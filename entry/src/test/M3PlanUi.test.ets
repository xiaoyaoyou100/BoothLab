import { describe, it, expect } from '@ohos/hypium';
import {
  BoothPlan,
  BoothTemplate,
  CatalogItem,
  PlacedObject,
  Rect,
  Rotation,
  Side,
  Viewport
} from '../main/ets/model/BoothModels';
import { listTemplates } from '../main/ets/catalog/BoothTemplates';
import { getCatalogItemById } from '../main/ets/catalog/ObjectCatalogData';
import { worldToScreen } from '../main/ets/engine/GeometryEngine';
import {
  drawThumbnailObject,
  drawThumbnailObjects,
  getTemplatePreviewGeometry,
  isTemplatePreviewable,
  resolveThumbnailObjectDraw,
  TemplatePreviewGeometry,
  TemplateSideSegment,
  ThumbnailObjectDraw
} from '../main/ets/components/plan/PlanThumbnail';
import {
  formatTemplateDimensions,
  formatTemplateSideSummary
} from '../main/ets/components/plan/TemplateCard';

/**
 * M3-B02 plan UI tests.
 *
 * These tests exercise the actual pure helpers used by PlanThumbnail and
 * TemplateCard: real template wall/open/reserved geometry, real catalog
 * dimensions, the existing worldToScreen mapping, actual committed rotation,
 * z-order and unknown-catalog/image-key safety. ArkUI touch handling, disabled
 * callback suppression and pixel layout are intentionally deferred to the
 * emulator because @Component methods cannot run in this local Hypium suite.
 */

class RecordedRect {
  x: number;
  y: number;
  width: number;
  height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

class RecordedPoint {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

class RecordingCanvasContext {
  fillStyle: string = '';
  strokeStyle: string = '';
  lineWidth: number = 1;
  font: string = '';
  textAlign: string = '';
  textBaseline: string = '';
  calls: string[] = [];
  saveCount: number = 0;
  restoreCount: number = 0;
  translations: RecordedPoint[] = [];
  rotations: number[] = [];
  fillRects: RecordedRect[] = [];
  strokeRects: RecordedRect[] = [];
  lineDashCalls: string[] = [];

  save(): void {
    this.calls.push('save');
    this.saveCount++;
  }

  restore(): void {
    this.calls.push('restore');
    this.restoreCount++;
  }

  translate(x: number, y: number): void {
    this.calls.push('translate');
    this.translations.push(new RecordedPoint(x, y));
  }

  rotate(angle: number): void {
    this.calls.push('rotate');
    this.rotations.push(angle);
  }

  beginPath(): void {
    this.calls.push('beginPath');
  }

  moveTo(x: number, y: number): void {
    this.calls.push('moveTo');
  }

  lineTo(x: number, y: number): void {
    this.calls.push('lineTo');
  }

  stroke(): void {
    this.calls.push('stroke');
  }

  fill(): void {
    this.calls.push('fill');
  }

  arc(centerX: number, centerY: number, radius: number,
    startAngle: number, endAngle: number): void {
    this.calls.push('arc');
  }

  fillRect(x: number, y: number, width: number, height: number): void {
    this.calls.push('fillRect');
    this.fillRects.push(new RecordedRect(x, y, width, height));
  }

  strokeRect(x: number, y: number, width: number, height: number): void {
    this.calls.push('strokeRect');
    this.strokeRects.push(new RecordedRect(x, y, width, height));
  }

  setLineDash(segments: number[]): void {
    this.calls.push('setLineDash');
    this.lineDashCalls.push(segments.join(','));
  }

  clearRect(x: number, y: number, width: number, height: number): void {
    this.calls.push('clearRect');
  }

