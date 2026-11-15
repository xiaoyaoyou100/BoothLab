/**
 * M2-I01 SaveCoordinator truthfulness tests.
 *
 * These tests use the real PlanRepository plus a controlled SnapshotStorage so
 * every assertion is about an actual write/result, not a mocked constant. The
 * deferred storage lets a save stay pending while a newer edit or a re-bind
 * happens, which is exactly the race the coordinator must handle.
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
import { parseStore } from '../main/ets/repository/PlanSerializer';
import { SaveCoordinator } from '../main/ets/application/SaveCoordinator';

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

function changedPlan(base: BoothPlan, objects: PlacedObject[], updatedAt: number): BoothPlan {
  const plan: BoothPlan = {
    id: base.id,
    name: base.name,
    templateId: base.templateId,
    objects: objects,
    createdAt: base.createdAt,
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

function requireStore(result: OperationResult<PlanStore>): PlanStore {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected a store payload.');
  }
  return result.data;
}

function requireText(value: string | null): string {
  if (value === null) {
    throw new Error('Expected persisted text.');
  }
  return value;
}

function requireDraft(coordinator: SaveCoordinator): BoothPlan {
  const draft: BoothPlan | null = coordinator.getDraft();
  if (draft === null) {
    throw new Error('Expected a bound draft.');
  }
  return draft;
}

function parsePersisted(text: string): PlanStore {
  return requireStore(parseStore(text));
}

function findPlan(plans: BoothPlan[], planId: string): BoothPlan | null {
  for (let i = 0; i < plans.length; i++) {
    if (plans[i].id === planId) {
      return plans[i];
    }
  }
  return null;
}

async function settleMicrotasks(): Promise<void> {
  for (let i = 0; i < 64; i++) {
    await Promise.resolve();
  }
}

interface PendingWrite {
  primary: string;
  backup: string | null;
  resolve: (result: OperationResult<boolean>) => void;
}

/**
 * Test storage that can fail writes or hold them until the test resolves them.
 * Reads always succeed so recovery never interferes with the save scenarios.
 */
class ControlledSnapshotStorage implements SnapshotStorage {
  primaryText: string | null = null;
  backupText: string | null = null;
  failWrites: boolean = false;
  deferWrites: boolean = false;
  writeCount: number = 0;
  lastWrittenPrimary: string | null = null;
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
    return this.finishWrite(primary, backup);
  }

  private finishWrite(primary: string, backup: string | null):
    Promise<OperationResult<boolean>> {
    if (this.failWrites) {
      return Promise.resolve(
        errorResult<boolean>('PERSISTENCE_ERROR', '模拟写入失败。')
      );
    }
    this.primaryText = primary;
    this.backupText = backup;
    this.lastWrittenPrimary = primary;
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
      this.lastWrittenPrimary = pending.primary;
      pending.resolve(okResult<boolean>('模拟延迟写入成功。', true));
    } else {
      pending.resolve(
        errorResult<boolean>('PERSISTENCE_ERROR', '模拟延迟写入失败。')
      );
    }
    return true;
  }
}

