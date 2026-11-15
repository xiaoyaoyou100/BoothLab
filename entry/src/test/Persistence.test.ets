/**
 * M2-B02 durable Preferences persistence tests.
 *
 * The fake PreferencesIO keeps a platform-like split between the in-memory
 * cache and the durable map: `put` only touches the cache and `flush` copies it
 * to durable. That is what makes flush-failure and cache-discard semantics real
 * rather than a repository-level mock that cannot show divergence.
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  BoothPlan,
  OperationResult,
  PlanStore,
  PlacedObject,
  Rotation
} from '../main/ets/model/BoothModels';
import { SnapshotStorage } from '../main/ets/model/M2Contracts';
import { PlanRepository } from '../main/ets/repository/PlanRepository';
import { errorResult, okResult } from '../main/ets/repository/PlanValidator';
import { parseStore, serializeStore } from '../main/ets/repository/PlanSerializer';
import {
  BACKUP_KEY,
  MAX_SNAPSHOT_TEXT_LENGTH,
  PREFERENCES_NAME,
  PRIMARY_KEY,
  PreferencesIO,
  PreferencesStore,
  RECOVERY_ARCHIVE_KEY_PREFIX,
  archiveBackupKey,
  archivePrimaryKey
} from '../main/ets/storage/PreferencesStore';
import {
  ArchivedSnapshot,
  RebuildResult,
  RebuildState
} from '../main/ets/repository/RecoveryContracts';

const NOW: number = Date.now();
const CORRUPT_PRIMARY: string = '{"schemaVersion":1,"plans":[';
const CORRUPT_BACKUP: string = '  not-json  ';
const FUTURE_STORE: string = '{"schemaVersion":2,"plans":[],"activePlanId":null}';

function makeObject(id: string, catalogId: string, centerX: number, centerY: number,
  rotation: Rotation, zIndex: number): PlacedObject {
  const object: PlacedObject = {
    id: id,
    catalogId: catalogId,
    centerX: centerX,
    centerY: centerY,
    rotation: rotation,
    zIndex: zIndex
  };
  return object;
}

function makePlan(id: string, name: string, templateId: string, objects: PlacedObject[],
  createdAt: number, updatedAt: number): BoothPlan {
  const plan: BoothPlan = {
    id: id,
    name: name,
    templateId: templateId,
    objects: objects,
    createdAt: createdAt,
    updatedAt: updatedAt
  };
  return plan;
}

function makeStore(plans: BoothPlan[], activePlanId: string | null): PlanStore {
  const store: PlanStore = {
    schemaVersion: 1,
    plans: plans,
    activePlanId: activePlanId
  };
  return store;
}

function serializedStore(plans: BoothPlan[], activePlanId: string | null): string {
  const result: OperationResult<string> = serializeStore(makeStore(plans, activePlanId));
  if (result.code !== 'OK' || result.data === undefined) {
    throw new Error('Test fixture did not serialize: ' + result.message);
  }
  return result.data;
}

function requirePlan(result: OperationResult<BoothPlan>): BoothPlan {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected plan data.');
  }
  return result.data;
}

function requireStore(result: OperationResult<PlanStore>): PlanStore {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected store data.');
  }
  return result.data;
}

function requireText(result: OperationResult<string | null>): string {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined || result.data === null) {
    throw new Error('Expected persisted text.');
  }
  return result.data;
}

function expectCode<T>(result: OperationResult<T>, code: string): void {
  expect(result.code).assertEqual(code);
}

function parsePersisted(text: string): PlanStore {
  return requireStore(parseStore(text));
}

function containsPlanName(plans: BoothPlan[], name: string): boolean {
  for (let i = 0; i < plans.length; i++) {
    if (plans[i].name === name) {
      return true;
    }
  }
  return false;
}

function findPlan(plans: BoothPlan[], planId: string): BoothPlan | null {
  for (let i = 0; i < plans.length; i++) {
    if (plans[i].id === planId) {
      return plans[i];
    }
  }
  return null;
}

function requireFoundPlan(plans: BoothPlan[], planId: string): BoothPlan {
  const plan: BoothPlan | null = findPlan(plans, planId);
  if (plan === null) {
    throw new Error('Expected plan ' + planId + '.');
  }
  return plan;
}

async function settleMicrotasks(): Promise<void> {
  for (let i = 0; i < 24; i++) {
    await Promise.resolve();
  }
}

/**
 * Fake with platform-like cache/durable divergence. Reads prefer the cache, as
 * platform Preferences does, so only discardCache + fresh read exposes durable
 * data after a failed flush.
 */
class FakePreferencesIO implements PreferencesIO {
  private durable: Map<string, string> = new Map<string, string>();
  private cached: Map<string, string> = new Map<string, string>();
  readCount: number = 0;
  putCount: number = 0;
  flushCount: number = 0;
  discardCount: number = 0;
  failRead: boolean = false;
  rejectRead: boolean = false;
  failPut: boolean = false;
  putReturnsFalse: boolean = false;
  rejectPut: boolean = false;
  failPutAtCall: number = 0;
  rejectFlush: boolean = false;
  flushReturnsFalse: boolean = false;
  failFlushAtCall: number = 0;
  failDiscard: boolean = false;
  rejectDiscard: boolean = false;
  wrongTypeKey: string | null = null;
  /** Simulates a storage adapter that itself reports UNSUPPORTED_SCHEMA. */
  unsupportedReadKey: string | null = null;
  /**
   * When set, any key starting with this prefix that is already durable is
   * returned with a different value. That simulates a platform read-back that
   * does not match what was flushed, without disturbing the initial archive id
   * existence checks.
   */
  corruptReadPrefix: string | null = null;

  seedDurable(key: string, value: string): void {
    this.durable.set(key, value);
  }

  durableValue(key: string): string | null {
    const value: string | undefined = this.durable.get(key);
    return value === undefined ? null : value;
  }

  cachedValue(key: string): string | null {
    const value: string | undefined = this.cached.get(key);
    return value === undefined ? null : value;
  }

  durableKeysWithPrefix(prefix: string): string[] {
    const keys: string[] = [];
    this.durable.forEach((value: string, key: string): void => {
      if (key.indexOf(prefix) === 0) {
        keys.push(key);
      }
    });
    return keys;
  }

  async read(key: string): Promise<OperationResult<string | null>> {
    this.readCount = this.readCount + 1;
    if (this.rejectRead) {
      throw new Error('模拟 Preferences read 拒绝。');
    }
    if (this.failRead) {
      return errorResult<string | null>('PERSISTENCE_ERROR', '模拟 Preferences read 失败。');
    }
    if (this.wrongTypeKey === key) {
      const wrongValue: Object = 42;
      return okResult<string | null>('模拟错误类型值。', wrongValue as string);
    }
    if (this.unsupportedReadKey === key) {
      return errorResult<string | null>('UNSUPPORTED_SCHEMA',
        '模拟存储层返回未来版本。');
    }
    if (this.corruptReadPrefix !== null && key.indexOf(this.corruptReadPrefix) === 0 &&
      this.durable.has(key)) {
      return okResult<string | null>('模拟归档读回不一致。', 'archive-readback-mismatch');
    }
    const cachedValue: string | null = this.cachedValue(key);
    if (cachedValue !== null) {
      return okResult<string | null>('模拟缓存读取。', cachedValue);
    }
    const durableValue: string | null = this.durableValue(key);
    return okResult<string | null>('模拟持久读取。', durableValue);
  }

  async put(key: string, value: string): Promise<OperationResult<boolean>> {
    this.putCount = this.putCount + 1;
    if (this.rejectPut) {
      throw new Error('模拟 Preferences put 拒绝。');
    }
    if (this.failPut) {
      return errorResult<boolean>('PERSISTENCE_ERROR', '模拟 Preferences put 失败。');
    }
    if (this.failPutAtCall > 0 && this.putCount === this.failPutAtCall) {
      return errorResult<boolean>('PERSISTENCE_ERROR', '模拟第 ' +
        this.putCount.toString() + ' 次 put 失败。');
    }
    if (this.putReturnsFalse) {
      return okResult<boolean>('模拟 put 未确认。', false);
    }
    this.cached.set(key, value);
    return okResult<boolean>('模拟 put 已写入缓存。', true);
  }

  async flush(): Promise<OperationResult<boolean>> {
    this.flushCount = this.flushCount + 1;
    if (this.rejectFlush) {
      throw new Error('模拟 Preferences flush 拒绝。');
    }
    if (this.failFlushAtCall > 0 && this.flushCount === this.failFlushAtCall) {
      return errorResult<boolean>('PERSISTENCE_ERROR', '模拟第 ' +
        this.flushCount.toString() + ' 次 flush 失败。');
    }
    if (this.flushReturnsFalse) {
      return okResult<boolean>('模拟 flush 未确认。', false);
    }
    this.cached.forEach((value: string, key: string): void => {
      this.durable.set(key, value);
    });
    return okResult<boolean>('模拟 flush 成功。', true);
  }

