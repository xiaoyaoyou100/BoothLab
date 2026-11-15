import { describe, it, expect } from '@ohos/hypium';
import {
  BoothPlan,
  OperationResult,
  PlacedObject,
  Rotation
} from '../main/ets/model/BoothModels';
import { EditorController } from '../main/ets/engine/EditorController';
import { HistoryManager } from '../main/ets/engine/HistoryManager';

function requireObjects(result: OperationResult<PlacedObject[]>): PlacedObject[] {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected an object array payload.');
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

function requirePlan(result: OperationResult<BoothPlan>): BoothPlan {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected a plan payload.');
  }
  return result.data;
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

function standardPlan(objects: PlacedObject[]): BoothPlan {
  return makePlan('plan-1', '春季方案', 'standard', objects, 1000, 1000);
}

function findObject(objects: PlacedObject[], id: string): PlacedObject | null {
  for (let i = 0; i < objects.length; i++) {
    if (objects[i].id === id) {
      return objects[i];
    }
  }
  return null;
}

function requireFound(objects: PlacedObject[], id: string): PlacedObject {
  const found: PlacedObject | null = findObject(objects, id);
  if (found === null) {
    throw new Error('Expected object id: ' + id);
  }
  return found;
}

function assertObjectIdentity(actual: PlacedObject, expected: PlacedObject): void {
  expect(actual.id).assertEqual(expected.id);
  expect(actual.catalogId).assertEqual(expected.catalogId);
  expect(actual.centerX).assertEqual(expected.centerX);
  expect(actual.centerY).assertEqual(expected.centerY);
  expect(actual.rotation).assertEqual(expected.rotation);
  expect(actual.zIndex).assertEqual(expected.zIndex);
}

export default function historyTest() {
  describe('HistoryTest', () => {
    // ------------------------------------------------------------------
    // Basic identity-preserving snapshots
    // ------------------------------------------------------------------
    it('addUndoRedoPreservesFullObjectIdentity', 0, () => {
      const controller = new EditorController('standard');
      const added = requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      expect(added.id).assertEqual('obj-2');
      expect(controller.canUndo()).assertTrue();
      expect(controller.canRedo()).assertFalse();

      const undone = requireObjects(controller.undo());
      expect(undone.length).assertEqual(1);
      expect(findObject(undone, 'obj-2') === null).assertTrue();
      expect(controller.canUndo()).assertFalse();
      expect(controller.canRedo()).assertTrue();

      const redone = requireObjects(controller.redo());
      expect(redone.length).assertEqual(2);
      const restored = requireFound(redone, 'obj-2');
      assertObjectIdentity(restored, added);
      expect(controller.getObjects().length).assertEqual(2);
      expect(controller.canRedo()).assertFalse();
    });

    it('moveUndoRedoRestoresCentreAndKeepsId', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.moveObject('obj-1', { x: 400, y: 200 }));

      const undone = requireObjects(controller.undo());
      const original = requireFound(undone, 'obj-1');
      expect(original.centerX).assertEqual(300);
      expect(original.centerY).assertEqual(200);

      const redone = requireObjects(controller.redo());
      const moved = requireFound(redone, 'obj-1');
      expect(moved.centerX).assertEqual(400);
      expect(moved.centerY).assertEqual(200);
      expect(moved.id).assertEqual('obj-1');
    });

    it('rotateUndoRedoRestoresRotationAndFootprintInputs', 0, () => {
      const controller = new EditorController('standard');
      const rotated = requireObject(controller.rotateObject('obj-1'));
      expect(rotated.rotation).assertEqual(90);

      const undone = requireObjects(controller.undo());
      const before = requireFound(undone, 'obj-1');
      expect(before.rotation).assertEqual(0);
      expect(before.centerX).assertEqual(300);
      expect(before.centerY).assertEqual(200);

      const redone = requireObjects(controller.redo());
      expect(requireFound(redone, 'obj-1').rotation).assertEqual(90);
    });

    it('deleteUndoRedoRestoresCompleteSnapshotIncludingIdAndZIndex', 0, () => {
      const controller = new EditorController('standard');
      const added = requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      requireObject(controller.moveObject(added.id, { x: 120, y: 110 }));
      requireObject(controller.rotateObject(added.id));
      expect(controller.selectObject(added.id).code).assertEqual('OK');
      const snapshot = requireFound(controller.getObjects(), added.id);

      const removed = requireObject(controller.removeObject(added.id));
      assertObjectIdentity(removed, snapshot);
      expect(findObject(controller.getObjects(), added.id) === null).assertTrue();
      expect(controller.getSelectedId() === null).assertTrue();

      const undone = requireObjects(controller.undo());
      const restored = requireFound(undone, added.id);
      assertObjectIdentity(restored, snapshot);
      expect(restored.zIndex).assertEqual(2);

      const redone = requireObjects(controller.redo());
      expect(findObject(redone, added.id) === null).assertTrue();
    });

    // ------------------------------------------------------------------
    // Capacity and branch behaviour
    // ------------------------------------------------------------------
    it('fiftyOperationsCanAllBeUndoneAndRedone', 0, () => {
      const controller = new EditorController('standard');
      for (let i = 0; i < 50; i++) {
        requireObject(controller.addObject('chair', { x: 300, y: 200 }));
      }
      expect(controller.getObjects().length).assertEqual(51);

      for (let i = 0; i < 50; i++) {
        requireObjects(controller.undo());
      }
      expect(controller.getObjects().length).assertEqual(1);
      expect(controller.canUndo()).assertFalse();
      expect(controller.canRedo()).assertTrue();
      expect(controller.undo().code).assertEqual('NO_HISTORY');

      const redone = requireObjects(controller.redo());
      expect(redone.length).assertEqual(2);
      expect(requireFound(redone, 'obj-2').catalogId).assertEqual('chair');
    });

    it('fiftyFirstOperationDropsOldestHistoryEntry', 0, () => {
      const controller = new EditorController('standard');
      for (let i = 0; i < 51; i++) {
        requireObject(controller.addObject('chair', { x: 300, y: 200 }));
      }
      expect(controller.getObjects().length).assertEqual(52);

      for (let i = 0; i < 50; i++) {
        requireObjects(controller.undo());
      }
      // The first add was evicted, so the oldest reachable state still has it.
      expect(controller.getObjects().length).assertEqual(2);
      expect(requireFound(controller.getObjects(), 'obj-2').id).assertEqual('obj-2');
      expect(controller.canUndo()).assertFalse();
      expect(controller.undo().code).assertEqual('NO_HISTORY');
    });

    it('newMutationAfterUndoClearsRedoBranch', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      requireObjects(controller.undo());
      expect(controller.canRedo()).assertTrue();

      const plant = requireObject(controller.addObject('plant', { x: 500, y: 100 }));
      expect(plant.id).assertEqual('obj-3');
      expect(controller.canRedo()).assertFalse();
      expect(controller.redo().code).assertEqual('NO_HISTORY');
      expect(findObject(controller.getObjects(), 'obj-2') === null).assertTrue();
      expect(findObject(controller.getObjects(), 'obj-3') !== null).assertTrue();
    });

    // ------------------------------------------------------------------
    // Operations that must never record history
    // ------------------------------------------------------------------
    it('invalidMoveRotateRemoveAndAddRecordNoHistory', 0, () => {
      const controller = new EditorController('standard');
      expect(controller.moveObject('missing', { x: 300, y: 200 }).code).assertEqual('NOT_FOUND');
      expect(controller.rotateObject('missing').code).assertEqual('NOT_FOUND');
      expect(controller.removeObject('missing').code).assertEqual('NOT_FOUND');
      expect(controller.addObject('missing', { x: 100, y: 100 }).code).assertEqual('NOT_FOUND');
      expect(controller.moveObject('obj-1', { x: 590, y: 200 }).code).assertEqual('OUT_OF_BOUNDS');
      expect(controller.addObject('display_table',
        { x: 540.1, y: 200 }).code).assertEqual('OUT_OF_BOUNDS');
      expect(controller.endDrag().code).assertEqual('INVALID_ARGUMENT');
      expect(controller.undo().code).assertEqual('NO_HISTORY');
      expect(controller.redo().code).assertEqual('NO_HISTORY');
      expect(controller.canUndo()).assertFalse();
      expect(controller.canRedo()).assertFalse();
      expect(controller.getObjects().length).assertEqual(1);
    });

    it('invalidRotateNearBoundaryRecordsNoHistory', 0, () => {
      const controller = new EditorController('standard');
      const plan = standardPlan([makeObject('obj-1', 'display_table', 300, 350, 0, 1)]);
      requirePlan(controller.importPlan(plan));
      expect(controller.canUndo()).assertFalse();

      expect(controller.rotateObject('obj-1').code).assertEqual('OUT_OF_BOUNDS');
      expect(controller.canUndo()).assertFalse();
      expect(controller.getObjects()[0].rotation).assertEqual(0);
    });

    it('multipleDragUpdatesRecordExactlyOneChange', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      requireObject(controller.updateDrag({ x: 350, y: 210 }));
      requireObject(controller.updateDrag({ x: 400, y: 220 }));
      requireObject(controller.updateDrag({ x: 450, y: 230 }));
      const ended = requireObject(controller.endDrag());
      expect(ended.centerX).assertEqual(450);
      expect(ended.centerY).assertEqual(230);

      const undone = requireObjects(controller.undo());
      expect(requireFound(undone, 'obj-1').centerX).assertEqual(300);
      expect(requireFound(undone, 'obj-1').centerY).assertEqual(200);
      expect(controller.canUndo()).assertFalse();

      const redone = requireObjects(controller.redo());
      expect(requireFound(redone, 'obj-1').centerX).assertEqual(450);
      expect(requireFound(redone, 'obj-1').centerY).assertEqual(230);
    });

    it('dragWithoutNetChangeRecordsNoHistory', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.moveObject('obj-1', { x: 300, y: 200 }));
      expect(controller.canUndo()).assertFalse();
      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      requireObject(controller.updateDrag({ x: 300, y: 200 }));
      requireObject(controller.updateDrag({ x: 305, y: 205 }));
      requireObject(controller.updateDrag({ x: 300, y: 200 }));
      requireObject(controller.endDrag());
      expect(controller.getObjects()[0].centerX).assertEqual(300);
      expect(controller.getObjects()[0].centerY).assertEqual(200);
      expect(controller.canUndo()).assertFalse();
      expect(controller.undo().code).assertEqual('NO_HISTORY');
    });

    it('rejectedDragAndCancelledDragRecordNoHistory', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      requireObject(controller.updateDrag({ x: 590, y: 200 }));
      expect(controller.endDrag().code).assertEqual('OUT_OF_BOUNDS');
      expect(controller.canUndo()).assertFalse();
      expect(controller.getObjects()[0].centerX).assertEqual(300);

      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      requireObject(controller.updateDrag({ x: 400, y: 220 }));
      expect(controller.cancelDrag().code).assertEqual('OK');
      expect(controller.canUndo()).assertFalse();
      expect(controller.getObjects()[0].centerX).assertEqual(300);
    });

    it('selectionAndPreviewChangesRecordNoHistory', 0, () => {
      const controller = new EditorController('standard');
      expect(controller.selectObject('obj-1').code).assertEqual('OK');
      expect(controller.selectObject(null).code).assertEqual('OK');
      expect(controller.selectObject('missing').code).assertEqual('NOT_FOUND');
      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      requireObject(controller.updateDrag({ x: 420, y: 260 }));
      expect(controller.getPreviewObject() !== null).assertTrue();
      expect(controller.canUndo()).assertFalse();
      expect(controller.cancelDrag().code).assertEqual('OK');
      expect(controller.canUndo()).assertFalse();
    });

    it('mutationsUndoAndRedoAreRejectedDuringDrag', 0, () => {
      const controller = new EditorController('standard');
      const added = requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));

      expect(controller.addObject('plant', { x: 500, y: 100 }).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.moveObject(added.id, { x: 120, y: 110 }).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.rotateObject(added.id).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.removeObject(added.id).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.undo().code).assertEqual('INVALID_ARGUMENT');
      expect(controller.redo().code).assertEqual('INVALID_ARGUMENT');
      expect(controller.canUndo()).assertTrue();
      expect(controller.canRedo()).assertFalse();
      expect(controller.getObjects().length).assertEqual(2);

      expect(controller.cancelDrag().code).assertEqual('OK');
      const undone = requireObjects(controller.undo());
      expect(undone.length).assertEqual(1);
      expect(controller.canUndo()).assertFalse();
    });

    // ------------------------------------------------------------------
    // Formal plan import / export
    // ------------------------------------------------------------------
    it('importEmptyPlanReplacesAllObjectsWithoutSeedAndClearsHistory', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      expect(controller.canUndo()).assertTrue();

      const imported = requirePlan(controller.importPlan(
        makePlan('plan-empty', '空方案', 'standard', [], 500, 600)));
      expect(imported.id).assertEqual('plan-empty');
      expect(imported.objects.length).assertEqual(0);
      expect(controller.getPlanId()).assertEqual('plan-empty');
      expect(controller.getObjects().length).assertEqual(0);
      expect(controller.canUndo()).assertFalse();
      expect(controller.canRedo()).assertFalse();

      const exported = requirePlan(controller.exportPlan());
      expect(exported.objects.length).assertEqual(0);
      expect(exported.templateId).assertEqual('standard');
    });

    it('importPlanClearsSelectionDragPreviewAndHistory', 0, () => {
      const controller = new EditorController('standard');
      const added = requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      expect(controller.selectObject(added.id).code).assertEqual('OK');
      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));

      const objects: PlacedObject[] = [
        makeObject('chair-a', 'chair', 100, 100, 0, 1),
        makeObject('plant-a', 'plant', 500, 100, 0, 2)
      ];
      requirePlan(controller.importPlan(makePlan('plan-switch', '切换方案', 'standard',
        objects, 1000, 2000)));

      expect(controller.isDragging()).assertFalse();
      expect(controller.getPreviewObject() === null).assertTrue();
      expect(controller.getSelectedId() === null).assertTrue();
      expect(controller.canUndo()).assertFalse();
      expect(controller.canRedo()).assertFalse();
      const current = controller.getObjects();
      expect(current.length).assertEqual(2);
      expect(current[0].id).assertEqual('chair-a');
      expect(current[1].id).assertEqual('plant-a');
    });

    it('invalidImportsLeavePlanObjectsDragAndHistoryIntact', 0, () => {
      const controller = new EditorController('standard');
      requirePlan(controller.importPlan(standardPlan([
        makeObject('obj-1', 'chair', 100, 100, 0, 1)
      ])));
      requireObject(controller.addObject('plant', { x: 500, y: 100 }));
      expect(controller.selectObject('obj-1').code).assertEqual('OK');
      const beforeObjects = controller.getObjects();
      const beforeUpdatedAt = requirePlan(controller.exportPlan()).updatedAt;
      expect(controller.canUndo()).assertTrue();

      const invalidPlans: BoothPlan[] = [
        makePlan('bad-template', '坏模板', 'unknown', [], 1, 1),
        makePlan('bad-name', '   ', 'standard', [], 1, 1),
        // Frozen BoothPlan ids only require a non-empty string (no 30-char
        // cap), so a long id is valid and must not appear in this list.
        makePlan('bad-time', '坏时间', 'standard', [], 100, 99),
        makePlan('bad-duplicate', '重复', 'standard', [
          makeObject('same', 'chair', 100, 100, 0, 1),
          makeObject('same', 'plant', 500, 100, 0, 2)
        ], 1, 1),
        makePlan('bad-catalog', '坏目录', 'standard', [
          makeObject('x', 'not-a-catalog', 100, 100, 0, 1)
        ], 1, 1),
        makePlan('bad-bounds', '越界', 'standard', [
          makeObject('x', 'display_table', 590, 200, 0, 1)
        ], 1, 1),
        makePlan('bad-rotation', '坏旋转', 'standard', [
          makeObject('x', 'display_table', 300, 200, 45 as Rotation, 1)
        ], 1, 1),
        makePlan('bad-centre', '坏坐标', 'standard', [
          makeObject('x', 'display_table', Number.NaN, 200, 0, 1)
        ], 1, 1),
        {
          id: 'bad-objects',
          name: '坏对象数组',
          templateId: 'standard',
          createdAt: 1,
          updatedAt: 1
        } as BoothPlan
      ];

      for (let i = 0; i < invalidPlans.length; i++) {
        const result = controller.importPlan(invalidPlans[i]);
        expect(result.code !== 'OK').assertTrue();
        expect(controller.getPlanId()).assertEqual('plan-1');
        expect(controller.getObjects().length).assertEqual(beforeObjects.length);
        expect(controller.getObjects()[0].catalogId).assertEqual(beforeObjects[0].catalogId);
        expect(controller.getSelectedId()).assertEqual('obj-1');
        expect(controller.canUndo()).assertTrue();
        expect(requirePlan(controller.exportPlan()).updatedAt).assertEqual(beforeUpdatedAt);
      }
    });

    it('importedAndUndoneIdsNeverCollideWithNewAllocations', 0, () => {
      const controller = new EditorController('standard');
      requirePlan(controller.importPlan(standardPlan([
        makeObject('obj-7', 'chair', 100, 100, 0, 1),
        makeObject('custom-a', 'plant', 500, 100, 0, 2)
      ])));

      const firstAdd = requireObject(controller.addObject('chair', { x: 200, y: 200 }));
      expect(firstAdd.id).assertEqual('obj-8');
      requireObjects(controller.undo());
      expect(controller.getObjects().length).assertEqual(2);

      const secondAdd = requireObject(controller.addObject('chair', { x: 200, y: 200 }));
      expect(secondAdd.id).assertEqual('obj-9');
      const ids: string[] = [];
      const current = controller.getObjects();
      for (let i = 0; i < current.length; i++) {
        expect(ids.indexOf(current[i].id) < 0).assertTrue();
        ids.push(current[i].id);
      }
      expect(ids.indexOf('obj-8') < 0).assertTrue();
    });

    it('undoAndRedoReuseOriginalIdsWithoutRollingAllocatorBack', 0, () => {
      const controller = new EditorController('standard');
      const added = requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      expect(added.id).assertEqual('obj-2');
      requireObjects(controller.undo());
      const redone = requireObjects(controller.redo());
      expect(requireFound(redone, 'obj-2').id).assertEqual('obj-2');

      const next = requireObject(controller.addObject('plant', { x: 500, y: 100 }));
      expect(next.id).assertEqual('obj-3');
      requireObjects(controller.undo());
      const afterUndoAdd = requireObject(controller.addObject('plant', { x: 500, y: 100 }));
      expect(afterUndoAdd.id).assertEqual('obj-4');
      expect(findObject(controller.getObjects(), 'obj-3') === null).assertTrue();
    });

    it('exportedPlanAndReturnedObjectsAreDeepIsolatedClones', 0, () => {
      const controller = new EditorController('standard');
      requirePlan(controller.importPlan(standardPlan([
        makeObject('obj-1', 'chair', 100, 100, 0, 1)
      ])));

      const first = requirePlan(controller.exportPlan());
      first.objects[0].centerX = -999;
      first.objects[0].catalogId = 'mutated';
      first.objects.push(makeObject('extra', 'plant', 10, 10, 0, 9));
      const second = requirePlan(controller.exportPlan());
      expect(second.objects.length).assertEqual(1);
      expect(second.objects[0].centerX).assertEqual(100);
      expect(second.objects[0].catalogId).assertEqual('chair');

      const objects = controller.getObjects();
      objects[0].centerX = -1;
      expect(controller.getObjects()[0].centerX).assertEqual(100);

      requireObject(controller.moveObject('obj-1', { x: 120, y: 110 }));
      const undone = requireObjects(controller.undo());
      expect(undone[0].centerX).assertEqual(100);
      undone[0].centerX = -2;
      expect(controller.getObjects()[0].centerX).assertEqual(100);
    });

    it('formalMetadataStaysStableOnReadAndChangesOnEffectiveHistory', 0, () => {
      const demo = new EditorController('standard');
      expect(demo.getPlanId() === null).assertTrue();
      expect(demo.exportPlan().code).assertEqual('INVALID_ARGUMENT');
      expect(demo.undo().code).assertEqual('NO_HISTORY');

      const controller = new EditorController('corner');
      const imported = requirePlan(controller.importPlan(makePlan('plan-meta', '元数据方案',
        'corner', [makeObject('obj-1', 'chair', 100, 100, 0, 1)], 1000, 2000)));
      expect(imported.createdAt).assertEqual(1000);
      expect(imported.updatedAt).assertEqual(2000);
      expect(controller.getTemplate().id).assertEqual('corner');
      expect(controller.exportPlan().code).assertEqual('OK');
      expect(requirePlan(controller.exportPlan()).updatedAt).assertEqual(2000);

      requireObject(controller.moveObject('obj-1', { x: 120, y: 110 }));
      const afterMove = requirePlan(controller.exportPlan());
      expect(afterMove.createdAt).assertEqual(1000);
      expect(afterMove.updatedAt > 2000).assertTrue();
      expect(requirePlan(controller.exportPlan()).updatedAt).assertEqual(afterMove.updatedAt);

      requireObjects(controller.undo());
      const afterUndo = requirePlan(controller.exportPlan());
      expect(afterUndo.updatedAt > afterMove.updatedAt).assertTrue();
      expect(afterUndo.createdAt).assertEqual(1000);

      requireObjects(controller.redo());
      const afterRedo = requirePlan(controller.exportPlan());
      expect(afterRedo.updatedAt > afterUndo.updatedAt).assertTrue();
      expect(afterRedo.createdAt).assertEqual(1000);
    });

    // ------------------------------------------------------------------
    // Exact boundary and failure bookkeeping
    // ------------------------------------------------------------------
    it('exactBoundaryAddsSucceedAndJustBeyondIsRejectedWithoutHistory', 0, () => {
      const controller = new EditorController('standard');
      const rightEdge = requireObject(controller.addObject('display_table', { x: 540, y: 200 }));
      expect(rightEdge.id).assertEqual('obj-2');
      expect(controller.addObject('display_table',
        { x: 540.1, y: 200 }).code).assertEqual('OUT_OF_BOUNDS');

      const cornerEdge = requireObject(controller.addObject('sign', { x: 570, y: 90 }));
      expect(cornerEdge.id).assertEqual('obj-3');
      expect(controller.addObject('sign',
        { x: 570.1, y: 90 }).code).assertEqual('OUT_OF_BOUNDS');

      expect(controller.getObjects().length).assertEqual(3);
      requireObjects(controller.undo());
      requireObjects(controller.undo());
      expect(controller.getObjects().length).assertEqual(1);
      expect(controller.canUndo()).assertFalse();
      expect(controller.undo().code).assertEqual('NO_HISTORY');
    });

    // ------------------------------------------------------------------
    // M2-A02 review regressions (import contract, allocator, history clones)
    // ------------------------------------------------------------------
    it('importAcceptsUuid36IdAndCanonicalisesTrimmedName', 0, () => {
      const controller = new EditorController('standard');
      const uuid: string = '123e4567-e89b-12d3-a456-426614174000';
      const imported = requirePlan(controller.importPlan(
        makePlan(uuid, '  春季方案  ', 'standard', [], 0, 0)));
      expect(imported.id).assertEqual(uuid);
      expect(imported.name).assertEqual('春季方案');
      expect(controller.getPlanId()).assertEqual(uuid);
      expect(requirePlan(controller.exportPlan()).name).assertEqual('春季方案');

      // The frozen entity contract has no plan-id length cap, so a 31-character
      // id is also valid and must not be rejected.
      const longId: string = '1234567890123456789012345678901';
      const longImported = requirePlan(controller.importPlan(
        makePlan(longId, '长编号方案', 'standard', [], 5, 5)));
      expect(longImported.id).assertEqual(longId);
      expect(controller.getPlanId()).assertEqual(longId);
    });

    it('importRejectsEmptyIdNegativeTimestampsAndOversizedName', 0, () => {
      const controller = new EditorController('standard');
      const invalidPlans: BoothPlan[] = [
        makePlan('', '空编号', 'standard', [], 0, 0),
        makePlan('plan-x', '负时间', 'standard', [], -1, 0),
        makePlan('plan-x', '负时间', 'standard', [], 0, -1),
        makePlan('plan-x', '   ', 'standard', [], 0, 0),
        makePlan('plan-x', '1234567890123456789012345678901', 'standard', [], 0, 0)
      ];
      for (let i = 0; i < invalidPlans.length; i++) {
        expect(controller.importPlan(invalidPlans[i]).code).assertEqual('INVALID_ARGUMENT');
        expect(controller.getPlanId() === null).assertTrue();
        expect(controller.getObjects().length).assertEqual(1);
      }
    });

    it('hugeImportedNumericSuffixDoesNotPoisonAllocator', 0, () => {
      const controller = new EditorController('standard');
      const hugeId: string = 'obj-9999999999999999999999';
      requirePlan(controller.importPlan(standardPlan([
        makeObject(hugeId, 'chair', 100, 100, 0, 1)
      ])));

      const first = requireObject(controller.addObject('chair', { x: 200, y: 200 }));
      const second = requireObject(controller.addObject('chair', { x: 300, y: 200 }));
      expect(first.id !== second.id).assertTrue();
      expect(first.id !== hugeId).assertTrue();
      expect(second.id !== hugeId).assertTrue();
      expect(controller.getObjects().length).assertEqual(3);

      const undone = requireObjects(controller.undo());
      expect(findObject(undone, second.id) === null).assertTrue();
      const redone = requireObjects(controller.redo());
      expect(requireFound(redone, second.id).id).assertEqual(second.id);

      const next = requireObject(controller.addObject('chair', { x: 400, y: 200 }));
      expect(next.id !== first.id).assertTrue();
      expect(next.id !== second.id).assertTrue();
      expect(next.id !== hugeId).assertTrue();
    });

    it('undoRedoReturnClonedEntriesIsolatedFromInternalStacks', 0, () => {
      const manager = new HistoryManager();
      const before: PlacedObject[] = [makeObject('before-id', 'chair', 100, 100, 0, 1)];
      const after: PlacedObject[] = [makeObject('after-id', 'chair', 120, 100, 0, 1)];
      manager.record(before, after);

      const undone = manager.undo();
      expect(undone !== null).assertTrue();
      if (undone === null) {
        throw new Error('Expected an undo entry.');
      }
      undone.before[0].id = 'mutated-before';
      undone.after[0].id = 'mutated-after';
      undone.before.push(makeObject('extra-before', 'plant', 10, 10, 0, 9));
      undone.after.push(makeObject('extra-after', 'plant', 20, 20, 0, 9));

      const redone = manager.redo();
      expect(redone !== null).assertTrue();
      if (redone === null) {
        throw new Error('Expected a redo entry.');
      }
      expect(redone.after.length).assertEqual(1);
      expect(redone.after[0].id).assertEqual('after-id');

      const undoneAgain = manager.undo();
      expect(undoneAgain !== null).assertTrue();
      if (undoneAgain === null) {
        throw new Error('Expected a second undo entry.');
      }
      expect(undoneAgain.before.length).assertEqual(1);
      expect(undoneAgain.before[0].id).assertEqual('before-id');
    });
  });
}
