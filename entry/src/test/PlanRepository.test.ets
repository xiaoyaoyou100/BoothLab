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
import {
  MEMORY_SNAPSHOT_STORAGE_DURABLE,
  MemorySnapshotStorage
} from '../main/ets/repository/MemorySnapshotStorage';
import {
  errorResult,
  okResult,
  validatePlan,
  validateStore
} from '../main/ets/repository/PlanValidator';
import { parseStore, serializeStore } from '../main/ets/repository/PlanSerializer';
import { PlanLibrary } from '../main/ets/components/plan/PlanLibrary';
import { PlanThumbnail } from '../main/ets/components/plan/PlanThumbnail';

const NOW: number = Date.now();

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
    throw new Error('Test fixture store did not serialize: ' + result.message);
  }
  return result.data;
}

function requireTextValue(value: string | null): string {
  if (value === null) {
    throw new Error('Expected persisted text.');
  }
  return value;
}

function requireFoundPlan(plans: BoothPlan[], planId: string): BoothPlan {
  const plan: BoothPlan | null = findPlan(plans, planId);
  if (plan === null) {
    throw new Error('Expected plan ' + planId + ' in list.');
  }
  return plan;
}

function requirePlan(result: OperationResult<BoothPlan>): BoothPlan {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected plan payload.');
  }
  return result.data;
}

function requireStore(result: OperationResult<PlanStore>): PlanStore {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected store payload.');
  }
  return result.data;
}

function requireText(result: OperationResult<string>): string {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected text payload.');
  }
  return result.data;
}

function requireBoolean(result: OperationResult<boolean>): boolean {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected boolean payload.');
  }
  return result.data;
}

function expectCode<T>(result: OperationResult<T>, code: string): void {
  expect(result.code).assertEqual(code);
}

function countPlan(plans: BoothPlan[], planId: string): number {
  let count: number = 0;
  for (let i = 0; i < plans.length; i++) {
    if (plans[i].id === planId) {
      count++;
    }
  }
  return count;
}

function findPlan(plans: BoothPlan[], planId: string): BoothPlan | null {
  for (let i = 0; i < plans.length; i++) {
    if (plans[i].id === planId) {
      return plans[i];
    }
  }
  return null;
}

/** Storage whose OK result has no data, exercising the undefined-data guard. */
class MissingDataSnapshotStorage implements SnapshotStorage {
  readPrimary(): Promise<OperationResult<string | null>> {
    const result: OperationResult<string | null> = {
      code: 'OK',
      message: '模拟读取成功但没有数据。'
    };
    return Promise.resolve(result);
  }

  readBackup(): Promise<OperationResult<string | null>> {
    const result: OperationResult<string | null> = {
      code: 'OK',
      message: '模拟读取成功但没有数据。'
    };
    return Promise.resolve(result);
  }

  write(primary: string, backup: string | null): Promise<OperationResult<boolean>> {
    return Promise.resolve(okResult<boolean>('模拟写入。', true));
  }
}

/** Test double that records writes and can fail reads/writes deterministically. */
class TestSnapshotStorage implements SnapshotStorage {
  primaryText: string | null = null;
  backupText: string | null = null;
  failWrites: boolean = false;
  failReads: boolean = false;
  rejectWrites: boolean = false;
  writeCount: number = 0;
  primaryReadCount: number = 0;
  backupReadCount: number = 0;
  lastWrittenPrimary: string | null = null;
  lastWrittenBackup: string | null = null;

  constructor(primaryText: string | null = null, backupText: string | null = null) {
    this.primaryText = primaryText;
    this.backupText = backupText;
  }

  readPrimary(): Promise<OperationResult<string | null>> {
    this.primaryReadCount = this.primaryReadCount + 1;
    if (this.failReads) {
      return Promise.resolve(errorResult<string | null>('PERSISTENCE_ERROR', '模拟主快照读取失败。'));
    }
    return Promise.resolve(okResult<string | null>('模拟主快照读取。', this.primaryText));
  }

  readBackup(): Promise<OperationResult<string | null>> {
    this.backupReadCount = this.backupReadCount + 1;
    if (this.failReads) {
      return Promise.resolve(errorResult<string | null>('PERSISTENCE_ERROR', '模拟备份读取失败。'));
    }
    return Promise.resolve(okResult<string | null>('模拟备份读取。', this.backupText));
  }

