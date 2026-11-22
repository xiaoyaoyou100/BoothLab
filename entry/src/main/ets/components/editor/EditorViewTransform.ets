import { Point, Viewport } from '../../model/BoothModels';

export const VIEW_ZOOM_MIN: number = 1;
export const VIEW_ZOOM_MAX: number = 2.5;
export const VIEW_ZOOM_STEP: number = 0.25;
export const VIEW_FOCUS_ZOOM: number = 1.6;

/** Session-only presentation state. Units: world cm, Canvas-local vp. */
export interface EditorViewState {
  zoom: number;
  worldFocus: Point;
  width: number;
  height: number;
  worldWidth: number;
  worldHeight: number;
  padding: number;
  viewport: Viewport;
}

function boundedSize(value: number): boolean {
  // Reject unusable/extreme input instead of propagating overflow/underflow.
  return Number.isFinite(value) && value >= 0.000001 && value <= 1000000000;
}

function clamp(value: number, low: number, high: number): number {
  return Math.max(low, Math.min(high, value));
}

function axisOffset(offset: number, projected: number, available: number): number {
  return projected <= available ? (available - projected) / 2 :
    clamp(offset, available - projected, 0);
}

/** Invalid canvas/world sizes have no effective viewport; never invent geometry. */
export function createEditorView(width: number, height: number, worldWidth: number,
  worldHeight: number, padding: number, zoom: number = 1,
  focus: Point | null = null): EditorViewState | null {
  if (!boundedSize(width) || !boundedSize(height) || !boundedSize(worldWidth) ||
    !boundedSize(worldHeight) || !Number.isFinite(padding) || padding < 0 ||
    width <= 2 * padding || height <= 2 * padding) {
    return null;
  }
  const z: number = Number.isFinite(zoom) ? clamp(zoom, VIEW_ZOOM_MIN, VIEW_ZOOM_MAX) : 1;
  const s0: number = Math.min((width - 2 * padding) / worldWidth,
    (height - 2 * padding) / worldHeight);
  const scale: number = s0 * z;
  if (!Number.isFinite(scale) || scale <= 0) {
    return null;
  }
  const fx: number = focus !== null && Number.isFinite(focus.x) ?
    clamp(focus.x, 0, worldWidth) : worldWidth / 2;
  const fy: number = focus !== null && Number.isFinite(focus.y) ?
    clamp(focus.y, 0, worldHeight) : worldHeight / 2;
  const offsetX: number = axisOffset(width / 2 - fx * scale, worldWidth * scale, width);
  const offsetY: number = axisOffset(height / 2 - fy * scale, worldHeight * scale, height);
  const viewport: Viewport = { scale: scale, offsetX: offsetX, offsetY: offsetY };
  const actualFocus: Point = {
    x: (width / 2 - offsetX) / scale,
    y: (height / 2 - offsetY) / scale
  };
  const state: EditorViewState = {
    zoom: z, worldFocus: actualFocus, width: width, height: height,
    worldWidth: worldWidth, worldHeight: worldHeight, padding: padding, viewport: viewport
  };
  return state;
}

export function fitEditorView(state: EditorViewState): EditorViewState | null {
  return createEditorView(state.width, state.height, state.worldWidth,
    state.worldHeight, state.padding);
}

export function resizeEditorView(state: EditorViewState, width: number,
  height: number): EditorViewState | null {
  return createEditorView(width, height, state.worldWidth, state.worldHeight,
    state.padding, state.zoom, state.worldFocus);
}

/** Anchor is Canvas-local vp. Clamp may move an edge anchor, by design. */
export function zoomEditorView(state: EditorViewState, zoom: number,
  anchor: Point): EditorViewState | null {
  if (!Number.isFinite(anchor.x) || !Number.isFinite(anchor.y)) {
    return state;
  }
  const next = createEditorView(state.width, state.height, state.worldWidth,
    state.worldHeight, state.padding, zoom);
  if (next === null) {
    return null;
  }
  const x: number = (anchor.x - state.viewport.offsetX) / state.viewport.scale;
  const y: number = (anchor.y - state.viewport.offsetY) / state.viewport.scale;
  const focus: Point = {
    x: x + (state.width / 2 - anchor.x) / next.viewport.scale,
    y: y + (state.height / 2 - anchor.y) / next.viewport.scale
  };
  return createEditorView(state.width, state.height, state.worldWidth,
    state.worldHeight, state.padding, next.zoom, focus);
}

export function focusEditorView(state: EditorViewState, center: Point): EditorViewState | null {
  return createEditorView(state.width, state.height, state.worldWidth,
    state.worldHeight, state.padding, VIEW_FOCUS_ZOOM, center);
}

/** Pan delta is already vp: do not multiply by density or scale. */
export function panEditorView(state: EditorViewState, dx: number,
  dy: number): EditorViewState | null {
  if (!Number.isFinite(dx) || !Number.isFinite(dy)) {
    return state;
  }
  const focus: Point = {
    x: state.worldFocus.x - dx / state.viewport.scale,
    y: state.worldFocus.y - dy / state.viewport.scale
  };
  return createEditorView(state.width, state.height, state.worldWidth,
    state.worldHeight, state.padding, state.zoom, focus);
}
