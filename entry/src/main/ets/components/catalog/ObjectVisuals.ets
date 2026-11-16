/**
 * BoothLab M3-B01 procedural object visuals.
 *
 * This module is the single authoritative description of the top-view
 * appearance of catalog objects. It is deliberately independent of geometry,
 * selection, preview, persistence and hit testing: the rectangular footprint
 * and collision behaviour remain owned by Controller/GeometryEngine.
 *
 * All coordinates are Canvas-local vp. `width` and `height` are the UNROTATED
 * footprint in vp; rotation is clockwise and is applied around the supplied
 * centre. The helper never swaps the footprint for 90/270 degree rotations and
 * never converts cm. Canvas state is always saved and restored internally so
 * callers keep their own transform and style.
 *
 * There is no asynchronous bitmap dependency. Every stable image key has a
 * distinct procedural top-view detail; unknown keys fall back to a neutral
 * geometric placeholder.
 */

import { Rotation } from '../../model/BoothModels';

/** Stable visual description consumed by the editor, picker and thumbnails. */
export interface ObjectVisualStyle {
  imageKey: string;
  fillColor: string;
  strokeColor: string;
  detailColor: string;
  shape: string;
}

const GENERIC_KEY: string = 'generic';

/** Palette-derived tints shared by all views. */
const FILL_GREEN: string = '#E8F2EF';
const FILL_CREAM: string = '#FFF0DF';
const FILL_PAGE: string = '#F7F8F4';
const FILL_WHITE: string = '#FFFFFF';
const FILL_DARK: string = '#263B41';
const STROKE_PRIMARY: string = '#247C72';
const STROKE_DARK: string = '#263B41';
const DETAIL_ACCENT: string = '#FFB56B';
const DETAIL_PRIMARY: string = '#247C72';

/**
 * Returns a fresh style object for an image key. The returned object is never
 * shared: callers may keep or modify it without affecting later lookups.
 * Unknown, empty and non-string runtime values use the generic fallback.
 */
export function getObjectVisualStyle(imageKey: string): ObjectVisualStyle {
  const key: string = typeof imageKey === 'string' ? imageKey : '';
  if (key === 'reception') {
    return {
      imageKey: 'reception',
      fillColor: FILL_GREEN,
      strokeColor: STROKE_PRIMARY,
      detailColor: DETAIL_ACCENT,
      shape: 'reception'
    };
  }
  if (key === 'display_table') {
    return {
      imageKey: 'display_table',
      fillColor: FILL_CREAM,
      strokeColor: STROKE_PRIMARY,
      detailColor: STROKE_DARK,
      shape: 'display_table'
    };
  }
  if (key === 'shelf') {
    return {
      imageKey: 'shelf',
      fillColor: FILL_PAGE,
      strokeColor: STROKE_PRIMARY,
      detailColor: DETAIL_ACCENT,
      shape: 'shelf'
    };
  }
  if (key === 'interactive_screen') {
    return {
      imageKey: 'interactive_screen',
      fillColor: FILL_DARK,
      strokeColor: STROKE_PRIMARY,
      detailColor: DETAIL_ACCENT,
      shape: 'interactive_screen'
    };
  }
  if (key === 'chair') {
    return {
      imageKey: 'chair',
      fillColor: FILL_CREAM,
      strokeColor: STROKE_DARK,
      detailColor: DETAIL_PRIMARY,
      shape: 'chair'
    };
  }
  if (key === 'storage') {
    return {
      imageKey: 'storage',
      fillColor: FILL_GREEN,
      strokeColor: STROKE_DARK,
      detailColor: DETAIL_PRIMARY,
      shape: 'storage'
    };
  }
  if (key === 'sign') {
    return {
      imageKey: 'sign',
      fillColor: FILL_WHITE,
      strokeColor: STROKE_PRIMARY,
      detailColor: DETAIL_ACCENT,
      shape: 'sign'
    };
  }
  if (key === 'plant') {
    return {
      imageKey: 'plant',
      fillColor: FILL_GREEN,
      strokeColor: STROKE_PRIMARY,
      detailColor: STROKE_DARK,
      shape: 'plant'
    };
  }
  if (key === 'plinth') {
    return {
      imageKey: 'plinth',
      fillColor: FILL_PAGE,
      strokeColor: STROKE_DARK,
      detailColor: DETAIL_PRIMARY,
      shape: 'plinth'
    };
  }
  if (key === 'rollup') {
    return {
      imageKey: 'rollup',
      fillColor: FILL_CREAM,
      strokeColor: STROKE_PRIMARY,
      detailColor: STROKE_DARK,
      shape: 'rollup'
    };
  }
  return {
    imageKey: GENERIC_KEY,
    fillColor: FILL_PAGE,
    strokeColor: STROKE_DARK,
    detailColor: DETAIL_PRIMARY,
    shape: GENERIC_KEY
  };
}

