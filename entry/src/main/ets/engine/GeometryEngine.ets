/**
 * BoothLab geometry engine (M1-A01).
 *
 * Pure world/canvas geometry. This file has no UI dependency.
 *
 * Conventions (see model/BoothModels.ets):
 * - World coordinates are centimetres; origin is the top-left of the booth,
 *   x grows right and y grows down.
 * - Rect x/y is the top-left corner; width/height are positive extents.
 * - PlacedObject position is its centre point.
 * - A 90 or 270 degree rotation swaps the footprint width and height.
 * - Canvas-local values are vp. Viewport.scale is vp per cm, so callers must
 *   never multiply by display density a second time.
 *
 * Invalid input is rejected with an explicit OperationResult code instead of
 * throwing; the geometry functions never hold mutable business state.
 */

import {
  CatalogItem,
  OperationResult,
  PlacedObject,
  Point,
  Rect,
  Viewport
} from '../model/BoothModels';

/** Letterbox padding used by the M1 editor Canvas, in vp. */
export const DEFAULT_VIEWPORT_PADDING_VP: number = 28;

function isFiniteNumber(value: number): boolean {
  return Number.isFinite(value);
}

function isFinitePositive(value: number): boolean {
  return Number.isFinite(value) && value > 0;
}

/** A rect is usable only when every component is finite and both extents are positive. */
export function isValidRect(rect: Rect): boolean {
  return isFiniteNumber(rect.x) && isFiniteNumber(rect.y) &&
    isFiniteNumber(rect.width) && isFiniteNumber(rect.height) &&
    rect.width > 0 && rect.height > 0;
}

/** Supported rotations are exactly 0, 90, 180 and 270 degrees. */
export function isValidRotation(value: number): boolean {
  return value === 0 || value === 90 || value === 180 || value === 270;
}

/** A viewport is usable only with a finite positive scale and finite offsets. */
export function isValidViewport(viewport: Viewport): boolean {
  return isFinitePositive(viewport.scale) &&
    isFiniteNumber(viewport.offsetX) &&
    isFiniteNumber(viewport.offsetY);
}

/**
 * Returns the axis-aligned footprint of a placed object.
 * catalog.widthCm/heightCm are the unrotated extents; 90/270 swap them.
 * Rotation, centre coordinates and catalog dimensions are validated.
 */
export function getFootprintRect(object: PlacedObject, catalog: CatalogItem): OperationResult<Rect> {
  if (!isFiniteNumber(object.centerX) || !isFiniteNumber(object.centerY)) {
    const invalid: OperationResult<Rect> = {
      code: 'INVALID_ARGUMENT',
      message: 'Object centre must be finite.'
    };
    return invalid;
  }
  if (!isValidRotation(object.rotation)) {
    const invalid: OperationResult<Rect> = {
      code: 'INVALID_ARGUMENT',
      message: 'Rotation must be one of 0, 90, 180 or 270 degrees.'
    };
    return invalid;
  }
  if (!isFinitePositive(catalog.widthCm) || !isFinitePositive(catalog.heightCm)) {
    const invalid: OperationResult<Rect> = {
      code: 'INVALID_ARGUMENT',
      message: 'Catalog dimensions must be finite and positive.'
    };
    return invalid;
  }

  const swapsExtents: boolean = object.rotation === 90 || object.rotation === 270;
  const width: number = swapsExtents ? catalog.heightCm : catalog.widthCm;
  const height: number = swapsExtents ? catalog.widthCm : catalog.heightCm;
  const rect: Rect = {
    x: object.centerX - width / 2,
    y: object.centerY - height / 2,
    width: width,
    height: height
  };
  if (!isValidRect(rect)) {
    const invalid: OperationResult<Rect> = {
      code: 'INVALID_ARGUMENT',
      message: 'Computed footprint is not finite.'
    };
    return invalid;
  }
  const result: OperationResult<Rect> = {
    code: 'OK',
    message: 'Footprint computed.',
    data: rect
  };
  return result;
}

/**
 * True when the rect lies fully inside the booth world. Touching a boundary is
 * allowed. Invalid rects or invalid template dimensions return false.
 */