export default function saveCoordinatorTest() {
  describe('SaveCoordinatorTest', () => {
    it('bindClonesEmptyDraftAndStartsSaved', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      requireStore(await repository.recoverStore());
      const created: BoothPlan =
        requirePlan(await repository.createPlan('空方案', 'standard'));

      const coordinator: SaveCoordinator = new SaveCoordinator(repository);
      coordinator.bind(created);
      expect(coordinator.getState()).assertEqual('Saved');
      expect(coordinator.isSaving()).assertFalse();

      const draft: BoothPlan = requireDraft(coordinator);
      expect(draft.id).assertEqual(created.id);
      expect(draft.name).assertEqual('空方案');
      expect(draft.objects.length).assertEqual(0);

      // The returned draft is an independent clone, not the internal snapshot.
      draft.name = '被篡改';
      draft.objects.push(makeObject('obj-tamper', 'chair', 100, 100, 0, 1));
      const reread: BoothPlan = requireDraft(coordinator);
      expect(reread.name).assertEqual('空方案');
      expect(reread.objects.length).assertEqual(0);

      // The bind input was cloned at call time.
      created.name = '输入被篡改';
      const afterInputTamper: BoothPlan = requireDraft(coordinator);
      expect(afterInputTamper.name).assertEqual('空方案');
      done();
    });

    it('updateMarksDirtyClonesAndRejectsImmutableMetadataChanges', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const created: BoothPlan =
          requirePlan(await repository.createPlan('编辑方案', 'standard'));

        const coordinator: SaveCoordinator = new SaveCoordinator(repository);
        coordinator.bind(created);

        const updated: BoothPlan = changedPlan(created,
          [makeObject('obj-1', 'display_table', 300, 200, 0, 1)],
          created.updatedAt + 100);
        const result: OperationResult<boolean> = coordinator.update(updated);
        expect(result.code).assertEqual('OK');
        expect(result.data === true).assertTrue();
        expect(coordinator.getState()).assertEqual('Dirty');
        expect(repository.getSaveState()).assertEqual('Dirty');

        // Caller-side mutation after update must not reach the draft.
        updated.objects[0].centerX = 999;
        updated.objects.push(makeObject('obj-2', 'chair', 120, 120, 0, 2));
        const draft: BoothPlan = requireDraft(coordinator);
        expect(draft.objects.length).assertEqual(1);
        expect(draft.objects[0].centerX).assertEqual(300);

        const wrongId: BoothPlan = changedPlan(created, [], created.updatedAt + 200);
        wrongId.id = 'other-plan';
        expect(coordinator.update(wrongId).code).assertEqual('INVALID_ARGUMENT');

        const wrongTemplate: BoothPlan = changedPlan(created, [],
          created.updatedAt + 300);
        wrongTemplate.templateId = 'corner';
        expect(coordinator.update(wrongTemplate).code).assertEqual('INVALID_ARGUMENT');

        const wrongCreatedAt: BoothPlan = changedPlan(created, [],
          created.updatedAt + 400);
        wrongCreatedAt.createdAt = created.createdAt + 1;
        expect(coordinator.update(wrongCreatedAt).code).assertEqual('INVALID_ARGUMENT');

        // Rejected identity changes never replaced the committed draft.
        const afterRejections: BoothPlan = requireDraft(coordinator);
        expect(afterRejections.objects.length).assertEqual(1);
        expect(afterRejections.objects[0].centerX).assertEqual(300);
        expect(coordinator.getState()).assertEqual('Dirty');
        done();
      });

    it('savePersistsActualSnapshotAndBecomesSaved', 0, async (done: Function) => {
      const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
      const repository: PlanRepository = new PlanRepository(storage);
      await repository.recoverStore();
      const created: BoothPlan =
        requirePlan(await repository.createPlan('保存方案', 'standard'));

      const coordinator: SaveCoordinator = new SaveCoordinator(repository);
      coordinator.bind(created);
      const objectA: PlacedObject =
        makeObject('obj-reception', 'reception', 300, 200, 0, 1);
      const objectB: PlacedObject =
        makeObject('obj-chair', 'chair', 100, 100, 90, 2);
      coordinator.update(changedPlan(created, [objectA, objectB],
        created.updatedAt + 100));

      const saved: BoothPlan = requirePlan(await coordinator.save());
      expect(saved.updatedAt).assertEqual(created.updatedAt + 100);
      expect(coordinator.getState()).assertEqual('Saved');
      expect(coordinator.isSaving()).assertFalse();

      // Actual repository view.
      const listed: BoothPlan[] = repository.listPlans();
      expect(listed.length).assertEqual(1);
      expect(listed[0].objects.length).assertEqual(2);
      expect(listed[0].objects[0].catalogId).assertEqual('reception');
      expect(listed[0].objects[1].rotation).assertEqual(90);

      // Actual persisted text: only formal plan fields, no session data.
      const text: string = requireText(storage.lastWrittenPrimary);
      expect(text.indexOf('preview') === -1).assertTrue();
      expect(text.indexOf('history') === -1).assertTrue();
      const persisted: PlanStore = parsePersisted(text);
      expect(persisted.plans.length).assertEqual(1);
      expect(persisted.plans[0].objects.length).assertEqual(2);
      expect(persisted.plans[0].objects[1].centerX).assertEqual(100);

      // The draft remains available for the next edit/save cycle.
      const draft: BoothPlan = requireDraft(coordinator);
      expect(draft.objects.length).assertEqual(2);
      done();
    });

    it('failedWriteShowsSaveErrorKeepsDraftAndRetrySucceeds', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const created: BoothPlan =
          requirePlan(await repository.createPlan('失败重试方案', 'standard'));

        const coordinator: SaveCoordinator = new SaveCoordinator(repository);
        coordinator.bind(created);
        coordinator.update(changedPlan(created,
          [makeObject('obj-1', 'chair', 300, 200, 0, 1)],
          created.updatedAt + 100));

        const createText: string = requireText(storage.lastWrittenPrimary);
        storage.failWrites = true;
        const failed: OperationResult<BoothPlan> = await coordinator.save();
        expect(failed.code).assertEqual('PERSISTENCE_ERROR');
        expect(coordinator.getState()).assertEqual('SaveError');
        expect(coordinator.isSaving()).assertFalse();

        // The draft survives the failure; the repository and disk stay unchanged.
        const draft: BoothPlan = requireDraft(coordinator);
        expect(draft.objects.length).assertEqual(1);
        expect(draft.objects[0].catalogId).assertEqual('chair');
        expect(repository.listPlans()[0].objects.length).assertEqual(0);
        expect(storage.lastWrittenPrimary).assertEqual(createText);
        expect(parsePersisted(createText).plans[0].objects.length).assertEqual(0);

        storage.failWrites = false;
        const retried: BoothPlan = requirePlan(await coordinator.save());
        expect(retried.objects.length).assertEqual(1);
        expect(coordinator.getState()).assertEqual('Saved');
        expect(repository.listPlans()[0].objects.length).assertEqual(1);
        expect(parsePersisted(requireText(storage.lastWrittenPrimary))
          .plans[0].objects.length).assertEqual(1);
        done();
      });

    it('newEditWhileOldSavePendingRemainsDirtyAndLatestSaveWins', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const created: BoothPlan =
          requirePlan(await repository.createPlan('并发编辑方案', 'standard'));

        const coordinator: SaveCoordinator = new SaveCoordinator(repository);
        coordinator.bind(created);
        const objectA: PlacedObject =
          makeObject('obj-a', 'display_table', 300, 200, 0, 1);
        coordinator.update(changedPlan(created, [objectA], created.updatedAt + 100));

        storage.deferWrites = true;
        const first: Promise<OperationResult<BoothPlan>> = coordinator.save();
        expect(coordinator.getState()).assertEqual('Saving');
        expect(coordinator.isSaving()).assertTrue();
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);

        // New edit while the first write is still pending.
        const objectB: PlacedObject = makeObject('obj-b', 'chair', 100, 100, 0, 2);
        coordinator.update(changedPlan(created, [objectA, objectB],
          created.updatedAt + 200));
        expect(coordinator.getState()).assertEqual('Dirty');
        expect(coordinator.isSaving()).assertTrue();

        storage.resolveNext(true);
        requirePlan(await first);
        await settleMicrotasks();
        // The older completion must not report the newer edit as Saved.
        expect(coordinator.getState()).assertEqual('Dirty');
        expect(coordinator.isSaving()).assertFalse();

        const second: Promise<OperationResult<BoothPlan>> = coordinator.save();
        expect(coordinator.getState()).assertEqual('Saving');
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);
        storage.resolveNext(true);
        requirePlan(await second);

        expect(coordinator.getState()).assertEqual('Saved');
        expect(coordinator.isSaving()).assertFalse();
        const listed: BoothPlan[] = repository.listPlans();
        expect(listed[0].objects.length).assertEqual(2);
        const persisted: PlanStore =
          parsePersisted(requireText(storage.lastWrittenPrimary));
        expect(persisted.plans[0].objects.length).assertEqual(2);
        expect(persisted.plans[0].objects[1].catalogId).assertEqual('chair');
        done();
      });

    it('inputAndReturnedDraftArraysAreIsolatedBeforeSave', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const created: BoothPlan =
          requirePlan(await repository.createPlan('隔离方案', 'standard'));

        const coordinator: SaveCoordinator = new SaveCoordinator(repository);
        coordinator.bind(created);
        const objects: PlacedObject[] = [
          makeObject('obj-1', 'display_table', 300, 200, 0, 1)
        ];
        coordinator.update(changedPlan(created, objects, created.updatedAt + 100));

        // Mutating the caller's array after update must not change the draft.
        objects[0].centerX = -50;
        objects.push(makeObject('obj-2', 'chair', 100, 100, 0, 2));
        const draft: BoothPlan = requireDraft(coordinator);
        expect(draft.objects.length).assertEqual(1);
        expect(draft.objects[0].centerX).assertEqual(300);

        // Mutating the clone returned by getDraft must not change the draft.
        draft.objects[0].centerY = 999;
        draft.objects.push(makeObject('obj-3', 'plant', 80, 80, 0, 3));
        const again: BoothPlan = requireDraft(coordinator);
        expect(again.objects.length).assertEqual(1);
        expect(again.objects[0].centerY).assertEqual(200);

        requirePlan(await coordinator.save());
        expect(repository.listPlans()[0].objects.length).assertEqual(1);
        expect(repository.listPlans()[0].objects[0].centerX).assertEqual(300);
        expect(repository.listPlans()[0].objects[0].centerY).assertEqual(200);
        done();
      });

    it('oldCompletionAfterRebindDoesNotPolluteNewSession', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const firstPlan: BoothPlan =
          requirePlan(await repository.createPlan('方案甲', 'standard'));
        const secondPlan: BoothPlan =
          requirePlan(await repository.createPlan('方案乙', 'standard'));

        const coordinator: SaveCoordinator = new SaveCoordinator(repository);
        coordinator.bind(firstPlan);
        coordinator.update(changedPlan(firstPlan,
          [makeObject('obj-1', 'chair', 300, 200, 0, 1)],
          firstPlan.updatedAt + 100));

        storage.deferWrites = true;
        const oldSave: Promise<OperationResult<BoothPlan>> = coordinator.save();
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);

        // A different plan becomes the current session while the old write waits.
        coordinator.bind(secondPlan);
        expect(coordinator.getState()).assertEqual('Saved');
        expect(coordinator.isSaving()).assertFalse();
        expect(requireDraft(coordinator).id).assertEqual(secondPlan.id);

        storage.resolveNext(true);
        requirePlan(await oldSave);
        await settleMicrotasks();

        // The stale completion must not touch the new session.
        expect(coordinator.getState()).assertEqual('Saved');
        expect(coordinator.isSaving()).assertFalse();
        const newDraft: BoothPlan = requireDraft(coordinator);
        expect(newDraft.id).assertEqual(secondPlan.id);
        expect(newDraft.objects.length).assertEqual(0);

        // The old request was a real write for the first plan (not a fake ack).
        const firstPersisted: BoothPlan | null =
          findPlan(repository.listPlans(), firstPlan.id);
        expect(firstPersisted !== null).assertTrue();
        if (firstPersisted !== null) {
          expect(firstPersisted.objects.length).assertEqual(1);
        }
        done();
      });

    it('multipleConcurrentSavesPersistLatestQueuedSnapshotOnly', 0,
      async (done: Function) => {
        const storage: ControlledSnapshotStorage = new ControlledSnapshotStorage();
        const repository: PlanRepository = new PlanRepository(storage);
        await repository.recoverStore();
        const created: BoothPlan =
          requirePlan(await repository.createPlan('排队保存方案', 'standard'));

        const coordinator: SaveCoordinator = new SaveCoordinator(repository);
        coordinator.bind(created);
        const objectA: PlacedObject =
          makeObject('obj-a', 'display_table', 300, 200, 0, 1);
        coordinator.update(changedPlan(created, [objectA], created.updatedAt + 100));

        storage.deferWrites = true;
        const first: Promise<OperationResult<BoothPlan>> = coordinator.save();
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);

        // A second save is requested while the first is still pending.
        const objectB: PlacedObject = makeObject('obj-b', 'chair', 100, 100, 0, 2);
        coordinator.update(changedPlan(created, [objectA, objectB],
          created.updatedAt + 200));
        const second: Promise<OperationResult<BoothPlan>> = coordinator.save();
        expect(coordinator.getState()).assertEqual('Saving');
        expect(coordinator.isSaving()).assertTrue();
        await settleMicrotasks();
        // The repository queue still has only the first write in flight.
        expect(storage.writes.length).assertEqual(1);

        storage.resolveNext(true);
        await settleMicrotasks();
        expect(storage.writes.length).assertEqual(1);
        storage.resolveNext(true);
        requirePlan(await first);
        requirePlan(await second);

        expect(coordinator.getState()).assertEqual('Saved');
        expect(coordinator.isSaving()).assertFalse();
        const listed: BoothPlan[] = repository.listPlans();
        expect(listed[0].objects.length).assertEqual(2);
        expect(listed[0].objects[1].catalogId).assertEqual('chair');
        const persisted: PlanStore =
          parsePersisted(requireText(storage.lastWrittenPrimary));
        expect(persisted.plans[0].objects.length).assertEqual(2);
        expect(persisted.plans[0].updatedAt).assertEqual(created.updatedAt + 200);
        done();
      });
  });
}