  fillText(text: string, x: number, y: number): void {
    this.calls.push('fillText');
  }
}

function asCanvasContext(context: RecordingCanvasContext): CanvasRenderingContext2D {
  return context as Object as CanvasRenderingContext2D;
}

function expectClose(actual: number, expected: number): void {
  expect(Math.abs(actual - expected) < 0.000001).assertTrue();
}

function findSegment(segments: TemplateSideSegment[],
  side: Side): TemplateSideSegment | undefined {
  for (let i = 0; i < segments.length; i++) {
    if (segments[i].side === side) {
      return segments[i];
    }
  }
  return undefined;
}

function findTemplate(templates: BoothTemplate[], id: string): BoothTemplate {
  for (let i = 0; i < templates.length; i++) {
    if (templates[i].id === id) {
      return templates[i];
    }
  }
  throw new Error('missing template fixture: ' + id);
}

function makeViewport(scale: number, offsetX: number, offsetY: number): Viewport {
  return { scale: scale, offsetX: offsetX, offsetY: offsetY };
}

function makeObject(id: string, catalogId: string, centerX: number,
  centerY: number, rotation: Rotation, zIndex: number): PlacedObject {
  return {
    id: id,
    catalogId: catalogId,
    centerX: centerX,
    centerY: centerY,
    rotation: rotation,
    zIndex: zIndex
  };
}

function makePlan(objects: PlacedObject[]): BoothPlan {
  return {
    id: 'm3-b02-plan',
    name: 'M3-B02 测试方案',
    templateId: 'standard',
    objects: objects,
    createdAt: 1700000000000,
    updatedAt: 1700000001000
  };
}

function fingerprint(plan: BoothPlan): string {
  return JSON.stringify(plan);
}

export default function m3PlanUiTest() {
  describe('M3PlanUi', () => {
    it('usesRealTemplateWallsOpenSidesAndReservedAreas', 0, () => {
      const templates: BoothTemplate[] = listTemplates();
      expect(templates.length).assertEqual(2);
      const standard: BoothTemplate = findTemplate(templates, 'standard');
      const corner: BoothTemplate = findTemplate(templates, 'corner');
      expect(standard.name).assertEqual('标准型展位');
      expect(corner.name).assertEqual('转角型展位');
      expect(standard.widthCm).assertEqual(600);
      expect(standard.heightCm).assertEqual(400);
      expect(corner.widthCm).assertEqual(600);
      expect(corner.heightCm).assertEqual(400);

      const standardGeometry: TemplatePreviewGeometry | null =
        getTemplatePreviewGeometry(standard);
      expect(standardGeometry !== null).assertTrue();
      if (standardGeometry === null) {
        return;
      }
      expect(standardGeometry.walls.length).assertEqual(3);
      expect(standardGeometry.openSides.length).assertEqual(1);
      expect(standardGeometry.reservedAreas.length).assertEqual(1);

      const left: TemplateSideSegment | undefined =
        findSegment(standardGeometry.walls, 'left');
      const top: TemplateSideSegment | undefined =
        findSegment(standardGeometry.walls, 'top');
      const right: TemplateSideSegment | undefined =
        findSegment(standardGeometry.walls, 'right');
      const bottom: TemplateSideSegment | undefined =
        findSegment(standardGeometry.openSides, 'bottom');
      expect(left !== undefined).assertTrue();
      expect(top !== undefined).assertTrue();
      expect(right !== undefined).assertTrue();
      expect(bottom !== undefined).assertTrue();
      const leftSegment: TemplateSideSegment = left as TemplateSideSegment;
      const topSegment: TemplateSideSegment = top as TemplateSideSegment;
      const rightSegment: TemplateSideSegment = right as TemplateSideSegment;
      const bottomSegment: TemplateSideSegment = bottom as TemplateSideSegment;
      expectClose(leftSegment.x1, 0);
      expectClose(leftSegment.y1, 0);
      expectClose(leftSegment.x2, 0);
      expectClose(leftSegment.y2, 400);
      expectClose(topSegment.x1, 0);
      expectClose(topSegment.y2, 0);
      expectClose(topSegment.x2, 600);
      expectClose(rightSegment.x1, 600);
      expectClose(rightSegment.y2, 400);
      expectClose(bottomSegment.y1, 400);
      expectClose(bottomSegment.x2, 600);

      const reserved: Rect = standardGeometry.reservedAreas[0];
      expectClose(reserved.x, 240);
      expectClose(reserved.y, 340);
      expectClose(reserved.width, 120);
      expectClose(reserved.height, 60);

      const cornerGeometry: TemplatePreviewGeometry | null =
        getTemplatePreviewGeometry(corner);
      expect(cornerGeometry !== null).assertTrue();
      if (cornerGeometry === null) {
        return;
      }
      expect(cornerGeometry.walls.length).assertEqual(2);
      expect(cornerGeometry.openSides.length).assertEqual(2);
      expect(cornerGeometry.reservedAreas.length).assertEqual(2);
      expect(findSegment(cornerGeometry.walls, 'left') !== undefined).assertTrue();
      expect(findSegment(cornerGeometry.walls, 'top') !== undefined).assertTrue();
      expect(findSegment(cornerGeometry.openSides, 'bottom') !== undefined).assertTrue();
      expect(findSegment(cornerGeometry.openSides, 'right') !== undefined).assertTrue();
      expectClose(cornerGeometry.reservedAreas[1].x, 540);
      expectClose(cornerGeometry.reservedAreas[1].y, 140);
      expectClose(cornerGeometry.reservedAreas[1].width, 60);
      expectClose(cornerGeometry.reservedAreas[1].height, 120);

      // The returned geometry is a fresh copy and cannot mutate the template.
      standardGeometry.reservedAreas[0].x = -999;
      expectClose(standard.reservedAreas[0].x, 240);
    });

    it('followsActualTemplateDimensionsAndRejectsUnknownSidesSafely', 0, () => {
      const custom: BoothTemplate = {
        id: 'custom-large',
        name: '自定义大展位',
        widthCm: 800,
        heightCm: 600,
        blockedAreas: [],
        reservedAreas: [],
        wallSides: ['left', 'top', 'right', 'bottom'],
        openSides: []
      };
      const geometry: TemplatePreviewGeometry | null =
        getTemplatePreviewGeometry(custom);
      expect(geometry !== null).assertTrue();
      if (geometry === null) {
        return;
      }
      expect(geometry.walls.length).assertEqual(4);
      const right: TemplateSideSegment | undefined =
        findSegment(geometry.walls, 'right');
      const bottom: TemplateSideSegment | undefined =
        findSegment(geometry.walls, 'bottom');
      expect(right !== undefined).assertTrue();
      expect(bottom !== undefined).assertTrue();
      expectClose((right as TemplateSideSegment).x1, 800);
      expectClose((right as TemplateSideSegment).y2, 600);
      expectClose((bottom as TemplateSideSegment).y1, 600);
      expectClose((bottom as TemplateSideSegment).x2, 800);

      const unknownSide: BoothTemplate = {
        id: 'unknown-side',
        name: '未知边',
        widthCm: 500,
        heightCm: 300,
        blockedAreas: [],
        reservedAreas: [{ x: 10, y: 10, width: 0, height: 20 }],
        wallSides: ['diagonal' as Side],
        openSides: []
      };
      const unknownGeometry: TemplatePreviewGeometry | null =
        getTemplatePreviewGeometry(unknownSide);
      expect(unknownGeometry !== null).assertTrue();
      if (unknownGeometry !== null) {
        expect(unknownGeometry.walls.length).assertEqual(0);
        expect(unknownGeometry.openSides.length).assertEqual(0);
        expect(unknownGeometry.reservedAreas.length).assertEqual(0);
      }

      const nullTemplate: BoothTemplate =
        JSON.parse('null') as BoothTemplate;
      expect(isTemplatePreviewable(nullTemplate)).assertFalse();
      expect(getTemplatePreviewGeometry(nullTemplate) === null).assertTrue();

      const zeroWidth: BoothTemplate = {
        id: 'zero',
        name: '零宽',
        widthCm: 0,
        heightCm: 400,
        blockedAreas: [],
        reservedAreas: [],
        wallSides: [],
        openSides: []
      };
      expect(isTemplatePreviewable(zeroWidth)).assertFalse();
      expect(getTemplatePreviewGeometry(zeroWidth) === null).assertTrue();
    });

    it('formatsRealTemplateNamesDimensionsAndSides', 0, () => {
      const templates: BoothTemplate[] = listTemplates();
      const standard: BoothTemplate = findTemplate(templates, 'standard');
      const corner: BoothTemplate = findTemplate(templates, 'corner');
      expect(formatTemplateDimensions(standard))
        .assertEqual('600 × 400 cm · 6 × 4 m');
      expect(formatTemplateSideSummary(standard))
        .assertEqual('墙：左、上、右 · 开放：下');
      expect(formatTemplateSideSummary(corner))
        .assertEqual('墙：左、上 · 开放：下、右');

      const fractional: BoothTemplate = {
        id: 'fractional',
        name: '非整数尺寸',
        widthCm: 650,
        heightCm: 450,
        blockedAreas: [],
        reservedAreas: [],
        wallSides: ['left'],
        openSides: ['right']
      };
      expect(formatTemplateDimensions(fractional))
        .assertEqual('650 × 450 cm · 6.5 × 4.5 m');
      expect(formatTemplateSideSummary(fractional))
        .assertEqual('墙：左 · 开放：右');

      const invalid: BoothTemplate = {
        id: 'invalid',
        name: '无效',
        widthCm: NaN,
        heightCm: 200,
        blockedAreas: [],
        reservedAreas: [],
        wallSides: [],
        openSides: []
      };
      expect(formatTemplateDimensions(invalid)).assertEqual('尺寸未知');
    });

    it('resolvesObjectsWithUnrotatedCatalogExtentsAndActualRotation', 0, () => {
      const viewport: Viewport = makeViewport(0.5, 10, 20);
      const reception: CatalogItem | undefined = getCatalogItemById('reception');
      expect(reception !== undefined).assertTrue();
      if (reception === undefined) {
        return;
      }
      const rotations: Rotation[] = [0, 90, 180, 270];
      for (let i = 0; i < rotations.length; i++) {
        const object: PlacedObject =
          makeObject('o-' + i.toString(), 'reception', 300, 200, rotations[i], 0);
        const draw: ThumbnailObjectDraw | null =
          resolveThumbnailObjectDraw(viewport, object, reception);
        expect(draw !== null).assertTrue();
        if (draw === null) {
          return;
        }
        expectClose(draw.centerX, 160);
        expectClose(draw.centerY, 120);
        // 140 cm * 0.5 and 60 cm * 0.5, never swapped for 90/270.
        expectClose(draw.width, 70);
        expectClose(draw.height, 30);
        expect(draw.rotation).assertEqual(rotations[i]);
        expect(draw.imageKey).assertEqual('reception');
      }

      const shelf: CatalogItem | undefined = getCatalogItemById('shelf');
      expect(shelf !== undefined).assertTrue();
      if (shelf === undefined) {
        return;
      }
      const tallObject: PlacedObject =
        makeObject('shelf-90', 'shelf', 100, 100, 90, 0);
      const tallDraw: ThumbnailObjectDraw | null =
        resolveThumbnailObjectDraw(makeViewport(0.2, 0, 0), tallObject, shelf);
      expect(tallDraw !== null).assertTrue();
      if (tallDraw !== null) {
        expectClose(tallDraw.width, 20);
        expectClose(tallDraw.height, 8);
        expect(tallDraw.rotation).assertEqual(90);
      }
    });

    it('mapsCentresThroughTheExistingWorldToScreenFunction', 0, () => {
      const viewport: Viewport = makeViewport(0.3, 7.5, 11.25);
      const centers: number[][] = [
        [0, 0],
        [150, 250],
        [600, 400]
      ];
      const catalog: CatalogItem | undefined = getCatalogItemById('chair');
      expect(catalog !== undefined).assertTrue();
      if (catalog === undefined) {
        return;
      }
      for (let i = 0; i < centers.length; i++) {
        const object: PlacedObject = makeObject('p-' + i.toString(), 'chair',
          centers[i][0], centers[i][1], 0, 0);
        const draw: ThumbnailObjectDraw | null =
          resolveThumbnailObjectDraw(viewport, object, catalog);
        expect(draw !== null).assertTrue();
        const screen = worldToScreen({ x: centers[i][0], y: centers[i][1] }, viewport);
        expect(screen.code).assertEqual('OK');
        if (draw !== null && screen.data !== undefined) {
          expectClose(draw.centerX, screen.data.x);
          expectClose(draw.centerY, screen.data.y);
        }
      }
    });

    it('neverInventsSizeForUnknownCatalogOrInvalidGeometry', 0, () => {
      const viewport: Viewport = makeViewport(0.5, 10, 20);
      const object: PlacedObject =
        makeObject('unknown', 'not-a-catalog-id', 100, 100, 0, 0);
      const unknown: CatalogItem | undefined = getCatalogItemById('not-a-catalog-id');
      expect(unknown === undefined).assertTrue();
      expect(resolveThumbnailObjectDraw(viewport, object, unknown) === null).assertTrue();

      const context: RecordingCanvasContext = new RecordingCanvasContext();
      const drawn: boolean = drawThumbnailObject(asCanvasContext(context),
        viewport, object, unknown);
      expect(drawn).assertFalse();
      expect(context.calls.length).assertEqual(0);

      const reception: CatalogItem | undefined = getCatalogItemById('reception');
      expect(reception !== undefined).assertTrue();
      if (reception === undefined) {
        return;
      }
      const zeroWidth: CatalogItem = {
        id: 'reception',
        name: '接待台',
        category: '服务',
        imageKey: 'reception',
        widthCm: 0,
        heightCm: 60
      };
      expect(resolveThumbnailObjectDraw(viewport, object, zeroWidth) === null)
        .assertTrue();
      const nanHeight: CatalogItem = {
        id: 'reception',
        name: '接待台',
        category: '服务',
        imageKey: 'reception',
        widthCm: 140,
        heightCm: NaN
      };
      expect(resolveThumbnailObjectDraw(viewport, object, nanHeight) === null)
        .assertTrue();
      expect(resolveThumbnailObjectDraw(makeViewport(0, 10, 20),
        object, reception) === null).assertTrue();
      expect(resolveThumbnailObjectDraw(makeViewport(0.5, NaN, 20),
        object, reception) === null).assertTrue();

      const badCenter: PlacedObject =
        makeObject('bad-centre', 'reception', NaN, 100, 0, 0);
      expect(resolveThumbnailObjectDraw(viewport, badCenter, reception) === null)
        .assertTrue();
    });

    it('drawsOnlyUsableObjectsInZOrderWithActualRotationOnce', 0, () => {
      const plan: BoothPlan = makePlan([
        makeObject('top', 'reception', 300, 200, 90, 2),
        makeObject('unknown', 'not-in-catalog', 50, 50, 0, 1),
        makeObject('bottom', 'shelf', 100, 100, 270, 0)
      ]);
      const before: string = fingerprint(plan);
      const context: RecordingCanvasContext = new RecordingCanvasContext();
      const viewport: Viewport = makeViewport(0.5, 10, 20);
      const drawn: number = drawThumbnailObjects(asCanvasContext(context),
        plan, viewport);
      expect(drawn).assertEqual(2);
      expect(context.translations.length).assertEqual(2);
      // shelf (zIndex 0) first at 10+100*0.5, 20+100*0.5.
      expectClose(context.translations[0].x, 60);
      expectClose(context.translations[0].y, 70);
      // reception (zIndex 2) next at 10+300*0.5, 20+200*0.5.
      expectClose(context.translations[1].x, 160);
      expectClose(context.translations[1].y, 120);
      expect(context.rotations.length).assertEqual(2);
      expectClose(context.rotations[0], Math.PI * 1.5);
      expectClose(context.rotations[1], Math.PI * 0.5);
      expect(context.saveCount).assertEqual(2);
      expect(context.restoreCount).assertEqual(2);
      // The shelf base fill uses unrotated 100x40 cm at scale 0.5.
      expectClose(context.fillRects[0].x, -25);
      expectClose(context.fillRects[0].y, -10);
      expectClose(context.fillRects[0].width, 50);
      expectClose(context.fillRects[0].height, 20);
      expect(fingerprint(plan)).assertEqual(before);
    });

    it('usesGenericFallbackForUnknownImageKeyWithoutSwappingExtents', 0, () => {
      const viewport: Viewport = makeViewport(0.5, 10, 20);
      const unknownImage: CatalogItem = {
        id: 'reception',
        name: '接待台',
        category: '服务',
        imageKey: 'mystery_object',
        widthCm: 140,
        heightCm: 60
      };
      const object: PlacedObject =
        makeObject('mystery', 'reception', 300, 200, 270, 0);
      const objectBefore: string = JSON.stringify(object);
      const catalogBefore: string = JSON.stringify(unknownImage);
      const context: RecordingCanvasContext = new RecordingCanvasContext();
      const drawn: boolean = drawThumbnailObject(asCanvasContext(context),
        viewport, object, unknownImage);
      expect(drawn).assertTrue();
      expect(context.saveCount).assertEqual(1);
      expect(context.restoreCount).assertEqual(1);
      expect(context.rotations.length).assertEqual(1);
      expectClose(context.rotations[0], Math.PI * 1.5);
      expectClose(context.translations[0].x, 160);
      expectClose(context.translations[0].y, 120);
      // Generic fallback is still drawn with real unrotated cm extents.
      expectClose(context.fillRects[0].width, 70);
      expectClose(context.fillRects[0].height, 30);
      expect(context.lineDashCalls[0]).assertEqual('4,3');
      expect(JSON.stringify(object)).assertEqual(objectBefore);
      expect(JSON.stringify(unknownImage)).assertEqual(catalogBefore);
    });

    it('drawHelpersAreReadOnlyAndTolerateMissingData', 0, () => {
      const plan: BoothPlan = makePlan([
        makeObject('one', 'display_table', 200, 150, 0, 0)
      ]);
      const template: BoothTemplate = findTemplate(listTemplates(), 'standard');
      const planBefore: string = fingerprint(plan);
      const templateBefore: string = JSON.stringify(template);
      const catalog: CatalogItem | undefined = getCatalogItemById('display_table');
      expect(catalog !== undefined).assertTrue();
      const catalogBefore: string = catalog === undefined ? '' : JSON.stringify(catalog);

      const context: RecordingCanvasContext = new RecordingCanvasContext();
      drawThumbnailObjects(asCanvasContext(context), plan,
        makeViewport(0.25, 5, 5));
      getTemplatePreviewGeometry(template);
      formatTemplateDimensions(template);
      formatTemplateSideSummary(template);

      expect(fingerprint(plan)).assertEqual(planBefore);
      expect(JSON.stringify(template)).assertEqual(templateBefore);
      if (catalog !== undefined) {
        expect(JSON.stringify(catalog)).assertEqual(catalogBefore);
      }

      const nullContext: CanvasRenderingContext2D =
        JSON.parse('null') as CanvasRenderingContext2D;
      expect(drawThumbnailObjects(nullContext, plan,
        makeViewport(0.25, 5, 5))).assertEqual(0);
      expect(drawThumbnailObject(nullContext, makeViewport(0.25, 5, 5),
        plan.objects[0], catalog)).assertFalse();
    });
  });
}
