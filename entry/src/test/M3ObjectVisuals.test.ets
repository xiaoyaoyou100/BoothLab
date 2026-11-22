import { describe, it, expect } from '@ohos/hypium';
import { Rotation } from '../main/ets/model/BoothModels';
import {
  drawObjectVisual,
  getObjectVisualStyle,
  ObjectVisualStyle
} from '../main/ets/components/catalog/ObjectVisuals';

/**
 * M3-B01 ObjectVisuals tests.
 *
 * These are pure drawing-contract tests. The recording context captures the
 * Canvas method calls produced by drawObjectVisual so the tests prove the
 * actual translation/rotation/restore order and the unswapped footprint, not
 * just a copy of the style table. ArkUI rendering and touch behaviour are not
 * claimed by these tests.
 */

const STABLE_KEYS: string[] = [
  'reception',
  'display_table',
  'shelf',
  'interactive_screen',
  'chair',
  'storage',
  'sign',
  'plant',
  'plinth',
  'rollup'
];

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

class RecordingCanvasContext {
  fillStyle: string = '';
  strokeStyle: string = '';
  lineWidth: number = 1;
  calls: string[] = [];
  saveCount: number = 0;
  restoreCount: number = 0;
  translatedX: number = 0;
  translatedY: number = 0;
  rotatedRadians: number = 0;
  rotationCount: number = 0;
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
    this.translatedX = x;
    this.translatedY = y;
  }

  rotate(angle: number): void {
    this.calls.push('rotate');
    this.rotatedRadians = angle;
    this.rotationCount++;
  }

  closePath(): void {
    this.calls.push('closePath');
  }

  quadraticCurveTo(cpX: number, cpY: number, endX: number, endY: number): void {
    this.calls.push('quadraticCurveTo:' + [cpX, cpY, endX, endY].join(','));
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
}

class ThrowingCanvasContext extends RecordingCanvasContext {
  strokeRect(x: number, y: number, width: number, height: number): void {
    throw new Error('draw failure probe');
  }
}

function asCanvasContext(context: RecordingCanvasContext): CanvasRenderingContext2D {
  return context as Object as CanvasRenderingContext2D;
}

function drawOn(context: RecordingCanvasContext, imageKey: string,
  centerX: number, centerY: number, width: number, height: number,
  rotation: Rotation): void {
  drawObjectVisual(asCanvasContext(context), imageKey, centerX, centerY,
    width, height, rotation);
}

function expectClose(actual: number, expected: number): void {
  expect(Math.abs(actual - expected) < 0.000001).assertTrue();
}

function isHexColor(value: string): boolean {
  return typeof value === 'string' && value.length === 7 && value.charAt(0) === '#';
}

/**
 * A stable fingerprint of the operations after the initial save/translate/
 * rotate. Style writes are intentionally excluded so the fingerprint proves
 * the geometric detail differs, not just the colours.
 */
function detailSignature(context: RecordingCanvasContext, imageKey: string): string {
  drawOn(context, imageKey, 100, 100, 120, 60, 0);
  const parts: string[] = [];
  let seenRotate: boolean = false;
  for (let i = 0; i < context.calls.length; i++) {
    const call: string = context.calls[i];
    if (!seenRotate) {
      if (call === 'rotate') {
        seenRotate = true;
      }
      continue;
    }
    if (call === 'restore') {
      break;
    }
    parts.push(call);
  }
  return parts.join('|') + ':' +
    context.fillRects.length.toString() + ':' + context.strokeRects.length.toString();
}