function isFiniteNumber(value: number): boolean {
  return typeof value === 'number' && Number.isFinite(value);
}

function normaliseRotation(rotation: Rotation): number {
  if (rotation === 90) {
    return 90;
  }
  if (rotation === 180) {
    return 180;
  }
  if (rotation === 270) {
    return 270;
  }
  return 0;
}

function drawLine(context: CanvasRenderingContext2D,
  x1: number, y1: number, x2: number, y2: number): void {
  context.beginPath();
  context.moveTo(x1, y1);
  context.lineTo(x2, y2);
  context.stroke();
}

function fillCircle(context: CanvasRenderingContext2D,
  centerX: number, centerY: number, radius: number, color: string): void {
  if (!(radius > 0) || !isFiniteNumber(radius)) {
    return;
  }
  context.fillStyle = color;
  context.beginPath();
  context.arc(centerX, centerY, radius, 0, Math.PI * 2);
  context.fill();
}

function strokeCircle(context: CanvasRenderingContext2D,
  centerX: number, centerY: number, radius: number): void {
  if (!(radius > 0) || !isFiniteNumber(radius)) {
    return;
  }
  context.beginPath();
  context.arc(centerX, centerY, radius, 0, Math.PI * 2);
  context.stroke();
}

function fillRect(context: CanvasRenderingContext2D,
  x: number, y: number, width: number, height: number, color: string): void {
  if (!(width > 0) || !(height > 0) || !isFiniteNumber(width) || !isFiniteNumber(height)) {
    return;
  }
  context.fillStyle = color;
  context.fillRect(x, y, width, height);
}

function drawBase(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  context.fillStyle = style.fillColor;
  context.fillRect(x, y, width, height);
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.strokeRect(x, y, width, height);
}

function drawReception(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const counterHeight: number = Math.max(2, height * 0.16);
  fillRect(context, x + width * 0.1, y + height * 0.7,
    width * 0.8, counterHeight, style.detailColor);
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  for (let i = 0; i < 2; i++) {
    const deskX: number = x + width * (0.12 + i * 0.4);
    const deskY: number = y + height * 0.16;
    const deskWidth: number = width * 0.3;
    const deskHeight: number = height * 0.26;
    context.strokeRect(deskX, deskY, deskWidth, deskHeight);
    drawLine(context,
      deskX + deskWidth * 0.15, deskY + deskHeight * 0.62,
      deskX + deskWidth * 0.85, deskY + deskHeight * 0.62);
  }
}

function drawDisplayTable(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  context.strokeRect(x + width * 0.1, y + height * 0.14,
    width * 0.8, height * 0.72);
  const radius: number = Math.max(1.5, Math.min(width, height) * 0.09);
  fillCircle(context, x + width * 0.28, y + height * 0.5, radius, style.detailColor);
  fillCircle(context, x + width * 0.5, y + height * 0.5, radius, style.detailColor);
  fillCircle(context, x + width * 0.72, y + height * 0.5, radius, style.detailColor);
}

function drawShelf(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const shelfX: number = x + width * 0.1;
  const shelfY: number = y + height * 0.12;
  const shelfWidth: number = width * 0.8;
  const shelfHeight: number = height * 0.76;
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  context.strokeRect(shelfX, shelfY, shelfWidth, shelfHeight);
  for (let i = 1; i < 4; i++) {
    drawLine(context,
      shelfX + shelfWidth * (i / 4), shelfY,
      shelfX + shelfWidth * (i / 4), shelfY + shelfHeight);
  }
  for (let i = 0; i < 4; i++) {
    const bookColor: string = i % 2 === 0 ? style.detailColor : style.strokeColor;
    fillRect(context,
      shelfX + shelfWidth * (i / 4) + shelfWidth * 0.03,
      shelfY + shelfHeight * 0.22,
      shelfWidth * 0.17,
      shelfHeight * 0.56,
      bookColor);
  }
}