  async discardCache(): Promise<OperationResult<boolean>> {
    this.discardCount = this.discardCount + 1;
    if (this.rejectDiscard) {
      // The platform cache survives a rejected removal, including dirty puts.
      throw new Error('模拟 Preferences discardCache 拒绝。');
    }
    if (this.failDiscard) {
      // A failed removal leaves the dirty cached instance in place.
      return errorResult<boolean>('PERSISTENCE_ERROR', '模拟 Preferences discardCache 失败。');
    }
    this.cached.clear();
    return okResult<boolean>('模拟缓存已丢弃。', true);
  }
}

function newDurableRepository(io: FakePreferencesIO): PlanRepository {
  return new PlanRepository(new PreferencesStore(io));
}

async function recoveredRepository(io: FakePreferencesIO): Promise<PlanRepository> {
  const repository: PlanRepository = newDurableRepository(io);
  await repository.recoverStore();
  return repository;
}

interface RecoveryHarness {
  prefs: PreferencesStore;
  repository: PlanRepository;
}

function newRecoveryHarness(io: FakePreferencesIO): RecoveryHarness {
  const prefs: PreferencesStore = new PreferencesStore(io);
  const repository: PlanRepository = new PlanRepository(prefs, prefs);
  const harness: RecoveryHarness = {
    prefs: prefs,
    repository: repository
  };
  return harness;
}

function seedCorruptPair(io: FakePreferencesIO, primary: string, backup: string): void {
  io.seedDurable(PRIMARY_KEY, primary);
  io.seedDurable(BACKUP_KEY, backup);
}

function requireArchived(result: OperationResult<ArchivedSnapshot>): ArchivedSnapshot {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected archived snapshot.');
  }
  return result.data;
}

function requireRebuildId(result: RebuildResult): string {
  if (result.archiveId === null) {
    throw new Error('Expected an archive id for ' + result.status + '.');
  }
  return result.archiveId;
}

/** Asserts the text parses as the schema-1 empty store. */
function expectEmptyStoreText(text: string | null): void {
  if (text === null) {
    throw new Error('Expected empty-store text.');
  }
  const store: PlanStore = requireStore(parseStore(text));
  expect(store.schemaVersion).assertEqual(1);
  expect(store.plans.length).assertEqual(0);
  expect(store.activePlanId === null).assertTrue();
}

function expectState(state: RebuildState, phase: string, reason: string,
  rebuildable: boolean): void {
  expect(state.phase).assertEqual(phase);
  expect(state.reason).assertEqual(reason);
  expect(state.rebuildable).assertEqual(rebuildable);
}

interface PendingWrite {
  primary: string;
  backup: string | null;
  resolve: (result: OperationResult<boolean>) => void;
}

/** Storage whose write stays pending until the test resolves it. */
class DeferredSnapshotStorage implements SnapshotStorage {
  primaryText: string | null = null;
  backupText: string | null = null;
  writes: PendingWrite[] = [];
  writeCount: number = 0;
  inflight: number = 0;
  maxInflight: number = 0;

  constructor(primaryText: string | null, backupText: string | null) {
    this.primaryText = primaryText;
    this.backupText = backupText;
  }

  readPrimary(): Promise<OperationResult<string | null>> {
    return Promise.resolve(okResult<string | null>('模拟主快照读取。', this.primaryText));
  }

  readBackup(): Promise<OperationResult<string | null>> {
    return Promise.resolve(okResult<string | null>('模拟备份读取。', this.backupText));
  }

  write(primary: string, backup: string | null): Promise<OperationResult<boolean>> {
    this.writeCount = this.writeCount + 1;
    this.inflight = this.inflight + 1;
    if (this.inflight > this.maxInflight) {
      this.maxInflight = this.inflight;
    }
    return new Promise<OperationResult<boolean>>(
      (resolve: (result: OperationResult<boolean>) => void): void => {
        const pending: PendingWrite = {
          primary: primary,
          backup: backup,
          resolve: resolve
        };
        this.writes.push(pending);
      }
    );
  }

  resolveNext(): boolean {
    const pending: PendingWrite | undefined = this.writes.shift();
    if (pending === undefined) {
      return false;
    }
    this.inflight = this.inflight - 1;
    this.primaryText = pending.primary;
    this.backupText = pending.backup;
    pending.resolve(okResult<boolean>('模拟延迟写入成功。', true));
    return true;
  }
}