export default function m3ObjectVisualsTest() {
  describe('M3ObjectVisuals', () => {
    it('mapsEveryStableKeyToItsOwnStyleAndShape', 0, () => {
      expect(STABLE_KEYS.length).assertEqual(10);
      const shapes: string[] = [];
      for (let i = 0; i < STABLE_KEYS.length; i++) {
        const key: string = STABLE_KEYS[i];
        const style: ObjectVisualStyle = getObjectVisualStyle(key);
        expect(style.imageKey).assertEqual(key);
        expect(style.shape).assertEqual(key);
        expect(isHexColor(style.fillColor)).assertTrue();
        expect(isHexColor(style.strokeColor)).assertTrue();
        expect(isHexColor(style.detailColor)).assertTrue();
        let duplicate: boolean = false;
        for (let j = 0; j < shapes.length; j++) {
          if (shapes[j] === style.shape) {
            duplicate = true;
          }
        }
        expect(duplicate).assertFalse();
        shapes.push(style.shape);
      }
      expect(shapes.length).assertEqual(10);
    });

    it('unknownAndInvalidKeysUseSafeGenericFallback', 0, () => {
      const keys: string[] = ['unknown', '', 'RECEPTION', 'reception ', 'display-table'];
      for (let i = 0; i < keys.length; i++) {
        const style: ObjectVisualStyle = getObjectVisualStyle(keys[i]);
        expect(style.imageKey).assertEqual('generic');
        expect(style.shape).assertEqual('generic');
        expect(isHexColor(style.fillColor)).assertTrue();
      }
    });

    it('styleLookupsAreIndependentAndDoNotShareMutableState', 0, () => {
      const first: ObjectVisualStyle = getObjectVisualStyle('reception');
      const second: ObjectVisualStyle = getObjectVisualStyle('reception');
      expect(first !== second).assertTrue();

      first.fillColor = '#000000';
      first.strokeColor = '#000000';
      first.detailColor = '#000000';
      first.shape = 'mutated';

      const fresh: ObjectVisualStyle = getObjectVisualStyle('reception');
      expect(fresh.fillColor).assertEqual('#E8F2EF');
      expect(fresh.shape).assertEqual('reception');
      expect(fresh.imageKey).assertEqual('reception');
    });

    it('translatesToCentreAndRotatesClockwiseAtEveryLegalAngle', 0, () => {
      const rotations: Rotation[] = [0, 90, 180, 270];
      const expectedRadians: number[] = [
        0,
        Math.PI * 0.5,
        Math.PI,
        Math.PI * 1.5
      ];
      for (let i = 0; i < rotations.length; i++) {
        const context: RecordingCanvasContext = new RecordingCanvasContext();
        drawOn(context, 'reception', 140, 90, 120, 40, rotations[i]);

        expect(context.calls[0]).assertEqual('save');
        expect(context.calls[1]).assertEqual('translate');
        expectClose(context.translatedX, 140);
        expectClose(context.translatedY, 90);
        expect(context.calls[2]).assertEqual('rotate');
        expectClose(context.rotatedRadians, expectedRadians[i]);
        expect(context.calls[context.calls.length - 1]).assertEqual('restore');
        expect(context.saveCount).assertEqual(1);
        expect(context.restoreCount).assertEqual(1);
      }
    });

    it('drawsUnrotatedFootprintExtentsAfterRotationWithoutSwapping', 0, () => {
      const rotations: Rotation[] = [0, 90, 180, 270];
      for (let i = 0; i < rotations.length; i++) {
        const context: RecordingCanvasContext = new RecordingCanvasContext();
        drawOn(context, 'display_table', 50, 60, 120, 60, rotations[i]);
        expect(context.fillRects.length > 0).assertTrue();
        const base: RecordedRect = context.fillRects[0];
        expectClose(base.x, -60);
        expectClose(base.y, -30);
        expectClose(base.width, 120);
        expectClose(base.height, 60);

        // The 100:40 catalog footprint has an inset rear rail and open front.
        const shelf: RecordingCanvasContext = new RecordingCanvasContext();
        drawOn(shelf, 'shelf', 73, 41, 100, 40, rotations[i]);
        expect(shelf.calls.slice(0, 3).join(',')).assertEqual('save,translate,rotate');
        expect(shelf.calls[shelf.calls.length - 1]).assertEqual('restore');
        expect(shelf.saveCount).assertEqual(1);
        expect(shelf.restoreCount).assertEqual(1);
        expect(shelf.rotationCount).assertEqual(1);
        expectClose(shelf.translatedX, 73);
        expectClose(shelf.translatedY, 41);
        expectClose(shelf.rotatedRadians, i * Math.PI / 2);

        const rail: RecordedRect = shelf.fillRects[0];
        expectClose(rail.x, -45.5);
        expectClose(rail.y, -17);
        expectClose(rail.width, 91);
        expectClose(rail.height, 4.8);
        const localCalls: string[] = shelf.calls.slice(3, -1);
        expect(localCalls.length).assertEqual(shelf.fillRects.length);
        for (let j = 0; j < localCalls.length; j++) {
          expect(localCalls[j]).assertEqual('fillRect');
          const rect: RecordedRect = shelf.fillRects[j];
          expect(rect.width > 0 && rect.height > 0 &&
            rect.x >= -50 && rect.y >= -20 &&
            rect.x + rect.width <= 50 && rect.y + rect.height <= 20).assertTrue();
        }
      }
    });

    it('drawsDistinctGeometricDetailsForAllStableKeys', 0, () => {
      const signatures: string[] = [];
      for (let i = 0; i < STABLE_KEYS.length; i++) {
        const context: RecordingCanvasContext = new RecordingCanvasContext();
        const signature: string = detailSignature(context, STABLE_KEYS[i]);
        let duplicate: boolean = false;
        for (let j = 0; j < signatures.length; j++) {
          if (signatures[j] === signature) {
            duplicate = true;
          }
        }
        expect(duplicate).assertFalse();
        const key: string = STABLE_KEYS[i];
        if (key === 'interactive_screen' || key === 'plant' || key === 'plinth') {
          expect(signature.indexOf('closePath|fill') >= 0).assertTrue();
        }
        if (key === 'plant') {
          expect(signature.indexOf('quadraticCurveTo:') >= 0).assertTrue();
        }
        expect(context.fillRects.length > 0).assertTrue();
        signatures.push(signature);
      }
      expect(signatures.length).assertEqual(10);
    });

    it('drawsUnknownKeysWithGenericDashedGeometry', 0, () => {
      const context: RecordingCanvasContext = new RecordingCanvasContext();
      drawOn(context, 'mystery_object', 30, 40, 80, 60, 0);
      expect(context.fillRects.length > 0).assertTrue();
      expect(context.lineDashCalls.length >= 2).assertTrue();
      expect(context.lineDashCalls[0]).assertEqual('4,3');
      expect(context.lineDashCalls[context.lineDashCalls.length - 1]).assertEqual('');
      expect(context.saveCount).assertEqual(1);
      expect(context.restoreCount).assertEqual(1);
    });

    it('ignoresInvalidDimensionsCentresAndContextSafely', 0, () => {
      const cases: number[][] = [
        [0, 40],
        [-10, 40],
        [40, 0],
        [40, -10],
        [NaN, 40],
        [40, NaN],
        [Infinity, 40],
        [40, Infinity]
      ];
      for (let i = 0; i < cases.length; i++) {
        const context: RecordingCanvasContext = new RecordingCanvasContext();
        drawOn(context, 'reception', 10, 10, cases[i][0], cases[i][1], 0);
        expect(context.calls.length).assertEqual(0);
        expect(context.saveCount).assertEqual(0);
      }

      const badCentre: RecordingCanvasContext = new RecordingCanvasContext();
      drawOn(badCentre, 'reception', NaN, 10, 80, 40, 0);
      expect(badCentre.calls.length).assertEqual(0);

      const badCentreY: RecordingCanvasContext = new RecordingCanvasContext();
      drawOn(badCentreY, 'reception', 10, Infinity, 80, 40, 0);
      expect(badCentreY.calls.length).assertEqual(0);

      const nullContext: CanvasRenderingContext2D =
        JSON.parse('null') as CanvasRenderingContext2D;
      drawObjectVisual(nullContext, 'reception', 10, 10, 80, 40, 0);
    });

    it('treatsInvalidRuntimeRotationAsZeroDegrees', 0, () => {
      const context: RecordingCanvasContext = new RecordingCanvasContext();
      drawOn(context, 'chair', 20, 30, 50, 50, 45 as Rotation);
      expect(context.rotationCount).assertEqual(1);
      expectClose(context.rotatedRadians, 0);
      expect(context.fillRects.length > 0).assertTrue();
    });

    it('restoresCanvasStateEvenWhenDrawingThrows', 0, () => {
      const context: ThrowingCanvasContext = new ThrowingCanvasContext();
      let threw: boolean = false;
      try {
        drawOn(context, 'storage', 20, 30, 90, 50, 0);
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
      expect(context.saveCount).assertEqual(1);
      expect(context.restoreCount).assertEqual(1);
      expect(context.calls[context.calls.length - 1]).assertEqual('restore');
    });
  });
}
