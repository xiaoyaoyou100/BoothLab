import { describe, it, expect } from '@ohos/hypium';
import {
  BoothPlan,
  BoothTemplate,
  LayoutIssue,
  OperationResult,
  PlacedObject,
  Rect,
  Rotation
} from '../main/ets/model/BoothModels';
import { getTemplateById } from '../main/ets/catalog/BoothTemplates';
import { EditorController } from '../main/ets/engine/EditorController';
import { canPlace, validateLayout } from '../main/ets/engine/LayoutValidator';

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

function makeTemplate(blockedAreas: Rect[], reservedAreas: Rect[]): BoothTemplate {
  const template: BoothTemplate = {
    id: 'custom-layout',
    name: '自定义校验展位',
    widthCm: 600,
    heightCm: 400,
    blockedAreas: blockedAreas,
    reservedAreas: reservedAreas,
    wallSides: [],
    openSides: []
  };
  return template;
}

function requireTemplate(id: string): BoothTemplate {
  const template: BoothTemplate | undefined = getTemplateById(id);
  if (template === undefined) {
    throw new Error('Missing built-in template: ' + id);
  }
  return template;
}

function filterIssues(issues: LayoutIssue[], code: string): LayoutIssue[] {
  const result: LayoutIssue[] = [];
  for (let i = 0; i < issues.length; i++) {
    if (issues[i].code === code) {
      result.push(issues[i]);
    }
  }
  return result;
}

function countIssuesForId(issues: LayoutIssue[], code: string, id: string): number {
  let count: number = 0;
  const filtered: LayoutIssue[] = filterIssues(issues, code);
  for (let i = 0; i < filtered.length; i++) {
    if (filtered[i].objectIds.indexOf(id) >= 0) {
      count++;
    }
  }
  return count;
}

function containsText(text: string, needle: string): boolean {
  return text.indexOf(needle) >= 0;
}