function drawInteractiveScreen(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const screenHeight: number = Math.max(2, height * 0.18);
  fillRect(context, x + width * 0.1, y + height * 0.18,
    width * 0.8, screenHeight, style.detailColor);
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  const radius: number = Math.max(2, Math.min(width, height) * 0.16);
  strokeCircle(context, x + width * 0.5, y + height * 0.5, radius);
  const footRadius: number = Math.max(1.5, Math.min(width, height) * 0.07);
  fillCircle(context, x + width * 0.22, y + height * 0.78, footRadius, style.detailColor);
  fillCircle(context, x + width * 0.78, y + height * 0.78, footRadius, style.detailColor);
}

function drawChair(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const backHeight: number = Math.max(2, height * 0.12);
  fillRect(context, x + width * 0.12, y + height * 0.1,
    width * 0.76, backHeight, style.detailColor);
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  const seatRadius: number = Math.max(2, Math.min(width, height) * 0.29);
  strokeCircle(context, x + width * 0.5, y + height * 0.58, seatRadius);
  drawLine(context, x + width * 0.08, y + height * 0.5,
    x + width * 0.22, y + height * 0.5);
  drawLine(context, x + width * 0.78, y + height * 0.5,
    x + width * 0.92, y + height * 0.5);
}

function drawStorage(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const storageX: number = x + width * 0.1;
  const storageY: number = y + height * 0.12;
  const storageWidth: number = width * 0.8;
  const storageHeight: number = height * 0.76;
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  context.strokeRect(storageX, storageY, storageWidth, storageHeight);
  drawLine(context, storageX + storageWidth * 0.5, storageY,
    storageX + storageWidth * 0.5, storageY + storageHeight);
  drawLine(context, storageX, storageY + storageHeight * 0.5,
    storageX + storageWidth, storageY + storageHeight * 0.5);
  const handleRadius: number = Math.max(1, Math.min(width, height) * 0.045);
  const offsetsX: number[] = [0.36, 0.64];
  const offsetsY: number[] = [0.36, 0.64];
  for (let i = 0; i < offsetsX.length; i++) {
    for (let j = 0; j < offsetsY.length; j++) {
      fillCircle(context,
        storageX + storageWidth * offsetsX[i],
        storageY + storageHeight * offsetsY[j],
        handleRadius, style.detailColor);
    }
  }
}

function drawSign(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const boardX: number = x + width * 0.12;
  const boardY: number = y + height * 0.12;
  const boardWidth: number = width * 0.76;
  const boardHeight: number = height * 0.5;
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  context.strokeRect(boardX, boardY, boardWidth, boardHeight);
  drawLine(context,
    boardX + boardWidth * 0.24, boardY + boardHeight * 0.5,
    boardX + boardWidth * 0.72, boardY + boardHeight * 0.5);
  drawLine(context,
    boardX + boardWidth * 0.54, boardY + boardHeight * 0.28,
    boardX + boardWidth * 0.72, boardY + boardHeight * 0.5);
  drawLine(context,
    boardX + boardWidth * 0.54, boardY + boardHeight * 0.72,
    boardX + boardWidth * 0.72, boardY + boardHeight * 0.5);
  const baseRadius: number = Math.max(1.5, Math.min(width, height) * 0.08);
  fillCircle(context, x + width * 0.5, y + height * 0.82,
    baseRadius, style.detailColor);
}

function drawPlant(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const centerX: number = x + width * 0.5;
  const centerY: number = y + height * 0.52;
  const extent: number = Math.min(width, height);
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  strokeCircle(context, centerX, centerY, Math.max(2, extent * 0.36));
  fillCircle(context, centerX, centerY, Math.max(1.5, extent * 0.1), style.detailColor);
  for (let i = 0; i < 4; i++) {
    const angle: number = Math.PI * 0.25 + i * Math.PI * 0.5;
    const leafX: number = centerX + Math.cos(angle) * extent * 0.22;
    const leafY: number = centerY + Math.sin(angle) * extent * 0.22;
    fillCircle(context, leafX, leafY, Math.max(1.5, extent * 0.09), style.detailColor);
  }
}

function drawPlinth(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const extent: number = Math.min(width, height);
  const inset: number = extent * 0.2;
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  context.strokeRect(x + inset, y + inset,
    width - inset * 2, height - inset * 2);
  const exhibitSize: number = Math.max(2, extent * 0.18);
  fillRect(context,
    x + width * 0.5 - exhibitSize * 0.5,
    y + height * 0.5 - exhibitSize * 0.5,
    exhibitSize, exhibitSize, style.detailColor);
  const tick: number = Math.max(2, extent * 0.08);
  const cornerInsetX: number = x + inset * 0.4;
  const cornerInsetY: number = y + inset * 0.4;
  drawLine(context, cornerInsetX, cornerInsetY, cornerInsetX + tick, cornerInsetY);
  drawLine(context, cornerInsetX, cornerInsetY, cornerInsetX, cornerInsetY + tick);
  drawLine(context, x + width - cornerInsetX, cornerInsetY,
    x + width - cornerInsetX - tick, cornerInsetY);
  drawLine(context, x + width - cornerInsetX, cornerInsetY,
    x + width - cornerInsetX, cornerInsetY + tick);
}

