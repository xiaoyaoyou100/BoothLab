import { describe, it, expect } from '@ohos/hypium';
import { Point } from '../main/ets/model/BoothModels';
import { createViewport, worldToScreen, screenToWorld } from '../main/ets/engine/GeometryEngine';
import {
  EditorViewState, createEditorView, fitEditorView, resizeEditorView,
  zoomEditorView, panEditorView, focusEditorView
} from '../main/ets/components/editor/EditorViewTransform';

function view(width: number = 390, height: number = 500, zoom: number = 1): EditorViewState {
  const state = createEditorView(width, height, 600, 400, 28, zoom);
  if (state === null) { throw new Error('Expected valid view'); }
  return state;
}
function near(a: number, b: number): void {
  expect(Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a), Math.abs(b))).assertTrue();
}
function required(state: EditorViewState | null): EditorViewState {
  if (state === null) { throw new Error('Unexpected invalid view'); }
  return state;
}
export default function editorViewTransformTest(): void {
  describe('EditorViewTransform', () => {
    it('fit matches existing geometry on varied sizes and templates', 0, () => {
      const sizes: number[][] = [[390, 500], [500, 390], [57, 57], [1000, 200]];
      sizes.forEach((size: number[]) => {
        const state = view(size[0], size[1]);
        const old = createViewport(size[0], size[1], 600, 400, 28);
        expect(old.code).assertEqual('OK');
        if (old.data !== undefined) {
          near(state.viewport.scale, old.data.scale);
          near(state.viewport.offsetX, old.data.offsetX);
          near(state.viewport.offsetY, old.data.offsetY);
        }
      });
    });
    it('forward inverse roundtrip across zooms and world points', 0, () => {
      [1, 1.6, 2.5].forEach((z: number) => {
        const state = required(panEditorView(view(390, 300, z), -80, 45));
        for (let i: number = 0; i <= 20; i++) {
          const point: Point = { x: i * 30, y: i * 20 };
          const screen = worldToScreen(point, state.viewport);
          if (screen.data === undefined) { throw new Error('forward'); }
          const world = screenToWorld(screen.data, state.viewport);
          if (world.data === undefined) { throw new Error('inverse'); }
          near(world.data.x, point.x); near(world.data.y, point.y);
        }
      });
    });
    it('zoom bounds and nonfinite input', 0, () => {
      near(view(390, 500, -50).zoom, 1); near(view(390, 500, 100).zoom, 2.5);
      near(view(390, 500, Number.NaN).zoom, 1);
    });
    it('pan clamps all four boundaries', 0, () => {
      const state = view(390, 300, 2.5);
      const positive = required(panEditorView(state, 1e8, 1e8));
      near(positive.viewport.offsetX, 0); near(positive.viewport.offsetY, 0);
      const negative = required(panEditorView(state, -1e8, -1e8));
      near(negative.viewport.offsetX, 390 - 600 * state.viewport.scale);
      near(negative.viewport.offsetY, 300 - 400 * state.viewport.scale);
    });
    it('small single axis always centers', 0, () => {
      const state = required(panEditorView(view(390, 700, 1.6), 500, -500));
      near(state.viewport.offsetY, (700 - 400 * state.viewport.scale) / 2);
      const wide = required(panEditorView(view(1000, 200, 2.5), 500, -500));
      near(wide.viewport.offsetX, (1000 - 600 * wide.viewport.scale) / 2);
    });
    it('focus centers selected world point where reachable', 0, () => {
      const state = required(focusEditorView(view(390, 300), { x: 310, y: 200 }));
      near(state.zoom, 1.6);
      near(state.viewport.offsetX + 310 * state.viewport.scale, 195);
    });
    it('anchor zoom preserves world point without clamp', 0, () => {
      const before = view(390, 300, 1.6);
      const anchor: Point = { x: 180, y: 140 };
      const after = required(zoomEditorView(before, 2, anchor));
      const world = screenToWorld(anchor, before.viewport);
      if (world.data === undefined) { throw new Error('anchor'); }
      near(after.viewport.offsetX + world.data.x * after.viewport.scale, anchor.x);
      near(after.viewport.offsetY + world.data.y * after.viewport.scale, anchor.y);
    });
    it('edge anchor clamps to visible boundaries', 0, () => {
      const state = required(zoomEditorView(view(390, 300), 2.5, { x: 0, y: 0 }));
      expect(state.viewport.offsetX <= 0).assertTrue();
      expect(state.viewport.offsetX >= 390 - 600 * state.viewport.scale).assertTrue();
    });
    it('tiny and invalid dimensions fail safely', 0, () => {
      [0, -1, 1, 56, Number.NaN, Number.POSITIVE_INFINITY, 1e300].forEach((n: number) => {
        expect(createEditorView(n, 500, 600, 400, 28) === null).assertTrue();
      });
      const tiny = required(createEditorView(0.00001, 0.00001, 600, 400, 0));
      expect(Number.isFinite(tiny.viewport.scale)).assertTrue();
      const edge = view(56.00001, 56.00001, 2.5);
      expect(Number.isFinite(edge.worldFocus.x)).assertTrue();
    });
    it('resize preserves zoom and reachable focus', 0, () => {
      const state = required(panEditorView(view(390, 300, 2.5), -20, -10));
      const resized = required(resizeEditorView(state, 420, 320));
      near(resized.zoom, state.zoom);
      near(resized.worldFocus.x, state.worldFocus.x); near(resized.worldFocus.y, state.worldFocus.y);
      const back = required(resizeEditorView(resized, 390, 300));
      near(back.viewport.offsetX, state.viewport.offsetX);
      expect(resizeEditorView(state, 0, 0) === null).assertTrue();
    });
    it('fit resets all pan and zoom', 0, () => {
      const state = required(fitEditorView(required(panEditorView(view(390, 300, 2.5), 99, -55))));
      const initial = view(390, 300);
      near(state.zoom, 1); near(state.viewport.offsetX, initial.viewport.offsetX);
      near(state.viewport.offsetY, initial.viewport.offsetY);
    });
    it('nonfinite gestures stay finite and do not mutate input', 0, () => {
      const state = view(); const scale: number = state.viewport.scale;
      const result = required(panEditorView(state, Number.POSITIVE_INFINITY, 5));
      near(result.viewport.scale, scale); near(state.zoom, 1);
      const focus = required(focusEditorView(state, { x: Number.NaN, y: Number.POSITIVE_INFINITY }));
      expect(Number.isFinite(focus.viewport.offsetX)).assertTrue();
    });
  });
}