export default function layoutTest() {
  describe('LayoutTest', () => {
    // ------------------------------------------------------------------
    // Pairwise overlap semantics
    // ------------------------------------------------------------------
    it('overlappingFootprintsProduceOnePairIssue', 0, () => {
      const template = requireTemplate('standard');
      const objects: PlacedObject[] = [
        makeObject('a', 'display_table', 300, 200, 0, 1),
        makeObject('b', 'display_table', 350, 200, 0, 2)
      ];
      const issues = validateLayout(template, objects);
      expect(issues.length).assertEqual(1);
      const overlaps = filterIssues(issues, 'OVERLAP');
      expect(overlaps.length).assertEqual(1);
      expect(overlaps[0].severity).assertEqual('warning');
      expect(overlaps[0].objectIds.length).assertEqual(2);
      expect(overlaps[0].objectIds.indexOf('a') >= 0).assertTrue();
      expect(overlaps[0].objectIds.indexOf('b') >= 0).assertTrue();
    });

    it('edgeContactAndSmallGapAreNotOverlaps', 0, () => {
      const template = requireTemplate('standard');
      const edgeObjects: PlacedObject[] = [
        makeObject('left', 'display_table', 240, 200, 0, 1),
        makeObject('right', 'display_table', 360, 200, 0, 2)
      ];
      const edgeIssues = validateLayout(template, edgeObjects);
      expect(filterIssues(edgeIssues, 'OVERLAP').length).assertEqual(0);

      const gapObjects: PlacedObject[] = [
        makeObject('upper', 'display_table', 300, 200, 0, 1),
        makeObject('lower', 'display_table', 300, 270, 0, 2)
      ];
      const gapIssues = validateLayout(template, gapObjects);
      expect(filterIssues(gapIssues, 'OVERLAP').length).assertEqual(0);
    });

    it('rotatedFootprintCreatesPositiveOverlap', 0, () => {
      const template = requireTemplate('standard');
      const unrotated: PlacedObject[] = [
        makeObject('a', 'display_table', 300, 200, 0, 1),
        makeObject('b', 'display_table', 300, 270, 0, 2)
      ];
      expect(filterIssues(validateLayout(template, unrotated), 'OVERLAP').length)
        .assertEqual(0);

      const rotated: PlacedObject[] = [
        makeObject('a', 'display_table', 300, 200, 0, 1),
        makeObject('b', 'display_table', 300, 270, 90, 2)
      ];
      const rotatedIssues = validateLayout(template, rotated);
      expect(filterIssues(rotatedIssues, 'OVERLAP').length).assertEqual(1);
      expect(countIssuesForId(rotatedIssues, 'OVERLAP', 'a')).assertEqual(1);
      expect(countIssuesForId(rotatedIssues, 'OVERLAP', 'b')).assertEqual(1);
    });

    it('allPairsProduceExactlyOneIssuePerPair', 0, () => {
      const template = requireTemplate('standard');
      const objects: PlacedObject[] = [
        makeObject('a', 'display_table', 300, 200, 0, 1),
        makeObject('b', 'display_table', 310, 200, 0, 2),
        makeObject('c', 'display_table', 320, 200, 0, 3)
      ];
      const overlaps = filterIssues(validateLayout(template, objects), 'OVERLAP');
      expect(overlaps.length).assertEqual(3);
      const pairKeys: string[] = [];
      for (let i = 0; i < overlaps.length; i++) {
        const ids: string[] = overlaps[i].objectIds;
        expect(ids.length).assertEqual(2);
        const key: string = ids[0] + '|' + ids[1];
        expect(pairKeys.indexOf(key) < 0).assertTrue();
        pairKeys.push(key);
      }
    });

    // ------------------------------------------------------------------
    // Reserved reminder areas vs hard blocked areas
    // ------------------------------------------------------------------
    it('standardReservedAreaProducesTeachingWarning', 0, () => {
      const controller = new EditorController('standard');
      const added = requireObject(controller.addObject('display_table', { x: 300, y: 370 }));
      expect(added.id).assertEqual('obj-2');

      const issues = controller.getLayoutIssues();
      const reserved = filterIssues(issues, 'ENTRY_OCCUPIED');
      expect(reserved.length).assertEqual(1);
      expect(reserved[0].severity).assertEqual('warning');
      expect(reserved[0].objectIds.length).assertEqual(1);
      expect(reserved[0].objectIds[0]).assertEqual('obj-2');
      expect(containsText(reserved[0].message, '预留区')).assertTrue();
      expect(containsText(reserved[0].message, '消防')).assertFalse();
      expect(containsText(reserved[0].message, '安全')).assertFalse();
    });

    it('cornerSecondReservedAreaProducesWarning', 0, () => {
      const template = requireTemplate('corner');
      const objects: PlacedObject[] = [
        makeObject('s1', 'sign', 570, 200, 0, 1)
      ];
      const issues = validateLayout(template, objects);
      const reserved = filterIssues(issues, 'ENTRY_OCCUPIED');
      expect(reserved.length).assertEqual(1);
      expect(reserved[0].objectIds[0]).assertEqual('s1');
      expect(reserved[0].severity).assertEqual('warning');
      expect(filterIssues(issues, 'BLOCKED_AREA').length).assertEqual(0);
    });

    it('reservedEdgeContactDoesNotWarn', 0, () => {
      const template = requireTemplate('standard');
      // Footprint y = 280..340 exactly touches the reserved area top at y=340.
      const objects: PlacedObject[] = [
        makeObject('edge', 'display_table', 300, 310, 0, 1)
      ];
      const issues = validateLayout(template, objects);
      expect(filterIssues(issues, 'ENTRY_OCCUPIED').length).assertEqual(0);
      expect(filterIssues(issues, 'OVERLAP').length).assertEqual(0);
    });

    it('moveOutOfReservedAreaClearsWarning', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.addObject('display_table', { x: 300, y: 370 }));
      expect(filterIssues(controller.getLayoutIssues(), 'ENTRY_OCCUPIED').length)
        .assertEqual(1);

      requireObject(controller.moveObject('obj-2', { x: 100, y: 100 }));
      expect(controller.getLayoutIssues().length).assertEqual(0);
    });

    it('deleteClearsWarning', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.addObject('display_table', { x: 300, y: 370 }));
      expect(controller.getLayoutIssues().length).assertEqual(1);

      requireObject(controller.removeObject('obj-2'));
      expect(controller.getLayoutIssues().length).assertEqual(0);
    });

    it('blockedAreaIsHardErrorWhileReservedIsWarning', 0, () => {
      const blocked: Rect[] = [{ x: 100, y: 100, width: 100, height: 100 }];
      const reserved: Rect[] = [{ x: 300, y: 100, width: 100, height: 100 }];
      const template = makeTemplate(blocked, reserved);
      const objects: PlacedObject[] = [
        makeObject('in-blocked', 'chair', 150, 150, 0, 1),
        makeObject('in-reserved', 'chair', 350, 150, 0, 2)
      ];
      const issues = validateLayout(template, objects);
      const hard = filterIssues(issues, 'BLOCKED_AREA');
      const warning = filterIssues(issues, 'ENTRY_OCCUPIED');
      expect(hard.length).assertEqual(1);
      expect(hard[0].severity).assertEqual('error');
      expect(hard[0].objectIds[0]).assertEqual('in-blocked');
      expect(warning.length).assertEqual(1);
      expect(warning[0].severity).assertEqual('warning');
      expect(warning[0].objectIds[0]).assertEqual('in-reserved');
      expect(filterIssues(issues, 'OUT_OF_BOUNDS').length).assertEqual(0);
      expect(countIssuesForId(issues, 'ENTRY_OCCUPIED', 'in-blocked')).assertEqual(0);
      expect(countIssuesForId(issues, 'BLOCKED_AREA', 'in-reserved')).assertEqual(0);
    });

    // ------------------------------------------------------------------
    // Explicit malformed data handling
    // ------------------------------------------------------------------
    it('invalidObjectsAndDuplicateIdsProduceExplicitIssues', 0, () => {
      const template = requireTemplate('standard');
      const objects: PlacedObject[] = [
        makeObject('dup', 'display_table', 300, 200, 0, 1),
        makeObject('dup', 'chair', 100, 100, 0, 2),
        makeObject('bad-catalog', 'not-a-catalog', 200, 200, 0, 3),
        makeObject('bad-centre', 'display_table', Number.NaN, 200, 0, 4),
        makeObject('bad-rotation', 'display_table', 300, 200, 45 as Rotation, 5),
        makeObject('', 'chair', 100, 300, 0, 6)
      ];
      const issues = validateLayout(template, objects);
      const invalid = filterIssues(issues, 'INVALID_ARGUMENT');
      expect(invalid.length).assertEqual(5);
      expect(countIssuesForId(issues, 'INVALID_ARGUMENT', 'dup')).assertEqual(1);
      expect(countIssuesForId(issues, 'INVALID_ARGUMENT', 'bad-catalog')).assertEqual(1);
      expect(countIssuesForId(issues, 'INVALID_ARGUMENT', 'bad-centre')).assertEqual(1);
      expect(countIssuesForId(issues, 'INVALID_ARGUMENT', 'bad-rotation')).assertEqual(1);
    });

    it('invalidTemplateRectDataProducesExplicitIssue', 0, () => {
      const template = makeTemplate(
        [{ x: 0, y: 0, width: Number.NaN, height: 100 }],
        [{ x: 0, y: 0, width: 0, height: 10 }]
      );
      const issues = validateLayout(template,
        [makeObject('chair-a', 'chair', 300, 200, 0, 1)]);
      const invalid = filterIssues(issues, 'INVALID_ARGUMENT');
      expect(invalid.length >= 2).assertTrue();

      const badDimensions = makeTemplate([], []);
      badDimensions.widthCm = Number.NaN;
      const dimensionIssues = validateLayout(badDimensions, []);
      expect(filterIssues(dimensionIssues, 'INVALID_ARGUMENT').length >= 1).assertTrue();
    });

    // ------------------------------------------------------------------
    // Controller getter freshness and warning-only policy
    // ------------------------------------------------------------------
    it('getLayoutIssuesIgnoresPreviewUntilCommit', 0, () => {
      const controller = new EditorController('standard');
      expect(controller.getLayoutIssues().length).assertEqual(0);

      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      requireObject(controller.updateDrag({ x: 300, y: 370 }));
      expect(controller.getLayoutIssues().length).assertEqual(0);

      requireObject(controller.endDrag());
      expect(filterIssues(controller.getLayoutIssues(), 'ENTRY_OCCUPIED').length)
        .assertEqual(1);
    });

    it('undoRedoRecomputeIssuesFromCommittedState', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.addObject('display_table', { x: 300, y: 370 }));
      expect(controller.getLayoutIssues().length).assertEqual(1);

      controller.undo();
      expect(controller.getLayoutIssues().length).assertEqual(0);
      expect(controller.getObjects().length).assertEqual(1);

      controller.redo();
      expect(controller.getLayoutIssues().length).assertEqual(1);
      expect(controller.getObjects().length).assertEqual(2);
    });

    it('layoutWarningDoesNotBlockEditingOrSaving', 0, () => {
      const controller = new EditorController('standard');
      const plan: BoothPlan = {
        id: 'warn-plan',
        name: '提醒方案',
        templateId: 'standard',
        objects: [makeObject('warn-object', 'display_table', 300, 370, 0, 1)],
        createdAt: 10,
        updatedAt: 20
      };
      requirePlan(controller.importPlan(plan));
      expect(filterIssues(controller.getLayoutIssues(), 'ENTRY_OCCUPIED').length)
        .assertEqual(1);

      requireObject(controller.moveObject('warn-object', { x: 300, y: 300 }));
      requireObject(controller.rotateObject('warn-object'));
      const exported = requirePlan(controller.exportPlan());
      expect(exported.objects.length).assertEqual(1);
      expect(exported.id).assertEqual('warn-plan');
    });

    // ------------------------------------------------------------------
    // Pure canPlace helper used by controller add/move/rotate/endDrag
    // ------------------------------------------------------------------
    it('canPlaceRejectsBlockedAreaAndAllowsReservedArea', 0, () => {
      const blocked: Rect[] = [{ x: 100, y: 100, width: 100, height: 100 }];
      const reserved: Rect[] = [{ x: 300, y: 100, width: 100, height: 100 }];
      const template = makeTemplate(blocked, reserved);

      expect(canPlace(template,
        makeObject('blocked', 'chair', 150, 150, 0, 1)).code).assertEqual('OUT_OF_BOUNDS');
      expect(canPlace(template,
        makeObject('reserved', 'chair', 350, 150, 0, 2)).code).assertEqual('OK');
      // Footprint x=50..100 touches the blocked left edge at x=100 with zero
      // intersection width, so edge contact is allowed.
      expect(canPlace(template,
        makeObject('edge', 'chair', 75, 150, 0, 3)).code).assertEqual('OK');
    });

    it('canPlacePreservesExactBoundarySemantics', 0, () => {
      const template = requireTemplate('standard');
      expect(canPlace(template,
        makeObject('right-edge', 'display_table', 540, 200, 0, 1)).code).assertEqual('OK');
      expect(canPlace(template,
        makeObject('past-right', 'display_table', 540.1, 200, 0, 1)).code)
        .assertEqual('OUT_OF_BOUNDS');
      expect(canPlace(template,
        makeObject('corner-edge', 'sign', 570, 90, 0, 1)).code).assertEqual('OK');
      expect(canPlace(template,
        makeObject('past-corner', 'sign', 570.1, 90, 0, 1)).code)
        .assertEqual('OUT_OF_BOUNDS');
    });
  });
}
