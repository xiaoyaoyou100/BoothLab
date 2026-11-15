/**
 * M2-PRECOMMIT-EDGE-FIX editor change notification regression tests.
 *
 * These tests exercise the real production path used by the editor page:
 * EditorController.importPlan -> a real effective operation -> the production
 * EditorChangeNotifier gate -> real SaveCoordinator -> real PlanRepository with
 * a controlled SnapshotStorage. The ArkUI struct itself cannot be instantiated
 * under Hypium, so the notifier seam is the production class the workspace
 * actually calls. No notification rule is re-implemented in this test file.
 *
 * The regression target is an archive whose updatedAt has reached the IEEE754
 * exact-integer boundary (2^53): adding 1 no longer changes the value, so an
 * updatedAt-only gate silently drops a real edit and the shell can keep the
 * draft Saved. An independent session revision must report every effective
 * committed operation regardless of the timestamp value.
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
import { EditorController } from '../main/ets/engine/EditorController';
import { EditorChangeNotifier } from '../main/ets/application/EditorChangeNotifier';
import { SaveCoordinator } from '../main/ets/application/SaveCoordinator';
import { PlanRepository } from '../main/ets/repository/PlanRepository';
import { errorResult, okResult } from '../main/ets/repository/PlanValidator';
import { serializeStore } from '../main/ets/repository/PlanSerializer';

const TWO_POW_53: number = 9007199254740992;
const TWO_POW_53_PLUS_2: number = 9007199254740994;
const TWO_POW_53_PLUS_4: number = 9007199254740996;
const MAX_SAFE_INTEGER: number = 9007199254740991;
const NORMAL_TIME: number = 1700000000000;
const BASE_CREATED_AT: number = 1000;

interface Session {
  controller: EditorController;
  notifier: EditorChangeNotifier;
  coordinator: SaveCoordinator;
  notifications: number;
}

interface PendingWrite {
  primary: string;
  backup: string | null;
  resolve: (result: OperationResult<boolean>) => void;
}

/** Storage that can seed an archive and hold writes until a test releases them. */
class ControlledSnapshotStorage implements SnapshotStorage {
  primaryText: string | null = null;
  backupText: string | null = null;
  deferWrites: boolean = false;
  writeCount: number = 0;
  writes: PendingWrite[] = [];

  readPrimary(): Promise<OperationResult<string | null>> {
    return Promise.resolve(okResult<string | null>('模拟主快照读取。', this.primaryText));
  }

  readBackup(): Promise<OperationResult<string | null>> {
    return Promise.resolve(okResult<string | null>('模拟备份读取。', this.backupText));
  }

  write(primary: string, backup: string | null): Promise<OperationResult<boolean>> {
    this.writeCount = this.writeCount + 1;
    if (this.deferWrites) {
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
    this.primaryText = primary;
    this.backupText = backup;
    return Promise.resolve(okResult<boolean>('模拟写入成功。', true));
  }

  resolveNext(succeed: boolean = true): boolean {
    const pending: PendingWrite | undefined = this.writes.shift();
    if (pending === undefined) {
      return false;
    }
    if (succeed) {
      this.primaryText = pending.primary;
      this.backupText = pending.backup;
      pending.resolve(okResult<boolean>('模拟延迟写入成功。', true));
    } else {
      pending.resolve(errorResult<boolean>('PERSISTENCE_ERROR', '模拟延迟写入失败。'));
    }
    return true;
  }
}

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

function makePlan(id: string, name: string, objects: PlacedObject[],
  createdAt: number, updatedAt: number): BoothPlan {
  const plan: BoothPlan = {
    id: id,
    name: name,
    templateId: 'standard',
    objects: objects,
    createdAt: createdAt,
    updatedAt: updatedAt
  };
  return plan;
}

function requirePlan(result: OperationResult<BoothPlan>): BoothPlan {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected a plan payload.');
  }
  return result.data;
}

function requireObject(result: OperationResult<PlacedObject>): PlacedObject {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected a placed-object payload.');
  }
  return result.data;
}

function requireText(result: OperationResult<string>): string {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected serialized store text.');
  }
  return result.data;
}