export function isWithinBounds(rect: Rect, widthCm: number, heightCm: number): boolean {
  if (!isValidRect(rect) || !isFinitePositive(widthCm) || !isFinitePositive(heightCm)) {
    return false;
  }
  return rect.x >= 0 && rect.y >= 0 &&
    rect.x + rect.width <= widthCm &&
    rect.y + rect.height <= heightCm;
}

/**
 * True only when two rects share a positive-area intersection. Edge contact
 * (zero intersection width or height) is not an overlap. Invalid rects are
 * treated as non-overlapping so the helper is safe for callers.
 */
export function overlapsPositive(a: Rect, b: Rect): boolean {
  if (!isValidRect(a) || !isValidRect(b)) {
    return false;
  }
  const left: number = Math.max(a.x, b.x);
  const right: number = Math.min(a.x + a.width, b.x + b.width);
  const top: number = Math.max(a.y, b.y);
  const bottom: number = Math.min(a.y + a.height, b.y + b.height);
  return right - left > 0 && bottom - top > 0;
}

/** Plane hit test for one rect; a point exactly on the edge counts as inside. */
export function pointInRect(rect: Rect, point: Point): boolean {
  if (!isValidRect(rect) || !isFiniteNumber(point.x) || !isFiniteNumber(point.y)) {
    return false;
  }
  return point.x >= rect.x && point.x <= rect.x + rect.width &&
    point.y >= rect.y && point.y <= rect.y + rect.height;
}

/**
 * Builds a uniform-scale, centre-letterboxed viewport for a world size.
 * scale = min(available width / world width, available height / world height).
 * The four-argument form is the pure letterbox. paddingVp is optional
 * Canvas-local vp used by the editor UI to keep drawing away from the edge.
 * Zero/negative world or canvas dimensions, non-finite values, and padding
 * that leaves no drawable area are rejected before any division.
 */
export function createViewport(widthVp: number, heightVp: number, worldWidth: number,
  worldHeight: number, paddingVp: number = 0): OperationResult<Viewport> {
  if (!isFinitePositive(widthVp) || !isFinitePositive(heightVp) ||
    !isFinitePositive(worldWidth) || !isFinitePositive(worldHeight) ||
    !isFiniteNumber(paddingVp) || paddingVp < 0) {
    const invalid: OperationResult<Viewport> = {
      code: 'INVALID_ARGUMENT',
      message: 'Canvas, world and padding values must be finite; sizes must be positive and padding non-negative.'
    };
    return invalid;
  }

  const availableWidth: number = widthVp - paddingVp * 2;
  const availableHeight: number = heightVp - paddingVp * 2;
  if (!isFinitePositive(availableWidth) || !isFinitePositive(availableHeight)) {
    const invalid: OperationResult<Viewport> = {
      code: 'INVALID_ARGUMENT',
      message: 'Padding leaves no drawable canvas area.'
    };
    return invalid;
  }

  const scale: number = Math.min(availableWidth / worldWidth, availableHeight / worldHeight);
  if (!isFinitePositive(scale)) {
    const invalid: OperationResult<Viewport> = {
      code: 'INVALID_ARGUMENT',
      message: 'Viewport scale is not finite and positive.'
    };
    return invalid;
  }

  const viewport: Viewport = {
    scale: scale,
    offsetX: paddingVp + (availableWidth - worldWidth * scale) / 2,
    offsetY: paddingVp + (availableHeight - worldHeight * scale) / 2
  };
  if (!isValidViewport(viewport)) {
    const invalid: OperationResult<Viewport> = {
      code: 'INVALID_ARGUMENT',
      message: 'Viewport offsets are not finite.'
    };
    return invalid;
  }

  const result: OperationResult<Viewport> = {
    code: 'OK',
    message: 'Viewport computed.',
    data: viewport
  };
  return result;
}

