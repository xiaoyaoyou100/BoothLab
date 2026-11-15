import { describe, it, expect } from '@ohos/hypium';
import {
  CatalogItem,
  OperationResult,
  PlacedObject,
  Point,
  Rect,
  Rotation,
  Viewport
} from '../main/ets/model/BoothModels';
import { EditorController } from '../main/ets/engine/EditorController';
import {
  createViewport,
  getFootprintRect,
  hitTestObjects,
  isWithinBounds,
  isValidRotation,
  overlapsPositive,
  pointInRect,
  screenToWorld,
  worldToScreen
} from '../main/ets/engine/GeometryEngine';
import { getCatalogItemById } from '../main/ets/catalog/ObjectCatalogData';

function assertNear(actual: number, expected: number, tolerance: number): void {
  expect(Math.abs(actual - expected) <= tolerance).assertTrue();
}

function requireRect(result: OperationResult<Rect>): Rect {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected a rectangle payload.');
  }
  return result.data;
}

function requirePoint(result: OperationResult<Point>): Point {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected a point payload.');
  }
  return result.data;
}

function requireObject(result: OperationResult<PlacedObject>): PlacedObject {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected an object payload.');
  }
  return result.data;
}

function requireViewport(result: OperationResult<Viewport>): Viewport {
  expect(result.code).assertEqual('OK');
  if (result.data === undefined) {
    throw new Error('Expected a viewport payload.');
  }
  return result.data;
}

function displayTableCatalog(): CatalogItem {
  const item: CatalogItem | undefined = getCatalogItemById('display_table');
  if (item === undefined) {
    throw new Error('display_table is missing from the frozen catalog.');
  }
  return item;
}