function seedStorage(storage: ControlledSnapshotStorage, plans: BoothPlan[]): void {
  const store: PlanStore = {
    schemaVersion: 1,
    plans: plans,
    activePlanId: null
  };
  storage.primaryText = requireText(serializeStore(store));
}

async function prepareRepository(storage: ControlledSnapshotStorage,
  plans: BoothPlan[]): Promise<PlanRepository> {
  seedStorage(storage, plans);
  const repository: PlanRepository = new PlanRepository(storage);
  const recovered: OperationResult<PlanStore> = await repository.recoverStore();
  expect(recovered.code).assertEqual('OK');
  return repository;
}

/** Builds a controller/notifier around a coordinator without binding it. */
function createSession(plan: BoothPlan, coordinator: SaveCoordinator): Session {
  const controller: EditorController = new EditorController('standard');
  requirePlan(controller.importPlan(plan));
  const notifier: EditorChangeNotifier = new EditorChangeNotifier();
  notifier.reset(controller.getChangeRevision());
  const session: Session = {
    controller: controller,
    notifier: notifier,
    coordinator: coordinator,
    notifications: 0
  };
  return session;
}

/**
 * Mirrors EditorWorkspace.aboutToAppear + Index.handleEditorChanged: importing
 * never notifies, and each notified snapshot is recorded by the real
 * SaveCoordinator (which marks the repository dirty).
 */
function openSession(repository: PlanRepository, plan: BoothPlan): Session {
  const coordinator: SaveCoordinator = new SaveCoordinator(repository);
  coordinator.bind(plan);
  return createSession(plan, coordinator);
}

/** Mirrors EditorWorkspace.refreshUi -> notifyFormalChangeIfNeeded. */
function refreshUi(session: Session): void {
  const exported = session.controller.exportPlan();
  if (exported.code !== 'OK' || exported.data === undefined) {
    return;
  }
  if (!session.notifier.shouldNotify(session.controller.getChangeRevision())) {
    return;
  }
  session.notifications = session.notifications + 1;
  const updated: OperationResult<boolean> = session.coordinator.update(exported.data);
  expect(updated.code).assertEqual('OK');
}

function syncAfter(session: Session, resultCode: string): void {
  expect(resultCode).assertEqual('OK');
  refreshUi(session);
}

async function settleMicrotasks(): Promise<void> {
  for (let i = 0; i < 64; i++) {
    await Promise.resolve();
  }
}