export default function persistenceTest() {
  describe('PersistenceTest', () => {
    it('freshInstallWithBothKeysMissingStartsEmptyWithoutWrites', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const repository: PlanRepository = newDurableRepository(io);
        const store: PlanStore = requireStore(await repository.recoverStore());
        expect(store.plans.length).assertEqual(0);
        expect(store.activePlanId === null).assertTrue();
        expect(io.putCount).assertEqual(0);
        expect(io.flushCount).assertEqual(0);
        expect(repository.getSaveState()).assertEqual('Saved');
        expect(PREFERENCES_NAME).assertEqual('boothlab_plans_v1');
        expect(PRIMARY_KEY).assertEqual('plans_primary_v1');
        expect(BACKUP_KEY).assertEqual('plans_backup_v1');
        done();
      });

    it('saveOnePlanAndReloadFromDurableFile', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      const repository: PlanRepository = await recoveredRepository(io);
      const created: BoothPlan =
        requirePlan(await repository.createPlan('持久方案', 'standard'));
      created.objects.push(makeObject('obj-1', 'chair', 300, 200, 0, 1));
      created.updatedAt = created.createdAt + 100;
      requirePlan(await repository.savePlan(created));

      const restarted: PlanRepository = await recoveredRepository(io);
      const plans: BoothPlan[] = restarted.listPlans();
      expect(plans.length).assertEqual(1);
      expect(plans[0].id).assertEqual(created.id);
      expect(plans[0].name).assertEqual('持久方案');
      expect(plans[0].objects.length).assertEqual(1);
      expect(plans[0].objects[0].catalogId).assertEqual('chair');
      done();
    });

    it('saveThreePlansAndReloadAllWithIsolatedReads', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      const repository: PlanRepository = await recoveredRepository(io);
      const one: BoothPlan = requirePlan(await repository.createPlan('方案一', 'standard'));
      const two: BoothPlan = requirePlan(await repository.createPlan('方案二', 'corner'));
      const three: BoothPlan = requirePlan(await repository.createPlan('方案三', 'standard'));
      expect(one.id === two.id).assertFalse();
      expect(two.id === three.id).assertFalse();

      const listed: BoothPlan[] = repository.listPlans();
      listed[0].name = '被篡改';
      listed[0].objects.push(makeObject('temp', 'chair', 100, 100, 0, 1));
      expect(repository.getStore().plans.length).assertEqual(3);
      expect(containsPlanName(repository.listPlans(), '被篡改')).assertFalse();

      const loaded: BoothPlan = requirePlan(repository.loadPlan(one.id));
      loaded.name = '加载后篡改';
      expect(requirePlan(repository.loadPlan(one.id)).name).assertEqual('方案一');

      const restarted: PlanRepository = await recoveredRepository(io);
      expect(restarted.listPlans().length).assertEqual(3);
      expect(requireFoundPlan(restarted.listPlans(), one.id).name).assertEqual('方案一');
      expect(requireFoundPlan(restarted.listPlans(), two.id).templateId).assertEqual('corner');
      done();
    });

    it('moveAndRotationPersistAcrossRestart', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      const repository: PlanRepository = await recoveredRepository(io);
      const created: BoothPlan =
        requirePlan(await repository.createPlan('移动旋转', 'standard'));
      created.objects.push(makeObject('obj-a', 'chair', 300, 200, 90, 2));
      created.objects.push(makeObject('obj-b', 'reception', 400, 250, 270, 1));
      created.updatedAt = created.createdAt + 200;
      requirePlan(await repository.savePlan(created));

      const restarted: PlanRepository = await recoveredRepository(io);
      const plan: BoothPlan = requireFoundPlan(restarted.listPlans(), created.id);
      expect(plan.objects.length).assertEqual(2);
      expect(plan.objects[0].centerX).assertEqual(300);
      expect(plan.objects[0].centerY).assertEqual(200);
      expect(plan.objects[0].rotation).assertEqual(90);
      expect(plan.objects[1].centerX).assertEqual(400);
      expect(plan.objects[1].rotation).assertEqual(270);
      expect(plan.objects[1].zIndex).assertEqual(1);
      done();
    });

    it('putFailureReturnsPersistenceErrorWithoutPublishing', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      io.failPut = true;
      const repository: PlanRepository = await recoveredRepository(io);
      expectCode(await repository.createPlan('失败方案', 'standard'), 'PERSISTENCE_ERROR');
      expect(repository.listPlans().length).assertEqual(0);
      expect(repository.getSaveState()).assertEqual('SaveError');
      expect(io.durableValue(PRIMARY_KEY) === null).assertTrue();
      expect(io.durableValue(BACKUP_KEY) === null).assertTrue();

      io.failPut = false;
      const retried: BoothPlan =
        requirePlan(await repository.createPlan('重试成功', 'standard'));
      expect(retried.name).assertEqual('重试成功');
      expect(repository.getSaveState()).assertEqual('Saved');
      done();
    });

    it('backupFlushFailureKeepsPreviousConfirmedSnapshotAndRetryWorks', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const repository: PlanRepository = await recoveredRepository(io);
        const created: BoothPlan =
          requirePlan(await repository.createPlan('初始版本', 'standard'));
        const originalPrimary: string = requireText(await new PreferencesStore(io).readPrimary());

        const changed: BoothPlan = makePlan(created.id, '备份失败版本', 'standard', [],
          created.createdAt, created.updatedAt + 10);
        io.failFlushAtCall = io.flushCount + 1; // backup flush fails first
        expectCode(await repository.savePlan(changed), 'PERSISTENCE_ERROR');
        expect(repository.listPlans()[0].name).assertEqual('初始版本');
        expect(repository.getSaveState()).assertEqual('SaveError');
        expect(io.discardCount > 0).assertTrue();
        expect(requireText(await new PreferencesStore(io).readPrimary())).assertEqual(originalPrimary);
        expect(io.durableValue(BACKUP_KEY) === null).assertTrue();

        io.failFlushAtCall = 0;
        const retried: BoothPlan =
          requirePlan(await repository.savePlan(changed));
        expect(retried.name).assertEqual('备份失败版本');
        const durable: PlanStore = parsePersisted(
          requireText(await new PreferencesStore(io).readPrimary()));
        expect(durable.plans[0].name).assertEqual('备份失败版本');
        expect(repository.getSaveState()).assertEqual('Saved');
        done();
      });

    it('primaryFlushFailureDiscardsCachedPutAndNextWriteDoesNotLeak', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const repository: PlanRepository = await recoveredRepository(io);
        const created: BoothPlan =
          requirePlan(await repository.createPlan('原始快照', 'standard'));
        const originalPrimary: string = requireText(await new PreferencesStore(io).readPrimary());

        const failedCandidate: BoothPlan = makePlan(created.id, '不应上盘的候选', 'standard',
          [], created.createdAt, created.updatedAt + 10);
        io.failFlushAtCall = io.flushCount + 2; // backup flush OK, primary flush fails
        expectCode(await repository.savePlan(failedCandidate), 'PERSISTENCE_ERROR');
        expect(repository.listPlans()[0].name).assertEqual('原始快照');
        expect(repository.getSaveState()).assertEqual('SaveError');
        expect(io.discardCount > 0).assertTrue();
        expect(io.cachedValue(PRIMARY_KEY) === null).assertTrue();

        // The failed cached put is gone; a fresh read sees only durable text.
        expect(requireText(await new PreferencesStore(io).readPrimary())).assertEqual(originalPrimary);
        const restarted: PlanRepository = await recoveredRepository(io);
        expect(restarted.listPlans()[0].name).assertEqual('原始快照');

        io.failFlushAtCall = 0;
        const newer: BoothPlan = makePlan(created.id, '真正的新版本', 'standard', [],
          created.createdAt, created.updatedAt + 20);
        requirePlan(await repository.savePlan(newer));
        const durableText: string = requireText(
          await new PreferencesStore(io).readPrimary());
        const durable: PlanStore = parsePersisted(durableText);
        expect(durable.plans[0].name).assertEqual('真正的新版本');
        expect(durableText.indexOf('不应上盘的候选') === -1).assertTrue();
        const durableBackup: PlanStore = parsePersisted(
          requireText(await new PreferencesStore(io).readBackup()));
        expect(durableBackup.plans[0].name).assertEqual('原始快照');
        done();
      });

    it('writeFalseAndRejectedPromisesFailClosedAndQueueSurvives', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const repository: PlanRepository = await recoveredRepository(io);

        io.putReturnsFalse = true;
        expectCode(await repository.createPlan('put未确认', 'standard'), 'PERSISTENCE_ERROR');
        io.putReturnsFalse = false;

        io.rejectPut = true;
        expectCode(await repository.createPlan('put拒绝', 'standard'), 'PERSISTENCE_ERROR');
        io.rejectPut = false;

        io.flushReturnsFalse = true;
        expectCode(await repository.createPlan('flush未确认', 'standard'), 'PERSISTENCE_ERROR');
        io.flushReturnsFalse = false;

        io.rejectFlush = true;
        expectCode(await repository.createPlan('flush拒绝', 'standard'), 'PERSISTENCE_ERROR');
        io.rejectFlush = false;

        expect(repository.listPlans().length).assertEqual(0);
        expect(repository.getSaveState()).assertEqual('SaveError');
        const created: BoothPlan =
          requirePlan(await repository.createPlan('队列存活', 'standard'));
        expect(created.name).assertEqual('队列存活');
        expect(repository.getSaveState()).assertEqual('Saved');
        done();
      });

    it('corruptPrimaryRecoversValidBackupWithoutOverwriting', 0, async (done: Function) => {
      const backupPlan: BoothPlan = makePlan('backup-plan', '备份方案', 'standard', [],
        NOW, NOW);
      const backupText: string = serializedStore([backupPlan], backupPlan.id);
      const io: FakePreferencesIO = new FakePreferencesIO();
      io.seedDurable(PRIMARY_KEY, '{not-json');
      io.seedDurable(BACKUP_KEY, backupText);
      const repository: PlanRepository = newDurableRepository(io);

      const recovered: OperationResult<PlanStore> = await repository.recoverStore();
      const store: PlanStore = requireStore(recovered);
      expect(recovered.message.indexOf('备份') >= 0).assertTrue();
      expect(store.plans.length).assertEqual(1);
      expect(store.plans[0].id).assertEqual(backupPlan.id);
      expect(io.putCount).assertEqual(0);
      expect(io.flushCount).assertEqual(0);
      expect(io.durableValue(PRIMARY_KEY)).assertEqual('{not-json');
      done();
    });

    it('missingPrimaryRecoversValidBackupWithExplicitMessage', 0, async (done: Function) => {
      const backupPlan: BoothPlan = makePlan('backup-only', '仅备份', 'corner', [],
        NOW, NOW);
      const io: FakePreferencesIO = new FakePreferencesIO();
      io.seedDurable(BACKUP_KEY, serializedStore([backupPlan], backupPlan.id));
      const repository: PlanRepository = newDurableRepository(io);

      const recovered: OperationResult<PlanStore> = await repository.recoverStore();
      const store: PlanStore = requireStore(recovered);
      expect(recovered.message.indexOf('缺失') >= 0).assertTrue();
      expect(recovered.message.indexOf('备份') >= 0).assertTrue();
      expect(store.plans.length).assertEqual(1);
      expect(store.plans[0].id).assertEqual(backupPlan.id);
      expect(io.putCount).assertEqual(0);
      done();
    });

    it('bothCorruptFailsWithoutOverwriteAndBlocksMutations', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      io.seedDurable(PRIMARY_KEY, '{broken');
      io.seedDurable(BACKUP_KEY, '[]');
      const repository: PlanRepository = newDurableRepository(io);

      expectCode(await repository.recoverStore(), 'CORRUPTED_DATA');
      expectCode(await repository.createPlan('不应创建', 'standard'), 'CORRUPTED_DATA');
      expect(io.putCount).assertEqual(0);
      expect(io.flushCount).assertEqual(0);
      expect(io.durableValue(PRIMARY_KEY)).assertEqual('{broken');
      expect(io.durableValue(BACKUP_KEY)).assertEqual('[]');
      done();
    });

    it('futureVersionPrimaryIsProtectedEvenWithValidBackup', 0, async (done: Function) => {
      const future: string = '{"schemaVersion":2,"plans":[],"activePlanId":null}';
      const backupPlan: BoothPlan = makePlan('backup-plan', '备份方案', 'standard', [],
        NOW, NOW);
      const io: FakePreferencesIO = new FakePreferencesIO();
      io.seedDurable(PRIMARY_KEY, future);
      io.seedDurable(BACKUP_KEY, serializedStore([backupPlan], null));
      const repository: PlanRepository = newDurableRepository(io);

      expectCode(await repository.recoverStore(), 'UNSUPPORTED_SCHEMA');
      expectCode(await repository.createPlan('不应创建', 'standard'), 'UNSUPPORTED_SCHEMA');
      expect(io.putCount).assertEqual(0);
      expect(io.durableValue(PRIMARY_KEY)).assertEqual(future);
      done();
    });

    it('failedReloadAfterSuccessBlocksWritesUntilRecoverySucceeds', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const repository: PlanRepository = await recoveredRepository(io);
        const created: BoothPlan =
          requirePlan(await repository.createPlan('已落盘方案', 'standard'));

        io.failRead = true;
        expectCode(await repository.recoverStore(), 'PERSISTENCE_ERROR');
        expectCode(await repository.createPlan('失败后创建', 'standard'), 'PERSISTENCE_ERROR');
        const changed: BoothPlan = makePlan(created.id, '失败后保存', 'standard', [],
          created.createdAt, created.updatedAt + 100);
        expectCode(await repository.savePlan(changed), 'PERSISTENCE_ERROR');
        expect(repository.getSaveState()).assertEqual('SaveError');

        io.failRead = false;
        requireStore(await repository.recoverStore());
        const after: BoothPlan =
          requirePlan(await repository.createPlan('恢复后创建', 'standard'));
        expect(after.name).assertEqual('恢复后创建');
        expect(repository.getSaveState()).assertEqual('Saved');
        done();
      });

    it('deferredWritesStaySerializedWithMaxOneInflight', 0, async (done: Function) => {
      const storage: DeferredSnapshotStorage = new DeferredSnapshotStorage(null, null);
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();

      const firstPromise: Promise<OperationResult<BoothPlan>> =
        repository.createPlan('延迟一', 'standard');
      await settleMicrotasks();
      expect(storage.writes.length).assertEqual(1);
      const secondPromise: Promise<OperationResult<BoothPlan>> =
        repository.createPlan('延迟二', 'standard');
      await settleMicrotasks();
      expect(storage.writes.length).assertEqual(1);

      expect(storage.resolveNext()).assertTrue();
      const first: BoothPlan = requirePlan(await firstPromise);
      await settleMicrotasks();
      expect(storage.writes.length).assertEqual(1);
      expect(storage.resolveNext()).assertTrue();
      const second: BoothPlan = requirePlan(await secondPromise);
      await settleMicrotasks();

      expect(storage.maxInflight).assertEqual(1);
      expect(first.id === second.id).assertFalse();
      expect(repository.listPlans().length).assertEqual(2);
      done();
    });

    it('deferredQueueCopiesSaveSnapshotBeforeTaskStartsAndKeepsOrder', 0,
      async (done: Function) => {
        const base: BoothPlan = makePlan('plan-base', '基准', 'standard', [], NOW, NOW);
        const storage: DeferredSnapshotStorage =
          new DeferredSnapshotStorage(serializedStore([base], base.id), null);
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();

        const openPromise: Promise<OperationResult<BoothPlan>> = repository.openPlan(base.id);
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);

        const incoming: BoothPlan = makePlan(base.id, '入队时快照', 'standard',
          [makeObject('obj-1', 'chair', 300, 200, 0, 1)], base.createdAt, NOW + 10);
        const savePromise: Promise<OperationResult<BoothPlan>> = repository.savePlan(incoming);
        incoming.name = '入队后篡改';
        incoming.objects[0].centerX = -999;
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);

        storage.resolveNext();
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);
        storage.resolveNext();
        const saved: BoothPlan = requirePlan(await savePromise);
        expect(saved.name).assertEqual('入队时快照');
        expect(saved.objects[0].centerX).assertEqual(300);
        const persisted: PlanStore = parsePersisted(storage.primaryText as string);
        expect(persisted.plans[0].name).assertEqual('入队时快照');
        expect(persisted.plans[0].objects[0].centerX).assertEqual(300);
        done();
      });

    it('markDirtyBeforeQueuedTaskStartsIsNotOverwrittenByOldCompletion', 0,
      async (done: Function) => {
        const base: BoothPlan = makePlan('plan-dirty', '基准', 'standard', [], NOW, NOW);
        const storage: DeferredSnapshotStorage =
          new DeferredSnapshotStorage(serializedStore([base], base.id), null);
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();

        const openPromise: Promise<OperationResult<BoothPlan>> = repository.openPlan(base.id);
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);

        const changed: BoothPlan = makePlan(base.id, '旧写入', 'standard', [],
          base.createdAt, NOW + 10);
        const savePromise: Promise<OperationResult<BoothPlan>> = repository.savePlan(changed);
        repository.markDirty(); // newer edit before the queued task starts
        expect(repository.getSaveState()).assertEqual('Dirty');

        storage.resolveNext();
        await openPromise;
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);
        storage.resolveNext();
        const saved: BoothPlan = requirePlan(await savePromise);
        expect(saved.name).assertEqual('旧写入');
        expect(repository.getSaveState()).assertEqual('Dirty');

        const latest: BoothPlan = makePlan(base.id, '最新写入', 'standard', [],
          base.createdAt, NOW + 20);
        const latestPromise: Promise<OperationResult<BoothPlan>> = repository.savePlan(latest);
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);
        storage.resolveNext();
        requirePlan(await latestPromise);
        expect(repository.getSaveState()).assertEqual('Saved');
        expect(repository.listPlans()[0].name).assertEqual('最新写入');
        done();
      });

    it('markDirtyWhileWriteAwaitsStaysDirtyUntilLatestSave', 0, async (done: Function) => {
      const base: BoothPlan = makePlan('plan-inflight', '基准', 'standard', [], NOW, NOW);
      const storage: DeferredSnapshotStorage =
        new DeferredSnapshotStorage(serializedStore([base], base.id), null);
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();

      const changed: BoothPlan = makePlan(base.id, '飞行中保存', 'standard', [],
        base.createdAt, NOW + 10);
      const savePromise: Promise<OperationResult<BoothPlan>> = repository.savePlan(changed);
      await settleMicrotasks();
      expect(storage.writes.length).assertEqual(1);
      repository.markDirty();
      storage.resolveNext();
      requirePlan(await savePromise);
      expect(repository.getSaveState()).assertEqual('Dirty');

      const latest: BoothPlan = makePlan(base.id, '结尾保存', 'standard', [],
        base.createdAt, NOW + 20);
      const latestPromise: Promise<OperationResult<BoothPlan>> = repository.savePlan(latest);
      await settleMicrotasks();
      storage.resolveNext();
      requirePlan(await latestPromise);
      expect(repository.getSaveState()).assertEqual('Saved');
      done();
    });

    it('staleQueuedSaveCannotReplaceNewerData', 0, async (done: Function) => {
      const base: BoothPlan = makePlan('plan-order', '基准', 'standard', [], NOW, NOW);
      const storage: DeferredSnapshotStorage =
        new DeferredSnapshotStorage(serializedStore([base], base.id), null);
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();

      const newer: BoothPlan = makePlan(base.id, '较新', 'standard', [],
        base.createdAt, NOW + 20);
      const older: BoothPlan = makePlan(base.id, '较旧', 'standard', [],
        base.createdAt, NOW + 10);
      const newerPromise: Promise<OperationResult<BoothPlan>> = repository.savePlan(newer);
      const olderPromise: Promise<OperationResult<BoothPlan>> = repository.savePlan(older);
      await settleMicrotasks();
      expect(storage.writes.length).assertEqual(1);
      storage.resolveNext();
      requirePlan(await newerPromise);
      await settleMicrotasks();
      expect(storage.writes.length).assertEqual(0);
      expectCode(await olderPromise, 'INVALID_ARGUMENT');
      expect(repository.listPlans()[0].name).assertEqual('较新');
      expect(parsePersisted(storage.primaryText as string).plans[0].name).assertEqual('较新');
      done();
    });

    it('deleteFlushFailureKeepsListAndActiveThenRetrySucceeds', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const repository: PlanRepository = await recoveredRepository(io);
        const first: BoothPlan =
          requirePlan(await repository.createPlan('删除保留一', 'standard'));
        const second: BoothPlan =
          requirePlan(await repository.createPlan('删除保留二', 'corner'));
        requirePlan(await repository.openPlan(second.id));
        expect(repository.getStore().activePlanId).assertEqual(second.id);

        io.failFlushAtCall = io.flushCount + 2; // primary flush fails after backup flush
        expectCode(await repository.deletePlan(second.id, true), 'PERSISTENCE_ERROR');
        expect(repository.listPlans().length).assertEqual(2);
        expect(repository.getStore().activePlanId).assertEqual(second.id);
        expect(repository.getSaveState()).assertEqual('SaveError');
        expect(io.discardCount > 0).assertTrue();

        io.failFlushAtCall = 0;
        const deleted: boolean =
          requireBooleanResult(await repository.deletePlan(second.id, true));
        expect(deleted).assertTrue();
        expect(repository.listPlans().length).assertEqual(1);
        expect(repository.getStore().activePlanId === null).assertTrue();
        const durable: PlanStore = parsePersisted(
          requireText(await new PreferencesStore(io).readPrimary()));
        expect(durable.plans.length).assertEqual(1);
        expect(durable.plans[0].id).assertEqual(first.id);
        expect(durable.activePlanId === null).assertTrue();
        done();
      });

    it('activePlanIdSurvivesRestart', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      const repository: PlanRepository = await recoveredRepository(io);
      const first: BoothPlan =
        requirePlan(await repository.createPlan('活动方案一', 'standard'));
      const second: BoothPlan =
        requirePlan(await repository.createPlan('活动方案二', 'corner'));
      requirePlan(await repository.openPlan(second.id));

      const restarted: PlanRepository = await recoveredRepository(io);
      const store: PlanStore = restarted.getStore();
      expect(store.activePlanId).assertEqual(second.id);
      expect(findPlan(restarted.listPlans(), first.id) !== null).assertTrue();
      done();
    });

    it('invalidCatalogRotationNaNAndDuplicateIdsAreRejectedWithoutPersistence', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const repository: PlanRepository = await recoveredRepository(io);
        const created: BoothPlan =
          requirePlan(await repository.createPlan('严格校验', 'standard'));
        const writesBefore: number = io.putCount;

        const unknownCatalog: BoothPlan = makePlan(created.id, '未知目录', 'standard',
          [makeObject('o1', 'not-a-catalog-item', 300, 200, 0, 1)],
          created.createdAt, created.updatedAt + 10);
        expectCode(await repository.savePlan(unknownCatalog), 'INVALID_ARGUMENT');

        const nanCentre: BoothPlan = makePlan(created.id, 'NaN中心', 'standard',
          [makeObject('o1', 'chair', Number.NaN, 200, 0, 1)],
          created.createdAt, created.updatedAt + 10);
        expectCode(await repository.savePlan(nanCentre), 'INVALID_ARGUMENT');

        const duplicateIds: BoothPlan = makePlan(created.id, '重复标识', 'standard', [
          makeObject('same', 'chair', 300, 200, 0, 1),
          makeObject('same', 'chair', 400, 200, 0, 2)
        ], created.createdAt, created.updatedAt + 10);
        expectCode(await repository.savePlan(duplicateIds), 'INVALID_ARGUMENT');

        const rotationText: string = '{"id":"' + created.id + '","name":"非法旋转",' +
          '"templateId":"standard","objects":[{"id":"o1","catalogId":"chair",' +
          '"centerX":300,"centerY":200,"rotation":45,"zIndex":1}],' +
          '"createdAt":' + created.createdAt.toString() + ',"updatedAt":' +
          (created.updatedAt + 10).toString() + '}';
        const invalidRotation: BoothPlan = JSON.parse(rotationText);
        expectCode(await repository.savePlan(invalidRotation), 'INVALID_ARGUMENT');

        expect(io.putCount).assertEqual(writesBefore);
        expect(repository.listPlans()[0].name).assertEqual('严格校验');
        done();
      });

    it('preferencesStoreValidatesWritesAndRejectsOversizedValues', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      const store: PreferencesStore = new PreferencesStore(io);

      expectCode(await store.write('{broken', null), 'CORRUPTED_DATA');
      expectCode(await store.write('{"schemaVersion":2,"plans":[],"activePlanId":null}', null),
        'UNSUPPORTED_SCHEMA');
      expect(io.putCount).assertEqual(0);

      let oversized: string = '';
      for (let i = 0; i <= MAX_SNAPSHOT_TEXT_LENGTH; i++) {
        oversized = oversized + 'x';
      }
      expectCode(await store.write(oversized, null), 'PERSISTENCE_ERROR');
      expect(io.putCount).assertEqual(0);
      done();
    });

    it('preferencesStoreReadWrongTypeAndIoErrorsAreExplicit', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      io.wrongTypeKey = PRIMARY_KEY;
      const store: PreferencesStore = new PreferencesStore(io);
      expectCode(await store.readPrimary(), 'CORRUPTED_DATA');

      io.wrongTypeKey = null;
      io.failRead = true;
      expectCode(await store.readPrimary(), 'PERSISTENCE_ERROR');
      io.failRead = false;
      io.rejectRead = true;
      expectCode(await store.readPrimary(), 'PERSISTENCE_ERROR');
      done();
    });

    it('preferencesStoreStandaloneFlushFailureDiscardsCachedPut', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      const store: PreferencesStore = new PreferencesStore(io);
      const original: string = serializedStore([], null);
      requireBooleanResult(await store.write(original, null));
      const candidate: string = serializedStore([
        makePlan('standalone-plan', '独立写入', 'standard', [], NOW, NOW)
      ], null);

      const flushBefore: number = io.flushCount;
      io.failFlushAtCall = flushBefore + 1;
      expectCode(await store.write(candidate, original), 'PERSISTENCE_ERROR');
      expect(io.discardCount > 0).assertTrue();
      expect(io.cachedValue(PRIMARY_KEY) === null).assertTrue();
      expect(requireText(await store.readPrimary())).assertEqual(original);

      io.failFlushAtCall = 0;
      requireBooleanResult(await store.write(candidate, original));
      expect(requireText(await store.readPrimary())).assertEqual(candidate);
      done();
    });

    it('discardReturnedFailureKeepsCacheUncertainAndBlocksUntilFreshDiscard', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const store: PreferencesStore = new PreferencesStore(io);
        const original: string = serializedStore([
          makePlan('original', '原始快照', 'standard', [], NOW, NOW)
        ], 'original');
        requireBooleanResult(await store.write(original, null));

        const failedCandidate: string = serializedStore([
          makePlan('candidate', '不应上盘的候选', 'standard', [], NOW, NOW + 10)
        ], 'candidate');
        io.failFlushAtCall = io.flushCount + 1; // primary flush fails
        io.failDiscard = true; // discard keeps the dirty cached instance
        expectCode(await store.write(failedCandidate, null), 'PERSISTENCE_ERROR');

        // The failed put is still in the platform cache because discard failed.
        expect(io.cachedValue(PRIMARY_KEY)).assertEqual(failedCandidate);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(original);

        // While cache invalidation is unconfirmed, reads must not return the
        // dirty value and writes must not reach put/flush.
        const putsBefore: number = io.putCount;
        const flushesBefore: number = io.flushCount;
        expectCode(await store.readPrimary(), 'PERSISTENCE_ERROR');
        expectCode(await store.readBackup(), 'PERSISTENCE_ERROR');
        expectCode(await store.write(failedCandidate, null), 'PERSISTENCE_ERROR');
        expectCode(await store.write(original, null), 'PERSISTENCE_ERROR');
        expect(io.putCount).assertEqual(putsBefore);
        expect(io.flushCount).assertEqual(flushesBefore);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(original);
        const durableNow: string = io.durableValue(PRIMARY_KEY) as string;
        expect(durableNow.indexOf('不应上盘的候选') === -1).assertTrue();

        // A successful discard plus fresh durable reads clears the uncertainty.
        io.failDiscard = false;
        io.failFlushAtCall = 0;
        expect(io.discardCount > 1).assertTrue();
        expect(requireText(await store.readPrimary())).assertEqual(original);
        const replacement: string = serializedStore([
          makePlan('replacement', '确认后的新快照', 'standard', [], NOW, NOW + 20)
        ], 'replacement');
        requireBooleanResult(await store.write(replacement, original));
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(replacement);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(original);
        const durableAfter: string = io.durableValue(PRIMARY_KEY) as string;
        expect(durableAfter.indexOf('不应上盘的候选') === -1).assertTrue();
        expect(parsePersisted(durableAfter).plans[0].name).assertEqual('确认后的新快照');
        done();
      });

    it('discardRejectedFailureKeepsCacheUncertainAndBlocksUntilFreshDiscard', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        const store: PreferencesStore = new PreferencesStore(io);
        const original: string = serializedStore([
          makePlan('original', '原始快照', 'standard', [], NOW, NOW)
        ], 'original');
        requireBooleanResult(await store.write(original, null));

        const failedCandidate: string = serializedStore([
          makePlan('candidate', '异常丢弃的候选', 'standard', [], NOW, NOW + 10)
        ], 'candidate');
        io.failFlushAtCall = io.flushCount + 1; // primary flush fails
        io.rejectDiscard = true; // discard throws, dirty cache survives
        expectCode(await store.write(failedCandidate, null), 'PERSISTENCE_ERROR');
        expect(io.cachedValue(PRIMARY_KEY)).assertEqual(failedCandidate);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(original);

        const putsBefore: number = io.putCount;
        const flushesBefore: number = io.flushCount;
        expectCode(await store.readPrimary(), 'PERSISTENCE_ERROR');
        expectCode(await store.write(failedCandidate, null), 'PERSISTENCE_ERROR');
        expect(io.putCount).assertEqual(putsBefore);
        expect(io.flushCount).assertEqual(flushesBefore);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(original);

        io.rejectDiscard = false;
        io.failFlushAtCall = 0;
        expect(requireText(await store.readPrimary())).assertEqual(original);
        const replacement: string = serializedStore([
          makePlan('replacement', '异常后恢复快照', 'standard', [], NOW, NOW + 20)
        ], 'replacement');
        requireBooleanResult(await store.write(replacement, original));
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(replacement);
        const durableAfter: string = io.durableValue(PRIMARY_KEY) as string;
        expect(durableAfter.indexOf('异常丢弃的候选') === -1).assertTrue();
        done();
      });
  });

  describe('RecoveryRebuildTest', () => {
    it('freshInstallHasNoRebuildOfferAndWritesNothing', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      const harness: RecoveryHarness = newRecoveryHarness(io);
      requireStore(await harness.repository.recoverStore());

      const state: RebuildState = harness.repository.getRebuildState();
      expectState(state, 'NOT_NEEDED', 'NO_REBUILD_NEEDED', false);
      expect(state.primary).assertEqual('MISSING');
      expect(state.backup).assertEqual('MISSING');
      expect(state.archiveAvailable).assertTrue();

      const result: RebuildResult = await harness.repository.rebuildStore(true);
      expect(result.status).assertEqual('NOT_REBUILDABLE');
      expect(io.putCount).assertEqual(0);
      expect(io.flushCount).assertEqual(0);
      expect(io.durableValue(PRIMARY_KEY) === null).assertTrue();
      expect(io.durableValue(BACKUP_KEY) === null).assertTrue();
      done();
    });

    it('corruptPrimaryValidBackupIsNotRebuildableAndIsNotTouched', 0,
      async (done: Function) => {
        const backupPlan: BoothPlan = makePlan('backup-plan', '备份方案', 'standard', [],
          NOW, NOW);
        const backupText: string = serializedStore([backupPlan], backupPlan.id);
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, backupText);
        const harness: RecoveryHarness = newRecoveryHarness(io);

        const recovered: PlanStore = requireStore(await harness.repository.recoverStore());
        expect(recovered.plans.length).assertEqual(1);
        expect(recovered.plans[0].id).assertEqual(backupPlan.id);

        const state: RebuildState = harness.repository.getRebuildState();
        expectState(state, 'NOT_NEEDED', 'NO_REBUILD_NEEDED', false);
        expect(state.primary).assertEqual('CORRUPTED');
        expect(state.backup).assertEqual('VALID');

        const result: RebuildResult = await harness.repository.rebuildStore(true);
        expect(result.status).assertEqual('NOT_REBUILDABLE');
        expect(io.putCount).assertEqual(0);
        expect(io.flushCount).assertEqual(0);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(backupText);
        done();
      });

    it('validPrimaryCorruptBackupLoadsPrimaryAndIsNotRebuildable', 0,
      async (done: Function) => {
        const primaryText: string = serializedStore([], null);
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, primaryText, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);

        requireStore(await harness.repository.recoverStore());
        const state: RebuildState = harness.repository.getRebuildState();
        expectState(state, 'NOT_NEEDED', 'NO_REBUILD_NEEDED', false);
        expect(state.primary).assertEqual('VALID');
        expect(state.backup).assertEqual('CORRUPTED');

        const result: RebuildResult = await harness.repository.rebuildStore(true);
        expect(result.status).assertEqual('NOT_REBUILDABLE');
        expect(io.putCount).assertEqual(0);
        expect(io.flushCount).assertEqual(0);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(primaryText);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        done();
      });

    it('bothCorruptRecoveryFailsButOffersRebuildWithoutWriting', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);

        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        const state: RebuildState = harness.repository.getRebuildState();
        expectState(state, 'READY', 'BOTH_CORRUPT', true);
        expect(state.primary).assertEqual('CORRUPTED');
        expect(state.backup).assertEqual('CORRUPTED');
        expect(state.archiveAvailable).assertTrue();
        expect(io.putCount).assertEqual(0);
        expect(io.flushCount).assertEqual(0);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        done();
      });

    it('cancelRebuildLeavesCorruptSnapshotsAndReviewStateUntouched', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        const putsBefore: number = io.putCount;
        const flushesBefore: number = io.flushCount;

        const result: RebuildResult = await harness.repository.rebuildStore(false);
        expect(result.status).assertEqual('CANCELLED');
        expect(result.archiveId === null).assertTrue();
        expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);
        expect(io.putCount).assertEqual(putsBefore);
        expect(io.flushCount).assertEqual(flushesBefore);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        expect(io.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length).assertEqual(0);
        done();
      });

    it('confirmedRebuildPreservesExactTextsThenWritesVerifiedEmptyStore', 0,
      async (done: Function) => {
        const primaryText: string = '  { "schemaVersion": 1, "plans": [  broken';
        const backupText: string = 'not-json-with-whitespace  ';
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, primaryText, backupText);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');

        const result: RebuildResult = await harness.repository.rebuildStore(true);
        expect(result.status).assertEqual('REBUILT');
        expect(result.message.length > 0).assertTrue();
        const archiveId: string = requireRebuildId(result);
        expect(result.store !== null).assertTrue();
        if (result.store !== null) {
          expect(result.store.plans.length).assertEqual(0);
          expect(result.store.activePlanId === null).assertTrue();
        }

        const archived: ArchivedSnapshot =
          requireArchived(await harness.prefs.readArchivedSnapshot(archiveId));
        expect(archived.archiveId).assertEqual(archiveId);
        expect(archived.primary).assertEqual(primaryText);
        expect(archived.backup).assertEqual(backupText);
        expect(io.durableValue(archivePrimaryKey(archiveId))).assertEqual(primaryText);
        expect(io.durableValue(archiveBackupKey(archiveId))).assertEqual(backupText);
        expectEmptyStoreText(io.durableValue(PRIMARY_KEY));
        expectEmptyStoreText(io.durableValue(BACKUP_KEY));

        const state: RebuildState = harness.repository.getRebuildState();
        expectState(state, 'REBUILT', 'ALREADY_REBUILT', false);
        expect(state.lastArchiveId).assertEqual(archiveId);
        expect(harness.repository.getSaveState()).assertEqual('Saved');
        done();
      });

    it('archivePutFailureBlocksRebuildAndRetrySucceeds', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
      const harness: RecoveryHarness = newRecoveryHarness(io);
      expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');

      const putsBefore: number = io.putCount;
      io.failPutAtCall = io.putCount + 1;
      const failed: RebuildResult = await harness.repository.rebuildStore(true);
      expect(failed.status).assertEqual('ARCHIVE_FAILED');
      expect(failed.message.indexOf('归档') >= 0).assertTrue();
      expect(io.putCount).assertEqual(putsBefore + 1);
      expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
      expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
      expect(io.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length).assertEqual(0);
      expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);

      io.failPutAtCall = 0;
      const retried: RebuildResult = await harness.repository.rebuildStore(true);
      expect(retried.status).assertEqual('REBUILT');
      expectEmptyStoreText(io.durableValue(PRIMARY_KEY));
      done();
    });

    it('archiveFlushFailureBlocksRebuildAndKeepsOriginalsForRetry', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');

        io.failFlushAtCall = io.flushCount + 1;
        const failed: RebuildResult = await harness.repository.rebuildStore(true);
        expect(failed.status).assertEqual('ARCHIVE_FAILED');
        expect(failed.message.indexOf('归档') >= 0).assertTrue();
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        expect(io.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length).assertEqual(0);
        expect(harness.repository.getSaveState()).assertEqual('SaveError');

        io.failFlushAtCall = 0;
        const retried: RebuildResult = await harness.repository.rebuildStore(true);
        expect(retried.status).assertEqual('REBUILT');
        expect(requireRebuildId(retried).length > 0).assertTrue();
        done();
      });

    it('emptyStorePutFailureDoesNotFakeSuccessAndRequiresFreshReview', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');

        // Archive uses two puts; the third put is the empty backup write.
        io.failPutAtCall = io.putCount + 3;
        const failed: RebuildResult = await harness.repository.rebuildStore(true);
        expect(failed.status).assertEqual('EMPTY_WRITE_FAILED');
        const archiveId: string = requireRebuildId(failed);
        const archived: ArchivedSnapshot =
          requireArchived(await harness.prefs.readArchivedSnapshot(archiveId));
        expect(archived.primary).assertEqual(CORRUPT_PRIMARY);
        expect(archived.backup).assertEqual(CORRUPT_BACKUP);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        expectState(harness.repository.getRebuildState(), 'BLOCKED', 'STATE_UNKNOWN', false);

        const blocked: RebuildResult = await harness.repository.rebuildStore(true);
        expect(blocked.status).assertEqual('NOT_REBUILDABLE');

        io.failPutAtCall = 0;
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);
        const retried: RebuildResult = await harness.repository.rebuildStore(true);
        expect(retried.status).assertEqual('REBUILT');
        expectEmptyStoreText(io.durableValue(PRIMARY_KEY));
        done();
      });

    it('emptyStorePrimaryFlushFailureThenNextInitializationRecoversEmpty', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');

        // Flush 1 is archive; flush 2 is empty backup; flush 3 is empty primary.
        io.failFlushAtCall = io.flushCount + 3;
        const failed: RebuildResult = await harness.repository.rebuildStore(true);
        expect(failed.status).assertEqual('EMPTY_WRITE_FAILED');
        const archiveId: string = requireRebuildId(failed);
        const archived: ArchivedSnapshot =
          requireArchived(await harness.prefs.readArchivedSnapshot(archiveId));
        expect(archived.primary).assertEqual(CORRUPT_PRIMARY);
        expect(archived.backup).assertEqual(CORRUPT_BACKUP);
        // Backup flushed empty, primary flush failed: partial keys are explicit.
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expectEmptyStoreText(io.durableValue(BACKUP_KEY));
        expectState(harness.repository.getRebuildState(), 'BLOCKED', 'STATE_UNKNOWN', false);
        expectCode(await harness.repository.createPlan('不应创建', 'standard'), 'CORRUPTED_DATA');

        io.failFlushAtCall = 0;
        const restarted: RecoveryHarness = newRecoveryHarness(io);
        const recovered: OperationResult<PlanStore> = await restarted.repository.recoverStore();
        const store: PlanStore = requireStore(recovered);
        expect(store.plans.length).assertEqual(0);
        expect(recovered.message.indexOf('备份') >= 0).assertTrue();
        const state: RebuildState = restarted.repository.getRebuildState();
        expectState(state, 'NOT_NEEDED', 'NO_REBUILD_NEEDED', false);
        expect(state.primary).assertEqual('CORRUPTED');
        expect(state.backup).assertEqual('VALID');
        expectEmptyStoreText(io.durableValue(BACKUP_KEY));
        done();
      });

    it('rebuiltStoreCanCreateAndSaveAndSurvivesRestart', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
      const harness: RecoveryHarness = newRecoveryHarness(io);
      expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
      const rebuilt: RebuildResult = await harness.repository.rebuildStore(true);
      expect(rebuilt.status).assertEqual('REBUILT');

      const created: BoothPlan =
        requirePlan(await harness.repository.createPlan('重建后方案', 'standard'));
      created.objects.push(makeObject('obj-1', 'chair', 300, 200, 0, 1));
      created.updatedAt = created.createdAt + 50;
      requirePlan(await harness.repository.savePlan(created));

      const durable: PlanStore = parsePersisted(
        requireText(await harness.prefs.readPrimary()));
      expect(durable.plans.length).assertEqual(1);
      expect(durable.plans[0].name).assertEqual('重建后方案');
      expect(durable.plans[0].objects.length).assertEqual(1);

      const restarted: RecoveryHarness = newRecoveryHarness(io);
      requireStore(await restarted.repository.recoverStore());
      const plans: BoothPlan[] = restarted.repository.listPlans();
      expect(plans.length).assertEqual(1);
      expect(plans[0].id).assertEqual(created.id);
      done();
    });

    it('newRepositoryRestartsFromRebuiltEmptyStoreAndArchiveRemains', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        const rebuilt: RebuildResult = await harness.repository.rebuildStore(true);
        expect(rebuilt.status).assertEqual('REBUILT');
        const archiveId: string = requireRebuildId(rebuilt);

        const restarted: RecoveryHarness = newRecoveryHarness(io);
        const recovered: PlanStore = requireStore(await restarted.repository.recoverStore());
        expect(recovered.plans.length).assertEqual(0);
        expect(recovered.activePlanId === null).assertTrue();
        const state: RebuildState = restarted.repository.getRebuildState();
        expectState(state, 'NOT_NEEDED', 'NO_REBUILD_NEEDED', false);
        expect(state.primary).assertEqual('VALID');
        expect(state.backup).assertEqual('VALID');

        const archived: ArchivedSnapshot =
          requireArchived(await restarted.prefs.readArchivedSnapshot(archiveId));
        expect(archived.primary).assertEqual(CORRUPT_PRIMARY);
        expect(archived.backup).assertEqual(CORRUPT_BACKUP);
        done();
      });

    it('futureSchemaInEitherSnapshotBlocksRebuildWithoutOverwrite', 0,
      async (done: Function) => {
        // Primary corrupt + backup future.
        const firstIo: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(firstIo, CORRUPT_PRIMARY, FUTURE_STORE);
        const first: RecoveryHarness = newRecoveryHarness(firstIo);
        expectCode(await first.repository.recoverStore(), 'UNSUPPORTED_SCHEMA');
        expectState(first.repository.getRebuildState(), 'BLOCKED', 'FUTURE_SCHEMA', false);
        expect(first.repository.getRebuildState().backup).assertEqual('UNSUPPORTED_SCHEMA');
        const firstResult: RebuildResult = await first.repository.rebuildStore(true);
        expect(firstResult.status).assertEqual('NOT_REBUILDABLE');
        expect(firstIo.putCount).assertEqual(0);
        expect(firstIo.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expect(firstIo.durableValue(BACKUP_KEY)).assertEqual(FUTURE_STORE);

        // Primary future + backup corrupt: backup must not be read for fallback.
        const secondIo: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(secondIo, FUTURE_STORE, CORRUPT_BACKUP);
        const second: RecoveryHarness = newRecoveryHarness(secondIo);
        expectCode(await second.repository.recoverStore(), 'UNSUPPORTED_SCHEMA');
        expectState(second.repository.getRebuildState(), 'BLOCKED', 'FUTURE_SCHEMA', false);
        const secondResult: RebuildResult = await second.repository.rebuildStore(true);
        expect(secondResult.status).assertEqual('NOT_REBUILDABLE');
        expect(secondIo.putCount).assertEqual(0);
        expect(secondIo.durableValue(PRIMARY_KEY)).assertEqual(FUTURE_STORE);
        expect(secondIo.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);

        // Valid primary + future backup: the whole store stays not ready so no
        // ordinary mutation can overwrite the future backup.
        const thirdIo: FakePreferencesIO = new FakePreferencesIO();
        const validPrimary: string = serializedStore([], null);
        seedCorruptPair(thirdIo, validPrimary, FUTURE_STORE);
        const third: RecoveryHarness = newRecoveryHarness(thirdIo);
        expectCode(await third.repository.recoverStore(), 'UNSUPPORTED_SCHEMA');
        const thirdState: RebuildState = third.repository.getRebuildState();
        expectState(thirdState, 'BLOCKED', 'FUTURE_SCHEMA', false);
        expect(thirdState.primary).assertEqual('VALID');
        expect(thirdState.backup).assertEqual('UNSUPPORTED_SCHEMA');
        const thirdResult: RebuildResult = await third.repository.rebuildStore(true);
        expect(thirdResult.status).assertEqual('NOT_REBUILDABLE');
        expect(thirdIo.putCount).assertEqual(0);
        expect(thirdIo.flushCount).assertEqual(0);
        expect(thirdIo.durableValue(PRIMARY_KEY)).assertEqual(validPrimary);
        expect(thirdIo.durableValue(BACKUP_KEY)).assertEqual(FUTURE_STORE);
        done();
      });

    it('validPrimaryFutureBackupBlocksAllMutationsAndPreservesBothKeys', 0,
      async (done: Function) => {
        const existing: BoothPlan = makePlan('existing-plan', '现有方案', 'standard',
          [], NOW, NOW);
        const primaryText: string = serializedStore([existing], existing.id);

        // Case 1: backup text parses as a future schema.
        const parseIo: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(parseIo, primaryText, FUTURE_STORE);
        const parseHarness: RecoveryHarness = newRecoveryHarness(parseIo);
        expectCode(await parseHarness.repository.recoverStore(), 'UNSUPPORTED_SCHEMA');
        const parseState: RebuildState = parseHarness.repository.getRebuildState();
        expectState(parseState, 'BLOCKED', 'FUTURE_SCHEMA', false);
        expect(parseState.primary).assertEqual('VALID');
        expect(parseState.backup).assertEqual('UNSUPPORTED_SCHEMA');
        expect(parseHarness.repository.getSaveState()).assertEqual('SaveError');

        const changed: BoothPlan = makePlan(existing.id, '不应保存', 'standard', [],
          existing.createdAt, existing.updatedAt + 10);
        expectCode(await parseHarness.repository.createPlan('不应创建', 'standard'),
          'UNSUPPORTED_SCHEMA');
        expectCode(await parseHarness.repository.savePlan(changed), 'UNSUPPORTED_SCHEMA');
        expectCode(await parseHarness.repository.openPlan(existing.id), 'UNSUPPORTED_SCHEMA');
        expectCode(await parseHarness.repository.deletePlan(existing.id, true),
          'UNSUPPORTED_SCHEMA');
        const parseRebuild: RebuildResult =
          await parseHarness.repository.rebuildStore(true);
        expect(parseRebuild.status).assertEqual('NOT_REBUILDABLE');
        expect(parseIo.putCount).assertEqual(0);
        expect(parseIo.flushCount).assertEqual(0);
        expect(parseIo.durableValue(PRIMARY_KEY)).assertEqual(primaryText);
        expect(parseIo.durableValue(BACKUP_KEY)).assertEqual(FUTURE_STORE);
        expect(parseIo.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length)
          .assertEqual(0);

        // Case 2: the storage adapter itself returns UNSUPPORTED_SCHEMA for the
        // backup read. No backup raw text is available, but the primary must
        // still not be published as ready.
        const codeIo: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(codeIo, primaryText, CORRUPT_BACKUP);
        codeIo.unsupportedReadKey = BACKUP_KEY;
        const codeHarness: RecoveryHarness = newRecoveryHarness(codeIo);
        expectCode(await codeHarness.repository.recoverStore(), 'UNSUPPORTED_SCHEMA');
        const codeState: RebuildState = codeHarness.repository.getRebuildState();
        expectState(codeState, 'BLOCKED', 'FUTURE_SCHEMA', false);
        expect(codeState.primary).assertEqual('VALID');
        expect(codeState.backup).assertEqual('UNSUPPORTED_SCHEMA');
        expect(codeHarness.repository.getSaveState()).assertEqual('SaveError');

        expectCode(await codeHarness.repository.createPlan('不应创建二', 'standard'),
          'UNSUPPORTED_SCHEMA');
        expectCode(await codeHarness.repository.savePlan(changed), 'UNSUPPORTED_SCHEMA');
        expectCode(await codeHarness.repository.openPlan(existing.id), 'UNSUPPORTED_SCHEMA');
        expectCode(await codeHarness.repository.deletePlan(existing.id, true),
          'UNSUPPORTED_SCHEMA');
        const codeRebuild: RebuildResult = await codeHarness.repository.rebuildStore(true);
        expect(codeRebuild.status).assertEqual('NOT_REBUILDABLE');
        expect(codeIo.putCount).assertEqual(0);
        expect(codeIo.flushCount).assertEqual(0);
        expect(codeIo.durableValue(PRIMARY_KEY)).assertEqual(primaryText);
        expect(codeIo.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        expect(codeIo.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length)
          .assertEqual(0);
        done();
      });

    it('ioFailureIsNotRebuildableAndWritesNothing', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
      const harness: RecoveryHarness = newRecoveryHarness(io);
      io.failRead = true;
      expectCode(await harness.repository.recoverStore(), 'PERSISTENCE_ERROR');
      expectState(harness.repository.getRebuildState(), 'BLOCKED', 'IO_ERROR', false);
      const blocked: RebuildResult = await harness.repository.rebuildStore(true);
      expect(blocked.status).assertEqual('NOT_REBUILDABLE');
      expect(io.putCount).assertEqual(0);
      expect(io.flushCount).assertEqual(0);

      // Reach READY, then fail the pre-rebuild re-read.
      io.failRead = false;
      expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
      expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);
      io.failRead = true;
      const putsBefore: number = io.putCount;
      const stale: RebuildResult = await harness.repository.rebuildStore(true);
      expect(stale.status).assertEqual('NOT_REBUILDABLE');
      expect(io.putCount).assertEqual(putsBefore);
      expectState(harness.repository.getRebuildState(), 'BLOCKED', 'IO_ERROR', false);

      // A fresh successful recovery re-reviews and permits an explicit rebuild.
      io.failRead = false;
      expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
      expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);
      const rebuilt: RebuildResult = await harness.repository.rebuildStore(true);
      expect(rebuilt.status).assertEqual('REBUILT');
      done();
    });

    it('uncertainCacheBlocksRebuildAndArchivePut', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
      const harness: RecoveryHarness = newRecoveryHarness(io);
      expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
      expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);

      const validEmpty: string = serializedStore([], null);
      io.failFlushAtCall = io.flushCount + 1;
      io.failDiscard = true;
      expectCode(await harness.prefs.write(validEmpty, null), 'PERSISTENCE_ERROR');
      expect(io.cachedValue(PRIMARY_KEY)).assertEqual(validEmpty);
      expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);

      const putsBefore: number = io.putCount;
      const result: RebuildResult = await harness.repository.rebuildStore(true);
      expect(result.status).assertEqual('NOT_REBUILDABLE');
      expect(result.message.indexOf('缓存') >= 0 || result.message.indexOf('读取') >= 0)
        .assertTrue();
      expect(io.putCount).assertEqual(putsBefore);
      expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
      expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
      expect(io.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length).assertEqual(0);
      expectState(harness.repository.getRebuildState(), 'BLOCKED', 'IO_ERROR', false);
      done();
    });

    it('concurrentConfirmationsRebuildOnlyOnceAndShareOneArchive', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');

        const firstPromise: Promise<RebuildResult> = harness.repository.rebuildStore(true);
        const secondPromise: Promise<RebuildResult> = harness.repository.rebuildStore(true);
        const first: RebuildResult = await firstPromise;
        const second: RebuildResult = await secondPromise;
        expect(first.status).assertEqual('REBUILT');
        expect(second.status).assertEqual('ALREADY_REBUILT');
        expect(second.archiveId === null).assertTrue();
        expect(io.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length).assertEqual(2);
        expectEmptyStoreText(io.durableValue(PRIMARY_KEY));
        expectEmptyStoreText(io.durableValue(BACKUP_KEY));
        expectState(harness.repository.getRebuildState(), 'REBUILT',
          'ALREADY_REBUILT', false);
        done();
      });

    it('secondRebuildUsesNewArchiveIdAndNeverOverwritesOldArchive', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        const first: RebuildResult = await harness.repository.rebuildStore(true);
        expect(first.status).assertEqual('REBUILT');
        const firstId: string = requireRebuildId(first);

        const secondPrimary: string = '{"schemaVersion":1,"plans":[second-break';
        const secondBackup: string = 'second-not-json';
        io.seedDurable(PRIMARY_KEY, secondPrimary);
        io.seedDurable(BACKUP_KEY, secondBackup);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);
        const second: RebuildResult = await harness.repository.rebuildStore(true);
        expect(second.status).assertEqual('REBUILT');
        const secondId: string = requireRebuildId(second);
        expect(firstId === secondId).assertFalse();

        const firstArchive: ArchivedSnapshot =
          requireArchived(await harness.prefs.readArchivedSnapshot(firstId));
        expect(firstArchive.primary).assertEqual(CORRUPT_PRIMARY);
        expect(firstArchive.backup).assertEqual(CORRUPT_BACKUP);
        const secondArchive: ArchivedSnapshot =
          requireArchived(await harness.prefs.readArchivedSnapshot(secondId));
        expect(secondArchive.primary).assertEqual(secondPrimary);
        expect(secondArchive.backup).assertEqual(secondBackup);
        expect(io.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length).assertEqual(4);
        done();
      });

    it('archiveReadbackMismatchIsRejectedBeforeEmptyWrite', 0, async (done: Function) => {
      const io: FakePreferencesIO = new FakePreferencesIO();
      seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
      const harness: RecoveryHarness = newRecoveryHarness(io);
      expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
      io.corruptReadPrefix = RECOVERY_ARCHIVE_KEY_PREFIX;

      const putsBefore: number = io.putCount;
      const flushesBefore: number = io.flushCount;
      const failed: RebuildResult = await harness.repository.rebuildStore(true);
      expect(failed.status).assertEqual('ARCHIVE_FAILED');
      expect(failed.message.indexOf('读回') >= 0).assertTrue();
      expect(io.putCount).assertEqual(putsBefore + 2);
      expect(io.flushCount).assertEqual(flushesBefore + 1);
      expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
      expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);

      io.corruptReadPrefix = null;
      const retried: RebuildResult = await harness.repository.rebuildStore(true);
      expect(retried.status).assertEqual('REBUILT');
      const archived: ArchivedSnapshot =
        requireArchived(await harness.prefs.readArchivedSnapshot(requireRebuildId(retried)));
      expect(archived.primary).assertEqual(CORRUPT_PRIMARY);
      expect(archived.backup).assertEqual(CORRUPT_BACKUP);
      expectEmptyStoreText(io.durableValue(PRIMARY_KEY));
      done();
    });

    it('oversizedCorruptTextIsRejectedBeforeAnyArchiveWrite', 0,
      async (done: Function) => {
        let oversized: string = '';
        for (let i = 0; i <= MAX_SNAPSHOT_TEXT_LENGTH; i++) {
          oversized = oversized + 'x';
        }
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, oversized, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);

        const putsBefore: number = io.putCount;
        const flushesBefore: number = io.flushCount;
        const failed: RebuildResult = await harness.repository.rebuildStore(true);
        expect(failed.status).assertEqual('ARCHIVE_FAILED');
        expect(failed.message.indexOf('上限') >= 0 || failed.message.indexOf('长度') >= 0)
          .assertTrue();
        expect(io.putCount).assertEqual(putsBefore);
        expect(io.flushCount).assertEqual(flushesBefore);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(oversized);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        done();
      });

    it('partialArchivePutFailureLeavesNoDurableArchiveAndRetryWorks', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');

        // First archive put succeeds in cache, second fails before flush.
        io.failPutAtCall = io.putCount + 2;
        const failed: RebuildResult = await harness.repository.rebuildStore(true);
        expect(failed.status).assertEqual('ARCHIVE_FAILED');
        expect(io.durableKeysWithPrefix(RECOVERY_ARCHIVE_KEY_PREFIX).length).assertEqual(0);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(CORRUPT_PRIMARY);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);

        io.failPutAtCall = 0;
        const retried: RebuildResult = await harness.repository.rebuildStore(true);
        expect(retried.status).assertEqual('REBUILT');
        const archived: ArchivedSnapshot =
          requireArchived(await harness.prefs.readArchivedSnapshot(requireRebuildId(retried)));
        expect(archived.primary).assertEqual(CORRUPT_PRIMARY);
        expect(archived.backup).assertEqual(CORRUPT_BACKUP);
        done();
      });

    it('externalChangeSinceReviewCausesStaleSnapshotWithoutWrites', 0,
      async (done: Function) => {
        const io: FakePreferencesIO = new FakePreferencesIO();
        seedCorruptPair(io, CORRUPT_PRIMARY, CORRUPT_BACKUP);
        const harness: RecoveryHarness = newRecoveryHarness(io);
        expectCode(await harness.repository.recoverStore(), 'CORRUPTED_DATA');
        expectState(harness.repository.getRebuildState(), 'READY', 'BOTH_CORRUPT', true);

        const externalPlan: BoothPlan = makePlan('external-plan', '外部新方案', 'standard',
          [], NOW, NOW);
        const externalText: string = serializedStore([externalPlan], externalPlan.id);
        io.seedDurable(PRIMARY_KEY, externalText);
        const putsBefore: number = io.putCount;
        const flushesBefore: number = io.flushCount;

        const stale: RebuildResult = await harness.repository.rebuildStore(true);
        expect(stale.status).assertEqual('STALE_SNAPSHOT');
        expect(stale.message.indexOf('变化') >= 0).assertTrue();
        expect(io.putCount).assertEqual(putsBefore);
        expect(io.flushCount).assertEqual(flushesBefore);
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(externalText);
        expect(io.durableValue(BACKUP_KEY)).assertEqual(CORRUPT_BACKUP);
        expectState(harness.repository.getRebuildState(), 'NOT_NEEDED',
          'NO_REBUILD_NEEDED', false);

        const recovered: PlanStore = requireStore(await harness.repository.recoverStore());
        expect(recovered.plans.length).assertEqual(1);
        expect(recovered.plans[0].id).assertEqual(externalPlan.id);
        const blocked: RebuildResult = await harness.repository.rebuildStore(true);
        expect(blocked.status).assertEqual('NOT_REBUILDABLE');
        expect(io.durableValue(PRIMARY_KEY)).assertEqual(externalText);
        done();
      });
  });
}

function requireBooleanResult(result: OperationResult<boolean>): boolean {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected boolean data.');
  }
  return result.data;
}