export default function editorTest() {
  describe('EditorTest', () => {
    // ------------------------------------------------------------------
    // Initial state and additive objects
    // ------------------------------------------------------------------
    it('initialSampleUsesStandardTemplateAndDisplayTableCentre', 0, () => {
      const controller = new EditorController('standard');
      const template = controller.getTemplate();
      expect(template.id).assertEqual('standard');
      expect(template.widthCm).assertEqual(600);
      expect(template.heightCm).assertEqual(400);

      const objects = controller.getObjects();
      expect(objects.length).assertEqual(1);
      expect(objects[0].id).assertEqual('obj-1');
      expect(objects[0].catalogId).assertEqual('display_table');
      expect(objects[0].rotation).assertEqual(0);
      assertNear(objects[0].centerX, 300, 0.000001);
      assertNear(objects[0].centerY, 200, 0.000001);

      const footprint = requireRect(controller.getFootprint(objects[0]));
      assertNear(footprint.x, 240, 0.000001);
      assertNear(footprint.y, 170, 0.000001);
      assertNear(footprint.width, 120, 0.000001);
      assertNear(footprint.height, 60, 0.000001);

      expect(controller.getSelectedId() === null).assertTrue();
      expect(controller.getSelectedObject() === null).assertTrue();
      expect(controller.getPreviewObject() === null).assertTrue();
      expect(!controller.isDragging()).assertTrue();
    });

    it('addObjectUsesCatalogCentreAndDeterministicUniqueIds', 0, () => {
      const controller = new EditorController('standard');
      const chair = requireObject(controller.addObject('chair', { x: 100, y: 100 }));
      expect(chair.id).assertEqual('obj-2');
      expect(chair.catalogId).assertEqual('chair');
      expect(chair.rotation).assertEqual(0);
      assertNear(chair.centerX, 100, 0.000001);
      assertNear(chair.centerY, 100, 0.000001);
      const chairFootprint = requireRect(controller.getFootprint(chair));
      assertNear(chairFootprint.x, 75, 0.000001);
      assertNear(chairFootprint.y, 75, 0.000001);
      assertNear(chairFootprint.width, 50, 0.000001);
      assertNear(chairFootprint.height, 50, 0.000001);

      const plant = requireObject(controller.addObject('plant', { x: 500, y: 100 }));
      expect(plant.id).assertEqual('obj-3');

      const objects = controller.getObjects();
      expect(objects.length).assertEqual(3);
      for (let i = 0; i < objects.length; i++) {
        for (let j = i + 1; j < objects.length; j++) {
          expect(objects[i].id !== objects[j].id).assertTrue();
        }
      }

      const another = new EditorController('standard');
      const anotherChair = requireObject(another.addObject('chair', { x: 100, y: 100 }));
      expect(anotherChair.id).assertEqual('obj-2');
    });

    // ------------------------------------------------------------------
    // Committed move and rotation
    // ------------------------------------------------------------------
    it('moveObjectCommitsValidCentreAndRejectsOutOfBounds', 0, () => {
      const controller = new EditorController('standard');
      const moved = requireObject(controller.moveObject('obj-1', { x: 400, y: 200 }));
      expect(moved.catalogId).assertEqual('display_table');
      assertNear(moved.centerX, 400, 0.000001);
      assertNear(moved.centerY, 200, 0.000001);
      expect(moved.rotation).assertEqual(0);

      const footprint = requireRect(controller.getFootprint(moved));
      assertNear(footprint.x, 340, 0.000001);
      assertNear(footprint.y, 170, 0.000001);

      const rejected = controller.moveObject('obj-1', { x: 590, y: 200 });
      expect(rejected.code).assertEqual('OUT_OF_BOUNDS');
      const committed = controller.getObjects()[0];
      assertNear(committed.centerX, 400, 0.000001);
      assertNear(committed.centerY, 200, 0.000001);
      expect(committed.rotation).assertEqual(0);
    });

    it('fourClockwiseRotationsSwapFootprintAndReturnToStart', 0, () => {
      const controller = new EditorController('standard');
      const expectedRotations: number[] = [90, 180, 270, 0];
      for (let i = 0; i < expectedRotations.length; i++) {
        const rotated = requireObject(controller.rotateObject('obj-1'));
        expect(rotated.rotation).assertEqual(expectedRotations[i]);
        assertNear(rotated.centerX, 300, 0.000001);
        assertNear(rotated.centerY, 200, 0.000001);
        const footprint = requireRect(controller.getFootprint(rotated));
        if (i === 0 || i === 2) {
          assertNear(footprint.x, 270, 0.000001);
          assertNear(footprint.y, 140, 0.000001);
          assertNear(footprint.width, 60, 0.000001);
          assertNear(footprint.height, 120, 0.000001);
        } else {
          assertNear(footprint.x, 240, 0.000001);
          assertNear(footprint.y, 170, 0.000001);
          assertNear(footprint.width, 120, 0.000001);
          assertNear(footprint.height, 60, 0.000001);
        }
      }
    });

    it('rotationNearBoundaryIsRejectedAndPreservesPreviousRotation', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.moveObject('obj-1', { x: 300, y: 350 }));
      const before = controller.getObjects()[0];
      const rejected = controller.rotateObject('obj-1');
      expect(rejected.code).assertEqual('OUT_OF_BOUNDS');

      const after = controller.getObjects()[0];
      expect(after.rotation).assertEqual(0);
      assertNear(after.centerX, 300, 0.000001);
      assertNear(after.centerY, 350, 0.000001);
      const footprint = requireRect(controller.getFootprint(after));
      assertNear(footprint.x, 240, 0.000001);
      assertNear(footprint.y, 320, 0.000001);
      assertNear(footprint.width, 120, 0.000001);
      assertNear(footprint.height, 60, 0.000001);

      expect(controller.rotateObject('missing').code).assertEqual('NOT_FOUND');
      expect(before.rotation).assertEqual(0);
    });

    it('exactBoundaryCentresAreAllowedAndBeyondIsRejected', 0, () => {
      const controller = new EditorController('standard');
      const topLeftEdge = requireObject(controller.addObject('display_table', { x: 60, y: 30 }));
      expect(topLeftEdge.id).assertEqual('obj-2');
      const topLeftFootprint = requireRect(controller.getFootprint(topLeftEdge));
      assertNear(topLeftFootprint.x, 0, 0.000001);
      assertNear(topLeftFootprint.y, 0, 0.000001);

      const pastLeft = controller.addObject('display_table', { x: 59, y: 30 });
      expect(pastLeft.code).assertEqual('OUT_OF_BOUNDS');

      const bottomEdge = requireObject(controller.addObject('display_table', { x: 300, y: 370 }));
      expect(bottomEdge.id).assertEqual('obj-3');
      const bottomFootprint = requireRect(controller.getFootprint(bottomEdge));
      assertNear(bottomFootprint.y + bottomFootprint.height, 400, 0.000001);

      const pastBottom = controller.addObject('display_table', { x: 300, y: 371 });
      expect(pastBottom.code).assertEqual('OUT_OF_BOUNDS');

      const rightEdge = requireObject(controller.addObject('display_table', { x: 540, y: 200 }));
      expect(rightEdge.id).assertEqual('obj-4');
      const rightFootprint = requireRect(controller.getFootprint(rightEdge));
      assertNear(rightFootprint.x + rightFootprint.width, 600, 0.000001);

      const pastRight = controller.addObject('display_table', { x: 541, y: 200 });
      expect(pastRight.code).assertEqual('OUT_OF_BOUNDS');

      expect(isWithinBounds({ x: 0, y: 0, width: 120, height: 60 }, 600, 400)).assertTrue();
      expect(!isWithinBounds({ x: -0.1, y: 0, width: 120, height: 60 }, 600, 400)).assertTrue();
      expect(!isWithinBounds({ x: 0, y: 0, width: 120, height: 60 }, 0, 400)).assertTrue();
      expect(!isWithinBounds({ x: Number.NaN, y: 0, width: 120, height: 60 }, 600, 400)).assertTrue();
    });

    // ------------------------------------------------------------------
    // Drag preview / commit / cancel
    // ------------------------------------------------------------------
    it('dragPreviewIsNotCommittedUntilEndDrag', 0, () => {
      const controller = new EditorController('standard');
      const started = requireObject(controller.beginDrag('obj-1', { x: 310, y: 190 }));
      assertNear(started.centerX, 300, 0.000001);
      assertNear(started.centerY, 200, 0.000001);
      expect(controller.isDragging()).assertTrue();

      const preview = requireObject(controller.updateDrag({ x: 490, y: 310 }));
      assertNear(preview.centerX, 480, 0.000001);
      assertNear(preview.centerY, 320, 0.000001);

      const committedBefore = controller.getObjects()[0];
      assertNear(committedBefore.centerX, 300, 0.000001);
      assertNear(committedBefore.centerY, 200, 0.000001);
      expect(controller.getPreviewObject() !== null).assertTrue();

      const ended = requireObject(controller.endDrag());
      assertNear(ended.centerX, 480, 0.000001);
      assertNear(ended.centerY, 320, 0.000001);
      const committedAfter = controller.getObjects()[0];
      assertNear(committedAfter.centerX, 480, 0.000001);
      assertNear(committedAfter.centerY, 320, 0.000001);
      expect(controller.getPreviewObject() === null).assertTrue();
      expect(!controller.isDragging()).assertTrue();
    });

    it('cancelDragRestoresPreviewWithoutCommitting', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.beginDrag('obj-1', { x: 310, y: 190 }));
      requireObject(controller.updateDrag({ x: 800, y: 800 }));
      expect(controller.getPreviewObject() !== null).assertTrue();

      const cancelled = controller.cancelDrag();
      expect(cancelled.code).assertEqual('OK');
      const committed = controller.getObjects()[0];
      assertNear(committed.centerX, 300, 0.000001);
      assertNear(committed.centerY, 200, 0.000001);
      expect(controller.getPreviewObject() === null).assertTrue();
      expect(!controller.isDragging()).assertTrue();
      expect(controller.cancelDrag().code).assertEqual('INVALID_ARGUMENT');
    });

    it('illegalEndDragRestoresLastCommittedCentre', 0, () => {
      const controller = new EditorController('standard');
      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      const preview = requireObject(controller.updateDrag({ x: 590, y: 200 }));
      assertNear(preview.centerX, 590, 0.000001);
      assertNear(preview.centerY, 200, 0.000001);

      const ended = controller.endDrag();
      expect(ended.code).assertEqual('OUT_OF_BOUNDS');
      const committed = controller.getObjects()[0];
      assertNear(committed.centerX, 300, 0.000001);
      assertNear(committed.centerY, 200, 0.000001);
      expect(controller.getPreviewObject() === null).assertTrue();
      expect(!controller.isDragging()).assertTrue();
      expect(controller.endDrag().code).assertEqual('INVALID_ARGUMENT');
    });

    it('dragAnchorOffsetPreventsJumpAndKeepsFinalMove', 0, () => {
      const controller = new EditorController('standard');
      const started = requireObject(controller.beginDrag('obj-1', { x: 250, y: 180 }));
      assertNear(started.centerX, 300, 0.000001);
      assertNear(started.centerY, 200, 0.000001);

      const moved = requireObject(controller.updateDrag({ x: 400, y: 300 }));
      assertNear(moved.centerX, 450, 0.000001);
      assertNear(moved.centerY, 320, 0.000001);

      // The last MOVE/UP point must be applied before endDrag commits.
      const finalPreview = requireObject(controller.updateDrag({ x: 410, y: 310 }));
      assertNear(finalPreview.centerX, 460, 0.000001);
      assertNear(finalPreview.centerY, 330, 0.000001);

      const ended = requireObject(controller.endDrag());
      assertNear(ended.centerX, 460, 0.000001);
      assertNear(ended.centerY, 330, 0.000001);
      expect(controller.getObjects()[0].centerX).assertEqual(ended.centerX);
      expect(controller.getObjects()[0].centerY).assertEqual(ended.centerY);
    });

    // ------------------------------------------------------------------
    // Explicit error semantics
    // ------------------------------------------------------------------
    it('invalidSelectClearsSelectionAndUnknownIdsReturnNotFound', 0, () => {
      const controller = new EditorController('standard');
      const selected = controller.selectObject('obj-1');
      expect(selected.code).assertEqual('OK');
      expect(controller.getSelectedId()).assertEqual('obj-1');

      const missing = controller.selectObject('does-not-exist');
      expect(missing.code).assertEqual('NOT_FOUND');
      expect(controller.getSelectedId() === null).assertTrue();

      const cleared = controller.selectObject(null);
      expect(cleared.code).assertEqual('OK');
      expect(cleared.data === null).assertTrue();
      expect(controller.getSelectedId() === null).assertTrue();

      controller.selectObject('obj-1');
      expect(controller.moveObject('missing', { x: 300, y: 200 }).code).assertEqual('NOT_FOUND');
      expect(controller.rotateObject('missing').code).assertEqual('NOT_FOUND');
      expect(controller.beginDrag('missing', { x: 300, y: 200 }).code).assertEqual('NOT_FOUND');
      expect(controller.getCatalogItem('missing').code).assertEqual('NOT_FOUND');
      expect(controller.getCatalogItem('').code).assertEqual('NOT_FOUND');
      expect(controller.addObject('missing', { x: 100, y: 100 }).code).assertEqual('NOT_FOUND');
      expect(controller.getSelectedId()).assertEqual('obj-1');
    });

    it('nanAndInfinityAreRejectedWithoutChangingCommittedState', 0, () => {
      const controller = new EditorController('standard');
      expect(controller.addObject('display_table',
        { x: Number.NaN, y: 200 }).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.addObject('display_table',
        { x: 100, y: Number.POSITIVE_INFINITY }).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.moveObject('obj-1',
        { x: Number.NaN, y: 200 }).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.moveObject('obj-1',
        { x: 300, y: Number.NEGATIVE_INFINITY }).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.beginDrag('obj-1',
        { x: Number.NaN, y: 200 }).code).assertEqual('INVALID_ARGUMENT');

      requireObject(controller.beginDrag('obj-1', { x: 300, y: 200 }));
      expect(controller.updateDrag({ x: Number.NaN, y: 200 }).code).assertEqual('INVALID_ARGUMENT');
      expect(controller.cancelDrag().code).assertEqual('OK');

      const committed = controller.getObjects()[0];
      assertNear(committed.centerX, 300, 0.000001);
      assertNear(committed.centerY, 200, 0.000001);
      expect(controller.endDrag().code).assertEqual('INVALID_ARGUMENT');
      expect(controller.updateDrag({ x: 1, y: 1 }).code).assertEqual('INVALID_ARGUMENT');
    });

    it('geometryRejectsInvalidRotationCatalogAndCentreInputs', 0, () => {
      const controller = new EditorController('standard');
      const object = controller.getObjects()[0];
      const catalog = displayTableCatalog();

      const badCentre: PlacedObject = {
        id: 'bad-centre',
        catalogId: 'display_table',
        centerX: Number.NaN,
        centerY: 200,
        rotation: 0,
        zIndex: 1
      };
      expect(getFootprintRect(badCentre, catalog).code).assertEqual('INVALID_ARGUMENT');

      const fortyFive: number = 45;
      const badRotation: PlacedObject = {
        id: 'bad-rotation',
        catalogId: 'display_table',
        centerX: 300,
        centerY: 200,
        rotation: fortyFive as Rotation,
        zIndex: 1
      };
      expect(getFootprintRect(badRotation, catalog).code).assertEqual('INVALID_ARGUMENT');
      expect(!isValidRotation(45)).assertTrue();
      expect(isValidRotation(0)).assertTrue();
      expect(isValidRotation(90)).assertTrue();
      expect(isValidRotation(180)).assertTrue();
      expect(isValidRotation(270)).assertTrue();

      const badCatalog: CatalogItem = displayTableCatalog();
      badCatalog.widthCm = 0;
      expect(getFootprintRect(object, badCatalog).code).assertEqual('INVALID_ARGUMENT');

      const badCatalogHeight: CatalogItem = displayTableCatalog();
      badCatalogHeight.heightCm = Number.NaN;
      expect(getFootprintRect(object, badCatalogHeight).code).assertEqual('INVALID_ARGUMENT');
    });

    // ------------------------------------------------------------------
    // Viewport, mapping and bounds
    // ------------------------------------------------------------------
    it('viewportIsUniformCentredLetterboxAtMultipleSizes', 0, () => {
      const square = requireViewport(createViewport(600, 400, 600, 400));
      assertNear(square.scale, 1, 0.000001);
      assertNear(square.offsetX, 0, 0.000001);
      assertNear(square.offsetY, 0, 0.000001);

      const wide = requireViewport(createViewport(800, 400, 600, 400));
      assertNear(wide.scale, 1, 0.000001);
      assertNear(wide.offsetX, 100, 0.000001);
      assertNear(wide.offsetY, 0, 0.000001);
      const wideTopLeft = requirePoint(worldToScreen({ x: 0, y: 0 }, wide));
      assertNear(wideTopLeft.x, 100, 0.000001);
      const wideBottomRight = requirePoint(worldToScreen({ x: 600, y: 400 }, wide));
      assertNear(wideBottomRight.x, 700, 0.000001);
      const wideBack = requirePoint(screenToWorld({ x: 500, y: 200 }, wide));
      assertNear(wideBack.x, 400, 0.000001);
      assertNear(wideBack.y, 200, 0.000001);

      const tall = requireViewport(createViewport(400, 600, 600, 400));
      assertNear(tall.scale, 2 / 3, 0.000001);
      assertNear(tall.offsetX, 0, 0.000001);
      assertNear(tall.offsetY, 500 / 3, 0.000001);
      const squareCentre = requirePoint(worldToScreen({ x: 300, y: 200 }, square));
      const tallCentre = requirePoint(worldToScreen({ x: 300, y: 200 }, tall));
      assertNear(squareCentre.x, 300, 0.000001);
      assertNear(squareCentre.y, 200, 0.000001);
      assertNear(tallCentre.x, 200, 0.000001);
      assertNear(tallCentre.y, 300, 0.000001);
      const tallBack = requirePoint(screenToWorld(tallCentre, tall));
      assertNear(tallBack.x, 300, 0.000001);
      assertNear(tallBack.y, 200, 0.000001);

      const small = requireViewport(createViewport(300, 300, 600, 400));
      assertNear(small.scale, 0.5, 0.000001);
      assertNear(small.offsetX, 0, 0.000001);
      assertNear(small.offsetY, 50, 0.000001);
      const smallBottomRight = requirePoint(worldToScreen({ x: 600, y: 400 }, small));
      assertNear(smallBottomRight.x, 300, 0.000001);
      assertNear(smallBottomRight.y, 250, 0.000001);
      const smallBack = requirePoint(screenToWorld(smallBottomRight, small));
      assertNear(smallBack.x, 600, 0.000001);
      assertNear(smallBack.y, 400, 0.000001);

      const padded = requireViewport(createViewport(600, 400, 600, 400, 20));
      assertNear(padded.scale, 0.9, 0.000001);
      assertNear(padded.offsetX, 30, 0.000001);
      assertNear(padded.offsetY, 20, 0.000001);

      const roundTripWorld: Point = { x: 137.5, y: 91.25 };
      const roundTripScreen = requirePoint(worldToScreen(roundTripWorld, padded));
      const roundTripBack = requirePoint(screenToWorld(roundTripScreen, padded));
      assertNear(roundTripBack.x, roundTripWorld.x, 0.000001);
      assertNear(roundTripBack.y, roundTripWorld.y, 0.000001);
    });

    it('invalidViewportInputsNeverDivideByZeroOrProduceNan', 0, () => {
      expect(createViewport(0, 400, 600, 400, 0).code).assertEqual('INVALID_ARGUMENT');
      expect(createViewport(400, 0, 600, 400, 0).code).assertEqual('INVALID_ARGUMENT');
      expect(createViewport(400, 400, 0, 400, 0).code).assertEqual('INVALID_ARGUMENT');
      expect(createViewport(400, 400, 600, 0, 0).code).assertEqual('INVALID_ARGUMENT');
      expect(createViewport(Number.NaN, 400, 600, 400, 0).code).assertEqual('INVALID_ARGUMENT');
      expect(createViewport(400, 400, 600, 400, Number.NaN).code).assertEqual('INVALID_ARGUMENT');
      expect(createViewport(400, 400, 600, 400, 200).code).assertEqual('INVALID_ARGUMENT');

      const zeroScale: Viewport = { scale: 0, offsetX: 0, offsetY: 0 };
      expect(worldToScreen({ x: 1, y: 1 }, zeroScale).code).assertEqual('INVALID_ARGUMENT');
      expect(screenToWorld({ x: 1, y: 1 }, zeroScale).code).assertEqual('INVALID_ARGUMENT');

      const nanScale: Viewport = { scale: Number.NaN, offsetX: 0, offsetY: 0 };
      expect(worldToScreen({ x: 1, y: 1 }, nanScale).code).assertEqual('INVALID_ARGUMENT');

      const nanOffset: Viewport = { scale: 1, offsetX: Number.NaN, offsetY: 0 };
      expect(worldToScreen({ x: 1, y: 1 }, nanOffset).code).assertEqual('INVALID_ARGUMENT');
      expect(screenToWorld({ x: 1, y: 1 }, nanOffset).code).assertEqual('INVALID_ARGUMENT');

      const valid: Viewport = { scale: 1, offsetX: 0, offsetY: 0 };
      expect(worldToScreen({ x: Number.NaN, y: 1 }, valid).code).assertEqual('INVALID_ARGUMENT');
      expect(screenToWorld({ x: 1, y: Number.POSITIVE_INFINITY },
        valid).code).assertEqual('INVALID_ARGUMENT');
    });

    it('overlapRequiresPositiveAreaAndEdgeContactIsNotOverlap', 0, () => {
      const base: Rect = { x: 0, y: 0, width: 100, height: 50 };
      const horizontalEdge: Rect = { x: 100, y: 0, width: 100, height: 50 };
      const verticalEdge: Rect = { x: 0, y: 50, width: 100, height: 50 };
      const positiveHorizontal: Rect = { x: 99.5, y: 0, width: 100, height: 50 };
      const positiveVertical: Rect = { x: 0, y: 49.5, width: 100, height: 50 };
      const zeroArea: Rect = { x: 10, y: 10, width: 0, height: 50 };

      expect(!overlapsPositive(base, horizontalEdge)).assertTrue();
      expect(!overlapsPositive(base, verticalEdge)).assertTrue();
      expect(overlapsPositive(base, positiveHorizontal)).assertTrue();
      expect(overlapsPositive(base, positiveVertical)).assertTrue();
      expect(!overlapsPositive(base, zeroArea)).assertTrue();

      expect(pointInRect(base, { x: 0, y: 0 })).assertTrue();
      expect(pointInRect(base, { x: 100, y: 50 })).assertTrue();
      expect(!pointInRect(base, { x: 100.1, y: 50 })).assertTrue();
      expect(!pointInRect(base, { x: Number.NaN, y: 0 })).assertTrue();
    });

    it('hitTestSelectsTopmostObjectAndHandlesEmptySpace', 0, () => {
      const controller = new EditorController('standard');
      const hit = controller.hitTest({ x: 300, y: 200 });
      expect(hit.code).assertEqual('OK');
      expect(hit.data).assertEqual('obj-1');

      const miss = controller.hitTest({ x: 10, y: 10 });
      expect(miss.code).assertEqual('OK');
      expect(miss.data === null).assertTrue();

      requireObject(controller.addObject('display_table', { x: 300, y: 200 }));
      const topmost = controller.hitTest({ x: 300, y: 200 });
      expect(topmost.code).assertEqual('OK');
      expect(topmost.data).assertEqual('obj-2');

      expect(controller.hitTest({ x: Number.NaN, y: 200 }).code).assertEqual('INVALID_ARGUMENT');
      const objects = controller.getObjects();
      expect(hitTestObjects(objects, [], { x: 300, y: 200 }).code).assertEqual('INVALID_ARGUMENT');
    });

    // ------------------------------------------------------------------
    // Copy isolation
    // ------------------------------------------------------------------
    it('returnedObjectsTemplateCatalogAndPreviewAreCopies', 0, () => {
      const controller = new EditorController('standard');
      const objects = controller.getObjects();
      objects[0].centerX = -999;
      const extra: PlacedObject = {
        id: 'extra',
        catalogId: 'chair',
        centerX: 0,
        centerY: 0,
        rotation: 0,
        zIndex: 9
      };
      objects.push(extra);
      const fresh = controller.getObjects();
      expect(fresh.length).assertEqual(1);
      assertNear(fresh[0].centerX, 300, 0.000001);

      expect(controller.selectObject('obj-1').code).assertEqual('OK');
      const selected = controller.getSelectedObject();
      expect(selected !== null).assertTrue();
      if (selected !== null) {
        selected.centerX = -1;
      }
      const selectedAgain = controller.getSelectedObject();
      expect(selectedAgain !== null).assertTrue();
      if (selectedAgain !== null) {
        assertNear(selectedAgain.centerX, 300, 0.000001);
      }

      const template = controller.getTemplate();
      template.widthCm = 1;
      template.wallSides.push('bottom');
      template.reservedAreas[0].x = -1;
      const freshTemplate = controller.getTemplate();
      expect(freshTemplate.widthCm).assertEqual(600);
      expect(freshTemplate.wallSides.length).assertEqual(3);
      expect(freshTemplate.reservedAreas[0].x).assertEqual(240);

      const catalog = controller.getCatalogItem('display_table');
      expect(catalog.code).assertEqual('OK');
      if (catalog.data !== undefined) {
        catalog.data.name = 'mutated';
      }
      const freshCatalog = controller.getCatalogItem('display_table');
      expect(freshCatalog.data !== undefined).assertTrue();
      if (freshCatalog.data !== undefined) {
        expect(freshCatalog.data.name).assertEqual('展示桌');
      }

      requireObject(controller.beginDrag('obj-1', { x: 310, y: 190 }));
      const preview = controller.getPreviewObject();
      expect(preview !== null).assertTrue();
      if (preview !== null) {
        preview.centerX = 999;
      }
      const previewAgain = controller.getPreviewObject();
      expect(previewAgain !== null).assertTrue();
      if (previewAgain !== null) {
        assertNear(previewAgain.centerX, 300, 0.000001);
      }
      expect(controller.cancelDrag().code).assertEqual('OK');
    });
  });
}
