/**
 * BoothLab public business models (M1).
 *
 * Shared conventions:
 * - All geometry uses world coordinates in centimetres (cm).
 * - The world origin is the top-left corner of the booth; x grows right, y grows down.
 * - Rect x/y is the top-left corner; width/height are positive extents.
 * - PlacedObject position is its centre point, not its top-left corner.
 * - Edge-touching is allowed. Only intersections with positive area are overlaps;
 *   zero-area contact along an edge is not an overlap.
 *
 * Preview versus committed state:
 * - The objects stored in a BoothPlan are committed state. During a drag or a
 *   proposed rotation the editor may compute a preview, but that preview must
 *   not be written into a BoothPlan. A plan is updated only when the operation
 *   is committed (for example, once on drag end).
 * - Screen-space values such as Viewport are presentation state and must never
 *   be persisted as world coordinates.
 *
 * This file intentionally contains declarations only: no storage, history,
 * geometry, or UI implementation belongs here.
 */

/** Axis-aligned rectangle in world coordinates (cm). x/y is the top-left corner. */
export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Supported object rotation in degrees, clockwise. */
export type Rotation = 0 | 90 | 180 | 270;

/** A side of the booth boundary. */
export type Side = 'left' | 'top' | 'right' | 'bottom';

/**
 * Booth template description in world coordinates (cm).
 *
 * blockedAreas cannot be occupied by placed objects. reservedAreas are
 * reserved/reminder regions rather than a compliance conclusion. wallSides
 * are enclosed sides; openSides are open/entrance sides.
 */
export interface BoothTemplate {
  id: string;
  name: string;
  widthCm: number;
  heightCm: number;
  blockedAreas: Rect[];
  reservedAreas: Rect[];
  wallSides: Side[];
  openSides: Side[];
}

/**
 * Catalog item definition. widthCm/heightCm describe the unrotated footprint.
 * imageKey is a stable reference, not a runtime image object.
 */
export interface CatalogItem {
  id: string;
  name: string;
  category: string;
  imageKey: string;
  widthCm: number;
  heightCm: number;
}

/**
 * A placed object in a BoothPlan (committed state).
 * centerX/centerY are world coordinates (cm) of the object's centre.
 * A 90 or 270 degree rotation swaps the rendered/collision footprint extents.
 */
export interface PlacedObject {
  id: string;
  catalogId: string;
  centerX: number;
  centerY: number;
  rotation: Rotation;
  zIndex: number;
}

/** A saved booth plan. createdAt/updatedAt are epoch timestamps (ms). */
export interface BoothPlan {
  id: string;
  name: string;
  templateId: string;
  objects: PlacedObject[];
  createdAt: number;
  updatedAt: number;
}

/**
 * Persistence envelope. schemaVersion is the data-format version (first
 * version is 1), not a document revision. activePlanId is null when no plan
 * is active. Declarations only; persistence is not implemented in M1.
 */
export interface PlanStore {
  schemaVersion: number;
  plans: BoothPlan[];
  activePlanId: string | null;
}

/**
 * A layout validation issue. code identifies the issue type and severity is
 * a validator-provided classification. objectIds lists the affected placed
 * objects and is empty when the issue is not object-specific.
 */
export interface LayoutIssue {
  code: string;
  severity: string;
  message: string;
  objectIds: string[];
}

/** Stable operation result codes shared across all modules. */
export type OperationCode =
  | 'OK'
  | 'NOT_FOUND'
  | 'INVALID_ARGUMENT'
  | 'OUT_OF_BOUNDS'
  | 'NO_HISTORY'
  | 'PERSISTENCE_ERROR'
  | 'UNSUPPORTED_SCHEMA'
  | 'CORRUPTED_DATA';

/**
 * Uniform operation result. message is user-readable or diagnostic context;
 * data is present only when the operation can return a value.
 */
export interface OperationResult<T> {
  code: OperationCode;
  message: string;
  data?: T;
}

/** Coordinate pair. Callers specify world cm or Canvas-local vp; never mix units. */
export interface Point {
  x: number;
  y: number;
}

/**
 * Screen-space world-to-screen transform state. scale is Canvas-local vp per cm;
 * offsetX/offsetY are the canvas-space origin in vp. Presentation only,
 * never persisted.
 */
export interface Viewport {
  scale: number;
  offsetX: number;
  offsetY: number;
}