  write(primary: string, backup: string | null): Promise<OperationResult<boolean>> {
    if (this.failWrites) {
      return Promise.resolve(errorResult<boolean>('PERSISTENCE_ERROR', '模拟写入失败。'));
    }
    if (this.rejectWrites) {
      return Promise.reject(new Error('模拟写入 Promise 拒绝。'));
    }
    this.writeCount = this.writeCount + 1;
    this.primaryText = primary;
    this.backupText = backup;
    this.lastWrittenPrimary = primary;
    this.lastWrittenBackup = backup;
    return Promise.resolve(okResult<boolean>('模拟快照写入。', true));
  }
}

export default function planRepositoryTest() {
  describe('PlanRepositoryTest', () => {
    it('createPlanTrimsNameAndStartsWithEmptyObjectsAndPersists', 0,
      async (done: Function) => {
        const storage: TestSnapshotStorage = new TestSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        requireStore(await repository.recoverStore());

        const created: BoothPlan = requirePlan(await repository.createPlan('  春季展位  ', 'standard'));
        expect(created.name).assertEqual('春季展位');
        expect(created.templateId).assertEqual('standard');
        expect(created.objects.length).assertEqual(0);
        expect(Number.isFinite(created.createdAt)).assertTrue();
        expect(created.createdAt).assertEqual(created.updatedAt);
        expect(created.createdAt >= 0).assertTrue();

        expect(storage.writeCount).assertEqual(1);
        expect(storage.lastWrittenBackup === null).assertTrue();
        const persisted: PlanStore =
          requireStore(parseStore(requireTextValue(storage.lastWrittenPrimary)));
        expect(persisted.plans.length).assertEqual(1);
        expect(persisted.plans[0].id).assertEqual(created.id);
        expect(persisted.activePlanId === null).assertTrue();
        expect(repository.getSaveState()).assertEqual('Saved');
        done();
      });

    it('createPlanSupportsBothBuiltInTemplates', 0, async (done: Function) => {
      const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
      await repository.recoverStore();
      const standard: BoothPlan = requirePlan(await repository.createPlan('标准方案', 'standard'));
      const corner: BoothPlan = requirePlan(await repository.createPlan('转角方案', 'corner'));
      expect(standard.templateId).assertEqual('standard');
      expect(corner.templateId).assertEqual('corner');
      expect(standard.id === corner.id).assertFalse();
      const plans: BoothPlan[] = repository.listPlans();
      expect(plans.length).assertEqual(2);
      expect(countPlan(plans, standard.id)).assertEqual(1);
      expect(countPlan(plans, corner.id)).assertEqual(1);
      done();
    });

    it('createPlanEnforcesTrimmedNameBoundariesAndUnknownTemplate', 0,
      async (done: Function) => {
        const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
        await repository.recoverStore();

        const maxName: string = '123456789012345678901234567890';
        expect(maxName.length).assertEqual(30);
        const accepted: BoothPlan = requirePlan(await repository.createPlan(maxName, 'standard'));
        expect(accepted.name.length).assertEqual(30);

        expectCode(await repository.createPlan(maxName + '1', 'standard'), 'INVALID_ARGUMENT');
        expectCode(await repository.createPlan('   ', 'standard'), 'INVALID_ARGUMENT');
        expectCode(await repository.createPlan('有效名称', 'unknown-template'), 'INVALID_ARGUMENT');
        expect(repository.listPlans().length).assertEqual(1);
        done();
      });

    it('createPlanRejectsUnknownTemplateWithoutMutation', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      expectCode(await repository.createPlan('未知模板方案', 'island'), 'INVALID_ARGUMENT');
      expect(repository.listPlans().length).assertEqual(0);
      expect(repository.getStore().plans.length).assertEqual(0);
      expect(storage.writeCount).assertEqual(0);
      done();
    });

    it('threePlansHaveUniqueIdsAndFullyIndependentListObjects', 0,
      async (done: Function) => {
        const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
        await repository.recoverStore();
        const one: BoothPlan = requirePlan(await repository.createPlan('方案一', 'standard'));
        const two: BoothPlan = requirePlan(await repository.createPlan('方案二', 'standard'));
        const three: BoothPlan = requirePlan(await repository.createPlan('方案三', 'corner'));
        expect(one.id === two.id).assertFalse();
        expect(two.id === three.id).assertFalse();
        expect(one.id === three.id).assertFalse();

        const firstList: BoothPlan[] = repository.listPlans();
        expect(firstList.length).assertEqual(3);
        const target: BoothPlan = requireFoundPlan(firstList, one.id);
        target.name = '被篡改的名称';
        target.objects.push(makeObject('temp', 'chair', 100, 100, 0, 1));

        const secondList: BoothPlan[] = repository.listPlans();
        const reloaded: BoothPlan = requireFoundPlan(secondList, one.id);
        expect(reloaded.name).assertEqual('方案一');
        expect(reloaded.objects.length).assertEqual(0);

        const storeClone: PlanStore = repository.getStore();
        storeClone.plans[0].name = '篡改快照';
        expect(repository.getStore().plans[0].name).assertEqual('方案一');
        done();
      });

    it('savePlanPersistsRealObjectsAndListShowsThemWithIsolation', 0,
      async (done: Function) => {
        const storage: TestSnapshotStorage = new TestSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const created: BoothPlan = requirePlan(await repository.createPlan('带物件方案', 'standard'));
        created.objects.push(makeObject('obj-reception', 'reception', 300, 200, 0, 1));
        created.objects.push(makeObject('obj-chair', 'chair', 100, 100, 90, 2));
        created.updatedAt = created.createdAt + 1000;
        const saved: BoothPlan = requirePlan(await repository.savePlan(created));

        expect(saved.objects.length).assertEqual(2);
        expect(saved.objects[0].centerX).assertEqual(300);
        expect(saved.objects[1].rotation).assertEqual(90);

        const listed: BoothPlan[] = repository.listPlans();
        expect(listed.length).assertEqual(1);
        expect(listed[0].objects.length).assertEqual(2);
        expect(listed[0].objects[0].catalogId).assertEqual('reception');
        expect(listed[0].objects[1].centerX).assertEqual(100);

        const persisted: PlanStore =
          requireStore(parseStore(requireTextValue(storage.primaryText)));
        expect(persisted.plans[0].objects.length).assertEqual(2);

        saved.objects[0].centerX = -999;
        const reloaded: BoothPlan = requirePlan(repository.loadPlan(created.id));
        expect(reloaded.objects[0].centerX).assertEqual(300);
        done();
      });

    it('listPlansReturnsClonesSortedByUpdatedAtDescending', 0, async (done: Function) => {
      const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
      await repository.recoverStore();
      const first: BoothPlan = requirePlan(await repository.createPlan('排序一', 'standard'));
      const second: BoothPlan = requirePlan(await repository.createPlan('排序二', 'standard'));
      const third: BoothPlan = requirePlan(await repository.createPlan('排序三', 'standard'));

      first.updatedAt = NOW + 3000;
      second.updatedAt = NOW + 1000;
      third.updatedAt = NOW + 2000;
      requirePlan(await repository.savePlan(first));
      requirePlan(await repository.savePlan(second));
      requirePlan(await repository.savePlan(third));

      const plans: BoothPlan[] = repository.listPlans();
      expect(plans.length).assertEqual(3);
      expect(plans[0].id).assertEqual(first.id);
      expect(plans[1].id).assertEqual(third.id);
      expect(plans[2].id).assertEqual(second.id);
      expect(plans[0].updatedAt > plans[1].updatedAt).assertTrue();
      done();
    });

    it('savePlanRejectsImmutableTemplateAndCreatedAtChangesWithoutWriting', 0,
      async (done: Function) => {
        const storage: TestSnapshotStorage = new TestSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const created: BoothPlan = requirePlan(await repository.createPlan('原始名称', 'standard'));
        const writesBefore: number = storage.writeCount;

        const changedTemplate: BoothPlan = makePlan(created.id, '修改模板', 'corner', [],
          created.createdAt, created.updatedAt + 500);
        expectCode(await repository.savePlan(changedTemplate), 'INVALID_ARGUMENT');
        const changedCreatedAt: BoothPlan = makePlan(created.id, '修改创建时间', 'standard', [],
          created.createdAt + 1, created.updatedAt + 500);
        expectCode(await repository.savePlan(changedCreatedAt), 'INVALID_ARGUMENT');
        expect(storage.writeCount).assertEqual(writesBefore);
        expect(repository.listPlans()[0].name).assertEqual('原始名称');

        const valid: BoothPlan = makePlan(created.id, '合法修改', 'standard', [],
          created.createdAt, created.updatedAt + 500);
        const saved: BoothPlan = requirePlan(await repository.savePlan(valid));
        expect(saved.id).assertEqual(created.id);
        expect(saved.templateId).assertEqual('standard');
        expect(saved.createdAt).assertEqual(created.createdAt);
        expect(saved.name).assertEqual('合法修改');
        expect(saved.updatedAt).assertEqual(created.updatedAt + 500);
        done();
      });

    it('savePlanRejectsStaleUpdatedAtBeforeWriting', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      const created: BoothPlan = requirePlan(await repository.createPlan('基准方案', 'standard'));
      const current: BoothPlan = makePlan(created.id, '较新名称', 'standard', [],
        created.createdAt, created.updatedAt + 1000);
      requirePlan(await repository.savePlan(current));
      const writesBefore: number = storage.writeCount;

      const stale: BoothPlan = makePlan(created.id, '较旧名称', 'standard', [],
        created.createdAt, created.updatedAt + 500);
      expectCode(await repository.savePlan(stale), 'INVALID_ARGUMENT');
      expect(storage.writeCount).assertEqual(writesBefore);
      expect(repository.listPlans()[0].name).assertEqual('较新名称');
      done();
    });

    it('recoverStoreMissingPrimaryWithValidBackupRecoversBackup', 0,
      async (done: Function) => {
        const backupPlan: BoothPlan = makePlan('backup-only', '仅备份方案', 'standard', [],
          NOW, NOW);
        const backupText: string = serializedStore([backupPlan], backupPlan.id);
        const storage: TestSnapshotStorage = new TestSnapshotStorage(null, backupText);
        const repository: PlanRepository = new PlanRepository(storage);

        const recovered: OperationResult<PlanStore> = await repository.recoverStore();
        const store: PlanStore = requireStore(recovered);
        expect(recovered.message.indexOf('备份') >= 0).assertTrue();
        expect(store.plans.length).assertEqual(1);
        expect(store.plans[0].id).assertEqual(backupPlan.id);
        expect(store.activePlanId).assertEqual(backupPlan.id);
        expect(storage.writeCount).assertEqual(0);
        done();
      });

    it('recoverStoreOkResultWithoutDataIsPersistenceError', 0, async (done: Function) => {
      const repository: PlanRepository = new PlanRepository(new MissingDataSnapshotStorage());
      expectCode(await repository.recoverStore(), 'PERSISTENCE_ERROR');
      expect(repository.getStore().plans.length).assertEqual(0);
      expectCode(await repository.createPlan('缺数据后创建', 'standard'), 'PERSISTENCE_ERROR');
      done();
    });

    it('failedReloadAfterSuccessfulRecoveryBlocksAllMutations', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      const created: BoothPlan = requirePlan(await repository.createPlan('首轮方案', 'standard'));
      expect(repository.getSaveState()).assertEqual('Saved');

      storage.failReads = true;
      expectCode(await repository.recoverStore(), 'PERSISTENCE_ERROR');
      expectCode(await repository.createPlan('不应创建', 'standard'), 'PERSISTENCE_ERROR');
      const changed: BoothPlan = makePlan(created.id, '不应保存', 'standard', [],
        created.createdAt, created.updatedAt + 100);
      expectCode(await repository.savePlan(changed), 'PERSISTENCE_ERROR');
      expectCode(await repository.deletePlan(created.id, true), 'PERSISTENCE_ERROR');
      expect(repository.getSaveState()).assertEqual('SaveError');

      storage.failReads = false;
      requireStore(await repository.recoverStore());
      const afterRecovery: BoothPlan =
        requirePlan(await repository.createPlan('恢复后可创建', 'standard'));
      expect(afterRecovery.name).assertEqual('恢复后可创建');
      done();
    });

    it('rejectedStorageWriteSetsSaveErrorAndQueueSurvives', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      storage.rejectWrites = true;
      expectCode(await repository.createPlan('拒绝方案', 'standard'), 'PERSISTENCE_ERROR');
      expect(repository.listPlans().length).assertEqual(0);
      expect(repository.getSaveState()).assertEqual('SaveError');

      storage.rejectWrites = false;
      const recovered: BoothPlan = requirePlan(await repository.createPlan('队列仍可用', 'standard'));
      expect(recovered.name).assertEqual('队列仍可用');
      expect(repository.listPlans().length).assertEqual(1);
      done();
    });

    it('savePlanMissingPlanReturnsNotFoundWithoutMutation', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      const writesBefore: number = storage.writeCount;
      const missing: BoothPlan = makePlan('missing-plan', '不存在的方案', 'standard', [],
        NOW, NOW);
      expectCode(await repository.savePlan(missing), 'NOT_FOUND');
      expect(repository.listPlans().length).assertEqual(0);
      expect(storage.writeCount).assertEqual(writesBefore);
      done();
    });

    it('loadPlanReturnsCloneAndMissingLoadIsNotFound', 0, async (done: Function) => {
      const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
      await repository.recoverStore();
      const created: BoothPlan = requirePlan(await repository.createPlan('读取方案', 'standard'));
      const first: BoothPlan = requirePlan(repository.loadPlan(created.id));
      first.name = '加载后篡改';
      const second: BoothPlan = requirePlan(repository.loadPlan(created.id));
      expect(second.name).assertEqual('读取方案');
      expect(repository.getStore().activePlanId === null).assertTrue();
      expectCode(repository.loadPlan('missing-plan'), 'NOT_FOUND');
      done();
    });

    it('openPlanUpdatesActiveIdPersistentlyAcrossRecovery', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      const first: BoothPlan = requirePlan(await repository.createPlan('方案甲', 'standard'));
      const second: BoothPlan = requirePlan(await repository.createPlan('方案乙', 'corner'));
      const opened: BoothPlan = requirePlan(await repository.openPlan(second.id));
      expect(opened.id).assertEqual(second.id);
      expect(repository.getStore().activePlanId).assertEqual(second.id);

      const persisted: PlanStore =
        requireStore(parseStore(requireTextValue(storage.primaryText)));
      expect(persisted.activePlanId).assertEqual(second.id);

      const reopenedRepository: PlanRepository = new PlanRepository(storage);
      const recovered: PlanStore = requireStore(await reopenedRepository.recoverStore());
      expect(recovered.activePlanId).assertEqual(second.id);
      expect(countPlan(recovered.plans, first.id)).assertEqual(1);

      expectCode(await repository.openPlan('missing-plan'), 'NOT_FOUND');
      expect(repository.getStore().activePlanId).assertEqual(second.id);
      done();
    });

    it('cancelDeleteDoesNotMutateStoreOrPersist', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      const first: BoothPlan = requirePlan(await repository.createPlan('保留一', 'standard'));
      requirePlan(await repository.createPlan('保留二', 'standard'));
      const writesBefore: number = storage.writeCount;
      const cancelled: boolean = requireBoolean(await repository.deletePlan(first.id, false));
      expect(cancelled).assertFalse();
      expect(repository.listPlans().length).assertEqual(2);
      expect(storage.writeCount).assertEqual(writesBefore);
      done();
    });

    it('confirmedDeleteRemovesOnlyTargetAndClearsDeletedActivePlan', 0,
      async (done: Function) => {
        const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
        await repository.recoverStore();
        const first: BoothPlan = requirePlan(await repository.createPlan('删除一', 'standard'));
        const second: BoothPlan = requirePlan(await repository.createPlan('删除二', 'standard'));
        const third: BoothPlan = requirePlan(await repository.createPlan('删除三', 'corner'));
        requirePlan(await repository.openPlan(second.id));

        const deleted: boolean = requireBoolean(await repository.deletePlan(second.id, true));
        expect(deleted).assertTrue();
        const remaining: BoothPlan[] = repository.listPlans();
        expect(remaining.length).assertEqual(2);
        expect(countPlan(remaining, first.id)).assertEqual(1);
        expect(countPlan(remaining, third.id)).assertEqual(1);
        expect(countPlan(remaining, second.id)).assertEqual(0);
        expect(repository.getStore().activePlanId === null).assertTrue();
        expectCode(await repository.deletePlan(second.id, true), 'NOT_FOUND');
        done();
      });

    it('failedWriteReturnsPersistenceErrorWithoutPublishingCandidate', 0,
      async (done: Function) => {
        const original: BoothPlan = makePlan('plan-existing', '原有名称', 'standard', [], NOW, NOW);
        const storage: TestSnapshotStorage = new TestSnapshotStorage(
          serializedStore([original], original.id), null);
        const repository: PlanRepository = new PlanRepository(storage);
        requireStore(await repository.recoverStore());
        storage.failWrites = true;

        const changed: BoothPlan = makePlan(original.id, '不应保存', 'standard', [], NOW, NOW + 50);
        expectCode(await repository.savePlan(changed), 'PERSISTENCE_ERROR');
        const plans: BoothPlan[] = repository.listPlans();
        expect(plans.length).assertEqual(1);
        expect(plans[0].name).assertEqual('原有名称');
        expect(plans[0].updatedAt).assertEqual(NOW);
        expect(repository.getSaveState()).assertEqual('SaveError');
        expect(storage.writeCount).assertEqual(0);
        done();
      });

    it('failedCreateDoesNotFakeSaveOrPublishState', 0, async (done: Function) => {
      const storage: TestSnapshotStorage = new TestSnapshotStorage();
      storage.failWrites = true;
      const repository: PlanRepository = new PlanRepository(storage);
      expectCode(await repository.createPlan('失败方案', 'standard'), 'PERSISTENCE_ERROR');
      expect(repository.listPlans().length).assertEqual(0);
      expect(repository.getStore().plans.length).assertEqual(0);
      expect(repository.getSaveState()).assertEqual('SaveError');
      done();
    });

    it('savePlanSnapshotsCallerDataAtEnqueueTime', 0, async (done: Function) => {
      const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
      await repository.recoverStore();
      const created: BoothPlan = requirePlan(await repository.createPlan('快照方案', 'standard'));
      created.objects.push(makeObject('obj-chair', 'chair', 300, 200, 0, 1));
      created.updatedAt = created.createdAt + 10;

      const pending: Promise<OperationResult<BoothPlan>> = repository.savePlan(created);
      created.name = '调用后被修改';
      created.objects[0].centerX = -500;

      const saved: BoothPlan = requirePlan(await pending);
      expect(saved.name).assertEqual('快照方案');
      expect(saved.objects[0].centerX).assertEqual(300);
      done();
    });

    it('recoverStoreFallsBackToValidBackupWhenPrimaryIsCorrupt', 0,
      async (done: Function) => {
        const backupPlan: BoothPlan = makePlan('backup-plan', '备份方案', 'standard', [], NOW, NOW);
        const validBackup: string = serializedStore([backupPlan], backupPlan.id);
        const storage: TestSnapshotStorage = new TestSnapshotStorage('{not-json', validBackup);
        const repository: PlanRepository = new PlanRepository(storage);

        const recovered: OperationResult<PlanStore> = await repository.recoverStore();
        const store: PlanStore = requireStore(recovered);
        expect(recovered.message.length > 0).assertTrue();
        expect(store.plans.length).assertEqual(1);
        expect(store.plans[0].id).assertEqual(backupPlan.id);
        expect(store.activePlanId).assertEqual(backupPlan.id);
        expect(storage.writeCount).assertEqual(0);
        expect(storage.primaryText).assertEqual('{not-json');
        done();
      });

    it('recoverStoreProtectsUnknownSchemaWithoutReadingBackupOrOverwriting', 0,
      async (done: Function) => {
        const backupPlan: BoothPlan = makePlan('backup-plan', '备份方案', 'standard', [], NOW, NOW);
        const validBackup: string = serializedStore([backupPlan], null);
        const unsupported: string =
          '{"schemaVersion":2,"plans":[],"activePlanId":null}';
        const storage: TestSnapshotStorage = new TestSnapshotStorage(unsupported, validBackup);
        const repository: PlanRepository = new PlanRepository(storage);

        expectCode(await repository.recoverStore(), 'UNSUPPORTED_SCHEMA');
        expect(repository.getStore().plans.length).assertEqual(0);
        expect(storage.backupReadCount).assertEqual(0);
        expect(storage.writeCount).assertEqual(0);
        expect(storage.primaryText).assertEqual(unsupported);
        expectCode(await repository.createPlan('不应创建', 'standard'), 'UNSUPPORTED_SCHEMA');
        done();
      });

    it('recoverStoreReturnsCorruptedDataWhenPrimaryAndBackupAreInvalid', 0,
      async (done: Function) => {
        const storage: TestSnapshotStorage = new TestSnapshotStorage('{broken', '[]');
        const repository: PlanRepository = new PlanRepository(storage);
        expectCode(await repository.recoverStore(), 'CORRUPTED_DATA');
        expect(repository.getStore().plans.length).assertEqual(0);
        expect(repository.getStore().activePlanId === null).assertTrue();
        expect(storage.writeCount).assertEqual(0);
        done();
      });

    it('recoverStoreFirstLaunchReturnsEmptyStoreAndReadFailureIsPersistenceError', 0,
      async (done: Function) => {
        const emptyStorage: TestSnapshotStorage = new TestSnapshotStorage();
        const emptyRepository: PlanRepository = new PlanRepository(emptyStorage);
        const empty: PlanStore = requireStore(await emptyRepository.recoverStore());
        expect(empty.plans.length).assertEqual(0);
        expect(empty.activePlanId === null).assertTrue();
        expect(empty.schemaVersion).assertEqual(1);
        expect(emptyStorage.writeCount).assertEqual(0);

        const failingStorage: TestSnapshotStorage = new TestSnapshotStorage();
        failingStorage.failReads = true;
        const failingRepository: PlanRepository = new PlanRepository(failingStorage);
        expectCode(await failingRepository.recoverStore(), 'PERSISTENCE_ERROR');
        expectCode(await failingRepository.createPlan('读取失败后', 'standard'), 'PERSISTENCE_ERROR');
        done();
      });

    it('mutationsStayRefusedAfterFailedRecoveryUntilExplicitRecoverySucceeds', 0,
      async (done: Function) => {
        const storage: TestSnapshotStorage = new TestSnapshotStorage('{broken', null);
        const repository: PlanRepository = new PlanRepository(storage);
        expectCode(await repository.recoverStore(), 'CORRUPTED_DATA');
        expectCode(await repository.createPlan('拒绝创建', 'standard'), 'CORRUPTED_DATA');
        expect(repository.listPlans().length).assertEqual(0);

        storage.primaryText = serializedStore([], null);
        requireStore(await repository.recoverStore());
        const created: BoothPlan = requirePlan(await repository.createPlan('恢复后创建', 'standard'));
        expect(created.name).assertEqual('恢复后创建');
        done();
      });

    it('defaultMemoryStorageIsExplicitlyNotDurableButSupportsRepositoryFlow', 0,
      async (done: Function) => {
        expect(MEMORY_SNAPSHOT_STORAGE_DURABLE).assertFalse();
        const memoryStorage: MemorySnapshotStorage = new MemorySnapshotStorage();
        expect(memoryStorage.durable).assertFalse();
        expect(memoryStorage.durabilityNotice().length > 0).assertTrue();
        const repository: PlanRepository = new PlanRepository(memoryStorage);
        await repository.recoverStore();
        requirePlan(await repository.createPlan('内存方案', 'standard'));
        expect(repository.listPlans().length).assertEqual(1);
        done();
      });

    it('validatorRejectsOutOfBoundsDuplicateIdsAndIllegalRuntimeRotation', 0,
      async (done: Function) => {
        const outOfBounds: BoothPlan = makePlan('p-oob', '越界方案', 'standard',
          [makeObject('o1', 'chair', 10, 10, 0, 1)], NOW, NOW);
        expectCode(validatePlan(outOfBounds), 'OUT_OF_BOUNDS');

        const duplicateIds: BoothPlan = makePlan('p-dup', '重复物件', 'standard', [
          makeObject('same-id', 'chair', 100, 100, 0, 1),
          makeObject('same-id', 'chair', 300, 100, 0, 2)
        ], NOW, NOW);
        expectCode(validatePlan(duplicateIds), 'INVALID_ARGUMENT');

        const invalidRotationJson: string = '{"id":"p-rot","name":"非法旋转",' +
          '"templateId":"standard","objects":[{"id":"o1","catalogId":"chair",' +
          '"centerX":300,"centerY":200,"rotation":45,"zIndex":1}],' +
          '"createdAt":' + NOW.toString() + ',"updatedAt":' + NOW.toString() + '}';
        const invalidRotation: BoothPlan = JSON.parse(invalidRotationJson);
        expectCode(validatePlan(invalidRotation), 'INVALID_ARGUMENT');

        const nanCentre: BoothPlan = makePlan('p-nan', '非数字中心', 'standard',
          [makeObject('o1', 'chair', Number.NaN, 200, 0, 1)], NOW, NOW);
        expectCode(validatePlan(nanCentre), 'INVALID_ARGUMENT');
        done();
      });

    it('validatorAllowsReservedAreaOverlapButEnforcesStoreUniquenessAndActiveId', 0,
      async (done: Function) => {
        const reservedOverlap: BoothPlan = makePlan('p-reserved', '预留区提示', 'standard',
          [makeObject('o1', 'plant', 300, 370, 0, 1)], NOW, NOW);
        expectCode(validatePlan(reservedOverlap), 'OK');

        const planA: BoothPlan = makePlan('dup-plan', '方案甲', 'standard', [], NOW, NOW);
        const planB: BoothPlan = makePlan('dup-plan', '方案乙', 'corner', [], NOW, NOW);
        expectCode(validateStore(makeStore([planA, planB], null)), 'INVALID_ARGUMENT');

        const activeMissing: BoothPlan = makePlan('p1', '方案一', 'standard', [], NOW, NOW);
        expectCode(validateStore(makeStore([activeMissing], 'not-there')), 'INVALID_ARGUMENT');

        const malformedRoot: PlanStore = JSON.parse('[]');
        expectCode(validateStore(malformedRoot), 'INVALID_ARGUMENT');

        const repository: PlanRepository = new PlanRepository(new TestSnapshotStorage());
        await repository.recoverStore();
        const created: BoothPlan = requirePlan(await repository.createPlan('预留区保存', 'standard'));
        created.objects.push(makeObject('o1', 'plant', 300, 370, 0, 1));
        created.updatedAt = created.createdAt + 1;
        requirePlan(await repository.savePlan(created));
        done();
      });

    it('parseStoreRejectsMalformedShapesAndDistinguishesUnknownSchema', 0,
      async (done: Function) => {
        const malformed: string[] = [
          '',
          '   ',
          'null',
          '[]',
          '123',
          '"text"',
          'true',
          '{broken',
          '{"plans":[],"activePlanId":null}',
          '{"schemaVersion":1,"plans":{},"activePlanId":null}',
          '{"schemaVersion":1,"plans":[],"activePlanId":"missing"}'
        ];
        for (let i = 0; i < malformed.length; i++) {
          expectCode(parseStore(malformed[i]), 'CORRUPTED_DATA');
        }
        expectCode(parseStore('{"schemaVersion":2,"plans":[],"activePlanId":null}'),
          'UNSUPPORTED_SCHEMA');
        expectCode(parseStore('{"schemaVersion":"2","plans":[],"activePlanId":null}'),
          'CORRUPTED_DATA');
        done();
      });

    it('serializerRoundTripsAndDropsExtraSessionFields', 0, async (done: Function) => {
      const plan: BoothPlan = makePlan('plan-serial', '序列化方案', 'corner',
        [makeObject('obj-1', 'chair', 300, 200, 270, 3)], NOW, NOW + 7);
      const store: PlanStore = makeStore([plan], plan.id);
      const serialized: string = requireText(serializeStore(store));
      expect(serialized.indexOf('preview') === -1).assertTrue();
      expect(serialized.indexOf('history') === -1).assertTrue();

      const parsed: PlanStore = requireStore(parseStore(serialized));
      expect(parsed.plans.length).assertEqual(1);
      expect(parsed.plans[0].name).assertEqual('序列化方案');
      expect(parsed.plans[0].objects[0].rotation).assertEqual(270);
      expect(parsed.activePlanId).assertEqual('plan-serial');

      const withExtra: string = '{"schemaVersion":1,"plans":[{"id":"extra-plan",' +
        '"name":"多余字段","templateId":"standard","objects":[],"createdAt":' +
        NOW.toString() + ',"updatedAt":' + NOW.toString() +
        ',"preview":"pixels","history":[]}],"activePlanId":null,"viewport":{"scale":1}}';
      const extraParsed: PlanStore = requireStore(parseStore(withExtra));
      const reserialized: string = requireText(serializeStore(extraParsed));
      expect(reserialized.indexOf('preview') === -1).assertTrue();
      expect(reserialized.indexOf('history') === -1).assertTrue();
      expect(reserialized.indexOf('viewport') === -1).assertTrue();
      done();
    });

    it('planUiComponentsAreExportedForParentIntegration', 0, () => {
      // Compile-time integration guard: both B-owned components must stay
      // importable by the A page without the library importing repository code.
      expect(PlanLibrary !== undefined).assertTrue();
      expect(PlanThumbnail !== undefined).assertTrue();
    });
  });
}