export default function editorChangeTest() {
  describe('EditorChangeTest', () => {
    // ------------------------------------------------------------------
    // Normal vs IEEE754-boundary timestamps
    // ------------------------------------------------------------------
    it('normalTimestampAddNotifiesOnceAndMarksDirty', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-normal', '正常方案', [], BASE_CREATED_AT, NORMAL_TIME);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));
      expect(session.notifications).assertEqual(0);
      expect(session.coordinator.getState()).assertEqual('Saved');

      syncAfter(session, session.controller.addObject('chair', { x: 100, y: 100 }).code);
      expect(session.notifications).assertEqual(1);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      expect(repository.getSaveState()).assertEqual('Dirty');

      // A second refresh without an operation must not notify again.
      refreshUi(session);
      expect(session.notifications).assertEqual(1);
      done();
    });

    it('twoPow53TimestampAddStillNotifiesOnceAndMarksDirty', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-2p53', '边界方案', [], BASE_CREATED_AT, TWO_POW_53);
      expect(plan.updatedAt + 1 === plan.updatedAt).assertTrue();
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      syncAfter(session, session.controller.addObject('chair', { x: 100, y: 100 }).code);
      expect(session.notifications).assertEqual(1);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      expect(repository.getSaveState()).assertEqual('Dirty');
      // The original finite metadata is preserved; it is not silently rewritten.
      const exported: BoothPlan = requirePlan(session.controller.exportPlan());
      expect(exported.updatedAt).assertEqual(TWO_POW_53);
      expect(Number.isFinite(exported.updatedAt)).assertTrue();
      done();
    });

    it('maxSafeIntegerThenUnchangedNeighbourBothNotify', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-safe', '安全整数方案', [],
        BASE_CREATED_AT, MAX_SAFE_INTEGER);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      // First edit advances MAX_SAFE_INTEGER -> 2^53 (still representable).
      const added = session.controller.addObject('chair', { x: 100, y: 100 });
      syncAfter(session, added.code);
      const chairId: string = requireObject(added).id;
      expect(session.notifications).assertEqual(1);
      expect(requirePlan(session.controller.exportPlan()).updatedAt).assertEqual(TWO_POW_53);

      // Second edit crosses the exact-integer boundary: +1 would be a no-op.
      syncAfter(session, session.controller.moveObject(chairId, { x: 120, y: 120 }).code);
      expect(session.notifications).assertEqual(2);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      expect(requirePlan(session.controller.exportPlan()).updatedAt).assertEqual(TWO_POW_53);
      done();
    });

    it('twoPow53PlusFourTimestampAddStillNotifies', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-2p53p4', '边界加四', [],
        BASE_CREATED_AT, TWO_POW_53_PLUS_4);
      expect(plan.updatedAt + 1 === plan.updatedAt).assertTrue();
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      syncAfter(session, session.controller.addObject('chair', { x: 100, y: 100 }).code);
      expect(session.notifications).assertEqual(1);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      done();
    });

    it('twoPow53PlusTwoTimestampAddStillNotifies', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-2p53p2', '边界加二', [],
        BASE_CREATED_AT, TWO_POW_53_PLUS_2);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      syncAfter(session, session.controller.addObject('chair', { x: 100, y: 100 }).code);
      expect(session.notifications).assertEqual(1);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      done();
    });

    // ------------------------------------------------------------------
    // One notification per effective operation
    // ------------------------------------------------------------------
    it('addMoveRotateDeleteUndoRedoEachNotifyOnce', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-ops', '操作方案', [], BASE_CREATED_AT, NORMAL_TIME);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      const added = session.controller.addObject('chair', { x: 100, y: 100 });
      syncAfter(session, added.code);
      const chairId: string = requireObject(added).id;
      expect(session.notifications).assertEqual(1);
      expect(session.coordinator.getState()).assertEqual('Dirty');

      syncAfter(session, session.controller.moveObject(chairId, { x: 160, y: 140 }).code);
      expect(session.notifications).assertEqual(2);

      syncAfter(session, session.controller.rotateObject(chairId).code);
      expect(session.notifications).assertEqual(3);

      syncAfter(session, session.controller.removeObject(chairId).code);
      expect(session.notifications).assertEqual(4);

      syncAfter(session, session.controller.undo().code);
      expect(session.notifications).assertEqual(5);

      syncAfter(session, session.controller.redo().code);
      expect(session.notifications).assertEqual(6);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      expect(repository.getSaveState()).assertEqual('Dirty');
      done();
    });

    it('extremeTimestampAllEffectiveOperationsEachNotifyOnce', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-ops-extreme', '极端操作', [],
        BASE_CREATED_AT, TWO_POW_53);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      const added = session.controller.addObject('chair', { x: 100, y: 100 });
      syncAfter(session, added.code);
      const chairId: string = requireObject(added).id;
      syncAfter(session, session.controller.moveObject(chairId, { x: 160, y: 140 }).code);
      syncAfter(session, session.controller.rotateObject(chairId).code);
      syncAfter(session, session.controller.removeObject(chairId).code);
      syncAfter(session, session.controller.undo().code);
      syncAfter(session, session.controller.redo().code);

      expect(session.notifications).assertEqual(6);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      expect(repository.getSaveState()).assertEqual('Dirty');
      done();
    });

    // ------------------------------------------------------------------
    // Rejected / no net change / preview-only work stays silent
    // ------------------------------------------------------------------
    it('failedAndNoNetChangeOperationsDoNotNotifyOrDirty', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-silent', '静默方案',
        [makeObject('obj-1', 'chair', 100, 100, 0, 1)], BASE_CREATED_AT, NORMAL_TIME);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      expect(session.controller.addObject('missing', { x: 100, y: 100 }).code)
        .assertEqual('NOT_FOUND');
      refreshUi(session);
      expect(session.controller.addObject('chair', { x: -200, y: -200 }).code)
        .assertEqual('OUT_OF_BOUNDS');
      refreshUi(session);
      expect(session.controller.moveObject('missing', { x: 100, y: 100 }).code)
        .assertEqual('NOT_FOUND');
      refreshUi(session);
      // Moving to the same centre is OK but records no effective change.
      expect(session.controller.moveObject('obj-1', { x: 100, y: 100 }).code)
        .assertEqual('OK');
      refreshUi(session);
      expect(session.controller.undo().code).assertEqual('NO_HISTORY');
      refreshUi(session);
      expect(session.controller.redo().code).assertEqual('NO_HISTORY');
      refreshUi(session);

      expect(session.notifications).assertEqual(0);
      expect(session.coordinator.getState()).assertEqual('Saved');
      expect(repository.getSaveState()).assertEqual('Saved');
      expect(session.controller.getObjects().length).assertEqual(1);
      done();
    });

    it('dragPreviewStaysSilentAndCommitNotifiesExactlyOnce', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-drag', '拖动方案',
        [makeObject('obj-1', 'chair', 100, 100, 0, 1)], BASE_CREATED_AT, TWO_POW_53);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      syncAfter(session, session.controller.beginDrag('obj-1', { x: 100, y: 100 }).code);
      expect(session.notifications).assertEqual(0);
      syncAfter(session, session.controller.updateDrag({ x: 200, y: 150 }).code);
      expect(session.notifications).assertEqual(0);
      syncAfter(session, session.controller.updateDrag({ x: 250, y: 160 }).code);
      expect(session.notifications).assertEqual(0);
      expect(session.coordinator.getState()).assertEqual('Saved');
      expect(repository.getSaveState()).assertEqual('Saved');

      syncAfter(session, session.controller.endDrag().code);
      expect(session.notifications).assertEqual(1);
      expect(session.coordinator.getState()).assertEqual('Dirty');
      expect(session.controller.getObjects()[0].centerX).assertEqual(250);
      expect(session.controller.getObjects()[0].centerY).assertEqual(160);
      done();
    });

    it('dragWithoutNetChangeDoesNotNotify', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-drag-same', '原地拖动',
        [makeObject('obj-1', 'chair', 100, 100, 0, 1)], BASE_CREATED_AT, NORMAL_TIME);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      syncAfter(session, session.controller.beginDrag('obj-1', { x: 100, y: 100 }).code);
      syncAfter(session, session.controller.updateDrag({ x: 120, y: 110 }).code);
      syncAfter(session, session.controller.updateDrag({ x: 100, y: 100 }).code);
      syncAfter(session, session.controller.endDrag().code);

      expect(session.notifications).assertEqual(0);
      expect(session.coordinator.getState()).assertEqual('Saved');
      expect(repository.getSaveState()).assertEqual('Saved');
      done();
    });

    it('selectionAndCancelledPreviewDoNotNotify', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-select', '选择方案',
        [makeObject('obj-1', 'chair', 100, 100, 0, 1)], BASE_CREATED_AT, NORMAL_TIME);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      expect(session.controller.selectObject('obj-1').code).assertEqual('OK');
      refreshUi(session);
      expect(session.controller.selectObject('missing').code).assertEqual('NOT_FOUND');
      refreshUi(session);
      expect(session.controller.selectObject(null).code).assertEqual('OK');
      refreshUi(session);
      syncAfter(session, session.controller.beginDrag('obj-1', { x: 100, y: 100 }).code);
      syncAfter(session, session.controller.updateDrag({ x: 300, y: 200 }).code);
      syncAfter(session, session.controller.cancelDrag().code);
      expect(session.notifications).assertEqual(0);
      expect(session.coordinator.getState()).assertEqual('Saved');
      done();
    });

    // ------------------------------------------------------------------
    // Save truthfulness and real snapshot reload
    // ------------------------------------------------------------------
    it('newEditWhileOldSavePendingRemainsDirtyAndLatestSaveWins', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const plan: BoothPlan = makePlan('plan-race', '并发方案', [],
          BASE_CREATED_AT, TWO_POW_53);
        const repository: PlanRepository = await prepareRepository(storage, [plan]);
        const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

        syncAfter(session, session.controller.addObject('chair', { x: 100, y: 100 }).code);
        expect(session.coordinator.getState()).assertEqual('Dirty');

        storage.deferWrites = true;
        const firstSave: Promise<OperationResult<BoothPlan>> = session.coordinator.save();
        expect(session.coordinator.getState()).assertEqual('Saving');
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);

        // A new effective edit arrives while the old write is pending.
        syncAfter(session, session.controller.addObject('plant', { x: 200, y: 150 }).code);
        expect(session.notifications).assertEqual(2);
        expect(session.coordinator.getState()).assertEqual('Dirty');

        storage.resolveNext(true);
        requirePlan(await firstSave);
        await settleMicrotasks();
        expect(session.coordinator.getState()).assertEqual('Dirty');
        expect(session.coordinator.isSaving()).assertFalse();

        const secondSave: Promise<OperationResult<BoothPlan>> = session.coordinator.save();
        await settleMicrotasks();
        storage.resolveNext(true);
        requirePlan(await secondSave);
        expect(session.coordinator.getState()).assertEqual('Saved');

        const persisted: BoothPlan = requirePlan(repository.loadPlan(plan.id));
        expect(persisted.objects.length).assertEqual(2);
        expect(persisted.updatedAt).assertEqual(TWO_POW_53);

        // Reopen from the serialized primary with a brand-new repository.
        const reopenedRepository: PlanRepository = new PlanRepository(storage);
        const recovered: OperationResult<PlanStore> = await reopenedRepository.recoverStore();
        expect(recovered.code).assertEqual('OK');
        const recoveredPlan: BoothPlan = requirePlan(reopenedRepository.loadPlan(plan.id));
        expect(recoveredPlan.objects.length).assertEqual(2);
        expect(Number.isFinite(recoveredPlan.updatedAt)).assertTrue();
        expect(recoveredPlan.updatedAt).assertEqual(TWO_POW_53);
        expect(recoveredPlan.objects[0].catalogId).assertEqual('chair');
        expect(recoveredPlan.objects[1].catalogId).assertEqual('plant');
        expect(recoveredPlan.objects[0].zIndex).assertEqual(1);
        expect(recoveredPlan.objects[1].zIndex).assertEqual(2);

        // The recovered snapshot can seed a new editor session and be edited.
        const reopenedController: EditorController = new EditorController('standard');
        requirePlan(reopenedController.importPlan(recoveredPlan));
        expect(reopenedController.moveObject(recoveredPlan.objects[0].id,
          { x: 120, y: 110 }).code).assertEqual('OK');
        done();
      });

    it('saveReloadsTheFormalSnapshotFromRepository', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const plan: BoothPlan = makePlan('plan-reload', '重载方案', [],
        BASE_CREATED_AT, NORMAL_TIME);
      const repository: PlanRepository = await prepareRepository(storage, [plan]);
      const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

      const added = session.controller.addObject('chair', { x: 100, y: 100 });
      syncAfter(session, added.code);
      const chairId: string = requireObject(added).id;
      syncAfter(session, session.controller.moveObject(chairId, { x: 160, y: 140 }).code);
      syncAfter(session, session.controller.rotateObject(chairId).code);
      const exported: BoothPlan = requirePlan(session.controller.exportPlan());
      requirePlan(await session.coordinator.save());
      expect(session.coordinator.getState()).assertEqual('Saved');

      const reloaded: BoothPlan = requirePlan(repository.loadPlan(plan.id));
      expect(reloaded.id).assertEqual(exported.id);
      expect(reloaded.name).assertEqual(exported.name);
      expect(reloaded.templateId).assertEqual(exported.templateId);
      expect(reloaded.createdAt).assertEqual(exported.createdAt);
      expect(reloaded.updatedAt).assertEqual(exported.updatedAt);
      expect(reloaded.objects.length).assertEqual(exported.objects.length);
      expect(reloaded.objects[0].id).assertEqual(exported.objects[0].id);
      expect(reloaded.objects[0].centerX).assertEqual(exported.objects[0].centerX);
      expect(reloaded.objects[0].centerY).assertEqual(exported.objects[0].centerY);
      expect(reloaded.objects[0].rotation).assertEqual(exported.objects[0].rotation);
      expect(reloaded.objects[0].catalogId).assertEqual(exported.objects[0].catalogId);
      expect(reloaded.objects[0].zIndex).assertEqual(exported.objects[0].zIndex);

      // Reopen the real serialized primary with a brand-new repository.
      const reopenedRepository: PlanRepository = new PlanRepository(storage);
      const recovered: OperationResult<PlanStore> = await reopenedRepository.recoverStore();
      expect(recovered.code).assertEqual('OK');
      const recoveredPlan: BoothPlan = requirePlan(reopenedRepository.loadPlan(plan.id));
      expect(recoveredPlan.id).assertEqual(exported.id);
      expect(recoveredPlan.name).assertEqual(exported.name);
      expect(recoveredPlan.templateId).assertEqual(exported.templateId);
      expect(recoveredPlan.createdAt).assertEqual(exported.createdAt);
      expect(recoveredPlan.updatedAt).assertEqual(exported.updatedAt);
      expect(recoveredPlan.objects.length).assertEqual(exported.objects.length);
      for (let i = 0; i < exported.objects.length; i++) {
        expect(recoveredPlan.objects[i].id).assertEqual(exported.objects[i].id);
        expect(recoveredPlan.objects[i].catalogId).assertEqual(exported.objects[i].catalogId);
        expect(recoveredPlan.objects[i].centerX).assertEqual(exported.objects[i].centerX);
        expect(recoveredPlan.objects[i].centerY).assertEqual(exported.objects[i].centerY);
        expect(recoveredPlan.objects[i].rotation).assertEqual(exported.objects[i].rotation);
        expect(recoveredPlan.objects[i].zIndex).assertEqual(exported.objects[i].zIndex);
      }
      done();
    });

    it('maxValueTimestampStaysFiniteAndEditIsStillSaved', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const plan: BoothPlan = makePlan('plan-max', '最大时间', [],
          BASE_CREATED_AT, Number.MAX_VALUE);
        const repository: PlanRepository = await prepareRepository(storage, [plan]);
        const session: Session = openSession(repository, requirePlan(repository.loadPlan(plan.id)));

        syncAfter(session, session.controller.addObject('chair', { x: 100, y: 100 }).code);
        expect(session.notifications).assertEqual(1);
        expect(session.coordinator.getState()).assertEqual('Dirty');

        const exported: BoothPlan = requirePlan(session.controller.exportPlan());
        expect(Number.isFinite(exported.updatedAt)).assertTrue();
        expect(exported.updatedAt).assertEqual(Number.MAX_VALUE);

        requirePlan(await session.coordinator.save());
        const reloaded: BoothPlan = requirePlan(repository.loadPlan(plan.id));
        expect(reloaded.objects.length).assertEqual(1);
        expect(Number.isFinite(reloaded.updatedAt)).assertTrue();
        expect(reloaded.updatedAt).assertEqual(Number.MAX_VALUE);

        // Reopen the real serialized primary with a brand-new repository.
        const reopenedRepository: PlanRepository = new PlanRepository(storage);
        const recovered: OperationResult<PlanStore> = await reopenedRepository.recoverStore();
        expect(recovered.code).assertEqual('OK');
        const recoveredPlan: BoothPlan = requirePlan(reopenedRepository.loadPlan(plan.id));
        expect(recoveredPlan.objects.length).assertEqual(1);
        expect(Number.isFinite(recoveredPlan.updatedAt)).assertTrue();
        expect(recoveredPlan.updatedAt).assertEqual(Number.MAX_VALUE);
        expect(recoveredPlan.objects[0].catalogId).assertEqual('chair');
        expect(recoveredPlan.objects[0].zIndex).assertEqual(1);

        // Editing still works after restoring the maximum finite timestamp.
        const reopenedController: EditorController = new EditorController('standard');
        requirePlan(reopenedController.importPlan(recoveredPlan));
        expect(reopenedController.moveObject(recoveredPlan.objects[0].id,
          { x: 160, y: 140 }).code).assertEqual('OK');
        const editedPlan: BoothPlan = requirePlan(reopenedController.exportPlan());
        expect(Number.isFinite(editedPlan.updatedAt)).assertTrue();
        expect(editedPlan.updatedAt).assertEqual(Number.MAX_VALUE);
        done();
      });

    // ------------------------------------------------------------------
    // Invalid timestamps and session isolation
    // ------------------------------------------------------------------
    it('nanInfinityAndNegativeTimestampsAreRejected', 0, async (done: Function) => {
      const controller: EditorController = new EditorController('standard');
      const good: BoothPlan = makePlan('plan-good', '有效方案', [],
        BASE_CREATED_AT, NORMAL_TIME);
      requirePlan(controller.importPlan(good));
      const before: BoothPlan = requirePlan(controller.exportPlan());

      const invalidTimestamps: number[] = [
        Number.NaN,
        Number.POSITIVE_INFINITY,
        Number.NEGATIVE_INFINITY,
        -1
      ];
      for (let i = 0; i < invalidTimestamps.length; i++) {
        const candidate: BoothPlan = makePlan('plan-bad-' + i.toString(), '无效时间', [],
          BASE_CREATED_AT, invalidTimestamps[i]);
        expect(controller.importPlan(candidate).code).assertEqual('INVALID_ARGUMENT');
      }
      const negativeCreated: BoothPlan = makePlan('plan-bad-created', '负创建时间', [],
        -1, NORMAL_TIME);
      expect(controller.importPlan(negativeCreated).code).assertEqual('INVALID_ARGUMENT');

      const after: BoothPlan = requirePlan(controller.exportPlan());
      expect(after.id).assertEqual(before.id);
      expect(after.updatedAt).assertEqual(before.updatedAt);
      expect(controller.getObjects().length).assertEqual(before.objects.length);
      done();
    });

    it('rebindIsolatesOldSessionAndOldCompletion', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const planA: BoothPlan = makePlan('plan-a', '方案甲', [],
        BASE_CREATED_AT, TWO_POW_53);
      const planB: BoothPlan = makePlan('plan-b', '方案乙', [],
        BASE_CREATED_AT + 1, NORMAL_TIME);
      const repository: PlanRepository = await prepareRepository(storage, [planA, planB]);
      const sessionA: Session = openSession(repository, requirePlan(repository.loadPlan(planA.id)));

      syncAfter(sessionA, sessionA.controller.addObject('chair', { x: 100, y: 100 }).code);
      expect(sessionA.notifications).assertEqual(1);

      storage.deferWrites = true;
      const oldSave: Promise<OperationResult<BoothPlan>> = sessionA.coordinator.save();
      await settleMicrotasks();
      expect(storage.writes.length).assertEqual(1);

      // Rebind the same coordinator to plan B with a fresh editor/notifier.
      sessionA.coordinator.bind(planB);
      const sessionB: Session = createSession(planB, sessionA.coordinator);
      expect(sessionB.notifications).assertEqual(0);
      expect(sessionB.coordinator.getState()).assertEqual('Saved');
      refreshUi(sessionB);
      expect(sessionB.notifications).assertEqual(0);

      storage.resolveNext(true);
      requirePlan(await oldSave);
      await settleMicrotasks();
      // The stale completion must not mark plan B saved or replace its draft.
      expect(sessionB.coordinator.getState()).assertEqual('Saved');
      expect(sessionB.coordinator.isSaving()).assertFalse();
      const draftB: BoothPlan | null = sessionB.coordinator.getDraft();
      expect(draftB !== null).assertTrue();
      if (draftB !== null) {
        expect(draftB.id).assertEqual(planB.id);
        expect(draftB.objects.length).assertEqual(0);
      }
      // The old request was still a real write for plan A.
      const persistedA: BoothPlan = requirePlan(repository.loadPlan(planA.id));
      expect(persistedA.objects.length).assertEqual(1);

      // Plan B notifies and becomes dirty independently.
      syncAfter(sessionB, sessionB.controller.addObject('plant', { x: 200, y: 150 }).code);
      expect(sessionB.notifications).assertEqual(1);
      expect(sessionB.coordinator.getState()).assertEqual('Dirty');
      done();
    });
  });
}