/** Maps a world point (cm) to Canvas-local vp. No density multiplication. */
export function worldToScreen(point: Point, viewport: Viewport): OperationResult<Point> {
  if (!isValidViewport(viewport) || !isFiniteNumber(point.x) || !isFiniteNumber(point.y)) {
    const invalid: OperationResult<Point> = {
      code: 'INVALID_ARGUMENT',
      message: 'Point and viewport must be finite; scale must be positive.'
    };
    return invalid;
  }
  const screen: Point = {
    x: viewport.offsetX + point.x * viewport.scale,
    y: viewport.offsetY + point.y * viewport.scale
  };
  if (!isFiniteNumber(screen.x) || !isFiniteNumber(screen.y)) {
    const invalid: OperationResult<Point> = {
      code: 'INVALID_ARGUMENT',
      message: 'Mapped screen point is not finite.'
    };
    return invalid;
  }
  const result: OperationResult<Point> = {
    code: 'OK',
    message: 'World point mapped to screen.',
    data: screen
  };
  return result;
}

/**
 * Maps a Canvas-local vp point back to world cm. This is the exact inverse of
 * worldToScreen for a valid viewport; a zero/NaN scale can never reach division.
 */
export function screenToWorld(point: Point, viewport: Viewport): OperationResult<Point> {
  if (!isValidViewport(viewport) || !isFiniteNumber(point.x) || !isFiniteNumber(point.y)) {
    const invalid: OperationResult<Point> = {
      code: 'INVALID_ARGUMENT',
      message: 'Point and viewport must be finite; scale must be positive.'
    };
    return invalid;
  }
  const world: Point = {
    x: (point.x - viewport.offsetX) / viewport.scale,
    y: (point.y - viewport.offsetY) / viewport.scale
  };
  if (!isFiniteNumber(world.x) || !isFiniteNumber(world.y)) {
    const invalid: OperationResult<Point> = {
      code: 'INVALID_ARGUMENT',
      message: 'Mapped world point is not finite.'
    };
    return invalid;
  }
  const result: OperationResult<Point> = {
    code: 'OK',
    message: 'Screen point mapped to world.',
    data: world
  };
  return result;
}

/**
 * Topmost hit test over placed objects. Objects are matched to their catalog
 * definitions; a higher zIndex wins and a later array entry wins a tie.
 * Returns OK with a null id when nothing is hit. Invalid runtime rotation,
 * catalog or zIndex is an explicit INVALID_ARGUMENT rather than a silent miss.
 */
export function hitTestObjects(objects: PlacedObject[], catalogs: CatalogItem[],
  point: Point): OperationResult<string | null> {
  if (!isFiniteNumber(point.x) || !isFiniteNumber(point.y)) {
    const invalid: OperationResult<string | null> = {
      code: 'INVALID_ARGUMENT',
      message: 'Hit-test point must be finite.'
    };
    return invalid;
  }

  let hitId: string | null = null;
  let hitZIndex: number = Number.NEGATIVE_INFINITY;
  for (let i = 0; i < objects.length; i++) {
    const object: PlacedObject = objects[i];
    if (!isFiniteNumber(object.zIndex)) {
      const invalid: OperationResult<string | null> = {
        code: 'INVALID_ARGUMENT',
        message: 'Placed object zIndex must be finite.'
      };
      return invalid;
    }

    let catalog: CatalogItem | null = null;
    for (let j = 0; j < catalogs.length; j++) {
      if (catalogs[j].id === object.catalogId) {
        catalog = catalogs[j];
        break;
      }
    }
    if (catalog === null) {
      const invalid: OperationResult<string | null> = {
        code: 'INVALID_ARGUMENT',
        message: 'Placed object references an unknown catalog id.'
      };
      return invalid;
    }

    const footprint: OperationResult<Rect> = getFootprintRect(object, catalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      const invalid: OperationResult<string | null> = {
        code: footprint.code,
        message: footprint.message
      };
      return invalid;
    }
    if (pointInRect(footprint.data, point)) {
      if (hitId === null || object.zIndex >= hitZIndex) {
        hitId = object.id;
        hitZIndex = object.zIndex;
      }
    }
  }

  const result: OperationResult<string | null> = {
    code: 'OK',
    message: hitId === null ? 'No object hit.' : 'Object hit.',
    data: hitId
  };
  return result;
}

/** Short alias for the public hit-test function. */
export function hitTest(objects: PlacedObject[], catalogs: CatalogItem[],
  point: Point): OperationResult<string | null> {
  return hitTestObjects(objects, catalogs, point);
}

/** Short alias for positive-area overlap testing. */
export function overlaps(a: Rect, b: Rect): boolean {
  return overlapsPositive(a, b);
}