function drawRollup(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const extent: number = Math.min(width, height);
  const baseY: number = y + height * 0.72;
  const baseHeight: number = Math.max(2, height * 0.14);
  fillRect(context, x + width * 0.08, baseY,
    width * 0.84, baseHeight, style.detailColor);
  const footRadius: number = Math.max(1.5, extent * 0.07);
  fillCircle(context, x + width * 0.08, baseY + baseHeight * 0.5,
    footRadius, style.detailColor);
  fillCircle(context, x + width * 0.92, baseY + baseHeight * 0.5,
    footRadius, style.detailColor);
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  drawLine(context,
    x + width * 0.16, baseY,
    x + width * 0.84, y + height * 0.18);
  fillCircle(context, x + width * 0.84, y + height * 0.18,
    Math.max(1.5, extent * 0.07), style.detailColor);
}

function drawGeneric(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const lineWidth: number = Math.max(1, Math.min(3, Math.min(width, height) * 0.035));
  const dash: number[] = [4, 3];
  context.setLineDash(dash);
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.strokeRect(x + width * 0.08, y + height * 0.12,
    width * 0.84, height * 0.76);
  const noDash: number[] = [];
  context.setLineDash(noDash);
  drawLine(context, x + width * 0.2, y + height * 0.25,
    x + width * 0.8, y + height * 0.75);
  drawLine(context, x + width * 0.8, y + height * 0.25,
    x + width * 0.2, y + height * 0.75);
  fillCircle(context, x + width * 0.5, y + height * 0.5,
    Math.max(1.5, Math.min(width, height) * 0.08), style.detailColor);
}

function drawShape(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  drawBase(context, style, x, y, width, height);
  if (style.shape === 'reception') {
    drawReception(context, style, x, y, width, height);
  } else if (style.shape === 'display_table') {
    drawDisplayTable(context, style, x, y, width, height);
  } else if (style.shape === 'shelf') {
    drawShelf(context, style, x, y, width, height);
  } else if (style.shape === 'interactive_screen') {
    drawInteractiveScreen(context, style, x, y, width, height);
  } else if (style.shape === 'chair') {
    drawChair(context, style, x, y, width, height);
  } else if (style.shape === 'storage') {
    drawStorage(context, style, x, y, width, height);
  } else if (style.shape === 'sign') {
    drawSign(context, style, x, y, width, height);
  } else if (style.shape === 'plant') {
    drawPlant(context, style, x, y, width, height);
  } else if (style.shape === 'plinth') {
    drawPlinth(context, style, x, y, width, height);
  } else if (style.shape === 'rollup') {
    drawRollup(context, style, x, y, width, height);
  } else {
    drawGeneric(context, style, x, y, width, height);
  }
}

/**
 * Draws one object's top view at a Canvas-local vp centre.
 *
 * `width`/`height` are the unrotated footprint extents. The whole drawing is
 * translated to the centre, rotated clockwise, and then drawn centred on the
 * local origin. Invalid contexts, centres or extents are ignored without
 * throwing; invalid runtime rotations are treated as 0 degrees.
 */
export function drawObjectVisual(context: CanvasRenderingContext2D,
  imageKey: string, centerX: number, centerY: number,
  width: number, height: number, rotation: Rotation): void {
  if (context === null || context === undefined) {
    return;
  }
  if (!isFiniteNumber(centerX) || !isFiniteNumber(centerY)) {
    return;
  }
  if (!isFiniteNumber(width) || !isFiniteNumber(height) || !(width > 0) || !(height > 0)) {
    return;
  }

  const style: ObjectVisualStyle = getObjectVisualStyle(imageKey);
  const degrees: number = normaliseRotation(rotation);
  const radians: number = degrees * Math.PI / 180;
  context.save();
  try {
    context.translate(centerX, centerY);
    context.rotate(radians);
    drawShape(context, style, -width * 0.5, -height * 0.5, width, height);
  } finally {
    context.restore();
  }
}
