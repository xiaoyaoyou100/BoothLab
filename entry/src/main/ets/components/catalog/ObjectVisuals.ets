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
  const extent: number = Math.min(width, height);
  // 线宽受短边约束；细节全部落在外轮廓内侧，极小投影也不溢出。
  const lineWidth: number = Math.min(extent * 0.2,
    Math.max(0.5, Math.min(3, extent * 0.035)));
  const inset: number = lineWidth * 0.5;
  const edge: number = lineWidth;
  const left: number = x + edge;
  const top: number = y + edge;
  const bottom: number = y + height - edge;
  const innerWidth: number = width - edge * 2;
  const innerHeight: number = height - edge * 2;

  // reception 自绘内缩底框；dispatch 提前返回，不再调用 drawBase。
  // 正交俯视：只表达接待台台面，不画柜门、桌腿、文字或透视。
  context.fillStyle = style.fillColor;
  context.fillRect(x, y, width, height);
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.strokeRect(x + inset, y + inset,
    width - inset * 2, height - inset * 2);

  // +y 为访客服务边界：沿内缩底边的服务台面带。
  const frontDepth: number = Math.min(innerHeight * 0.20, extent * 0.22);
  fillRect(context, left, bottom - frontDepth, innerWidth, frontDepth,
    style.detailColor);

  // 低 LOD：仅内缩轮廓 + +y 服务边，保留前后关系。
  if (extent < 18) {
    return;
  }

  // 中 LOD：U 形台面内轮廓；-y 中央留空，表示工作人员内侧开放方向。
  const armWidth: number = Math.min(innerWidth * 0.16, extent * 0.18);
  const uLeft: number = left + armWidth;
  const uRight: number = left + innerWidth - armWidth;
  const uFront: number = bottom - frontDepth;
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.beginPath();
  context.moveTo(uLeft, top);
  context.lineTo(uLeft, uFront);
  context.lineTo(uRight, uFront);
  context.lineTo(uRight, top);
  context.stroke();

  // 18..40 到此为止；>40 才增加少量台面工作细节。
  if (extent <= 40) {
    return;
  }

  // 高 LOD：两侧台面内缘细线，强调工作台面；仍无柜门/桌腿/文字。
  const rimInset: number = Math.min(lineWidth, armWidth * 0.35);
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  drawLine(context, uLeft - rimInset, top, uLeft - rimInset, uFront);
  drawLine(context, uRight + rimInset, top, uRight + rimInset, uFront);
}

function drawDisplayTable(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const extent: number = Math.min(width, height);
  // 与 chair/storage/sign 一致：线宽受短边约束，极小投影也不溢出 footprint。
  const lineWidth: number = Math.min(extent * 0.5,
    Math.max(0.5, Math.min(3, extent * 0.035)));
  const inset: number = lineWidth * 0.5;
  const innerX: number = x + inset;
  const innerY: number = y + inset;
  const innerWidth: number = width - inset * 2;
  const innerHeight: number = height - inset * 2;

  // display_table 自绘底框；dispatch 在本类型提前返回，不再调用 drawBase。
  // 正交俯视：只画台面，不画桌腿、透视或文字。
  context.fillStyle = style.fillColor;
  context.fillRect(x, y, width, height);
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.strokeRect(innerX, innerY, innerWidth, innerHeight);

  // 低 LOD：仅 footprint 内的台面与外框。
  if (extent < 18) {
    return;
  }

  // 中 LOD：内缩一圈描边作为边缘收口；rim 让开线宽，且不超过短边 1/4。
  const rim: number = Math.min(
    Math.max(lineWidth, Math.min(innerWidth, innerHeight) * 0.08),
    innerWidth * 0.25, innerHeight * 0.25);
  const topX: number = innerX + rim;
  const topY: number = innerY + rim;
  const topWidth: number = innerWidth - rim * 2;
  const topHeight: number = innerHeight - rim * 2;
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.strokeRect(topX, topY, topWidth, topHeight);

  // 中 LOD：沿长边两刀分三段；分隔线线宽减半并改用低对比浅灰绿，
  // 让台面轮廓与 rim 保持主导，不与中央标签争夺视觉权重。
  const alongWidth: boolean = width >= height;
  const dividerWidth: number = Math.max(0.5, lineWidth * 0.5);
  context.strokeStyle = '#BDCFC5';
  context.lineWidth = dividerWidth;
  if (alongWidth) {
    drawLine(context, topX + topWidth / 3, topY,
      topX + topWidth / 3, topY + topHeight);
    drawLine(context, topX + topWidth * 2 / 3, topY,
      topX + topWidth * 2 / 3, topY + topHeight);
  } else {
    drawLine(context, topX, topY + topHeight / 3,
      topX + topWidth, topY + topHeight / 3);
    drawLine(context, topX, topY + topHeight * 2 / 3,
      topX + topWidth, topY + topHeight * 2 / 3);
  }

  // 18..40 到此为止；>40 才增加少量低对比展品定位点。
  if (extent <= 40) {
    return;
  }

  // 高 LOD：每段仍保留一个定位点，区别于 plinth 的中央单展品；
  // 圆点显著缩小、改用低对比灰绿，并向 -y 偏移以避开中央标签。
  const bayWidth: number = alongWidth ? topWidth / 3 : topWidth;
  const bayHeight: number = alongWidth ? topHeight : topHeight / 3;
  const itemRadius: number = Math.min(bayWidth, bayHeight) * 0.06;
  if (!(itemRadius > 0)) {
    return;
  }
  const itemOffset: number = 0.30;
  for (let i: number = 0; i < 3; i++) {
    const itemX: number = alongWidth
      ? topX + bayWidth * (i + 0.5)
      : topX + topWidth * 0.5;
    const itemY: number = alongWidth
      ? topY + topHeight * itemOffset
      : topY + bayHeight * (i + itemOffset);
    fillCircle(context, itemX, itemY, itemRadius, '#A7BBB2');
  }
}

function drawShelf(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const shortSide: number = Math.min(width, height);
  const left: number = x + width * 0.045;
  const back: number = y + height * 0.075;
  const railWidth: number = width * 0.065;
  const right: number = x + width * 0.955 - railWidth;
  const ledgeX: number = left + railWidth;
  const ledgeY: number = y + height * 0.195;
  const ledgeWidth: number = right - ledgeX;

  fillRect(context, left, back, width * 0.91, height * 0.12, style.strokeColor);
  fillRect(context, left, ledgeY, railWidth, height * 0.72, '#4E8074');
  fillRect(context, right, ledgeY, railWidth, height * 0.72, '#4E8074');
  fillRect(context, ledgeX, ledgeY, ledgeWidth, height * 0.47, '#D9E7DF');

  // Two flat samples sit on the ledge behind the open visitor edge (+y).
  const leftSample: number = x + width * 0.19;
  const rightSample: number = x + width * 0.59;
  const leftSampleWidth: number = width * 0.24;
  const rightSampleWidth: number = width * 0.20;
  fillRect(context, leftSample, y + height * 0.315, leftSampleWidth, height * 0.245, '#8CB3A6');
  fillRect(context, rightSample, y + height * 0.25, rightSampleWidth, height * 0.28, '#DBB184');

  if (shortSide >= 18) {
    // Short retaining lips belong to the two individual sample holders.
    fillRect(context, leftSample, y + height * 0.56, leftSampleWidth, height * 0.06, '#86A99D');
    fillRect(context, rightSample, y + height * 0.53, rightSampleWidth, height * 0.06, '#86A99D');
  }
  if (shortSide > 40) {
    const jointOffset: number = railWidth * 0.24;
    const jointWidth: number = railWidth * 0.52;
    const jointY: number = y + height * 0.79;
    fillRect(context, left + jointOffset, jointY, jointWidth, height * 0.065, '#9BBAAE');
    fillRect(context, right + jointOffset, jointY, jointWidth, height * 0.065, '#9BBAAE');
  }
}

function drawInteractiveScreen(context: CanvasRenderingContext2D,
  x: number, y: number, width: number, height: number): void {
  const shortSide: number = Math.min(width, height);
  const baseLeft: number = x + width * 0.20;
  const baseRight: number = x + width * 0.80;
  const baseBack: number = y + height * 0.06;
  const baseFront: number = y + height * 0.82;
  const corner: number = shortSide * 0.12;

  context.fillStyle = '#B3CBCB';
  context.beginPath();
  context.moveTo(baseLeft + corner, baseBack);
  context.lineTo(baseRight - corner, baseBack);
  context.lineTo(baseRight, baseBack + corner);
  context.lineTo(baseRight, baseFront - corner);
  context.lineTo(baseRight - corner, baseFront);
  context.lineTo(baseLeft + corner, baseFront);
  context.lineTo(baseLeft, baseFront - corner);
  context.lineTo(baseLeft, baseBack + corner);
  context.closePath();
  context.fill();

  // A rear housing supports a glass deck that projects toward the visitor (+y).
  fillRect(context, x + width * 0.055, y + height * 0.26, width * 0.89, height * 0.33, '#648487');
  fillRect(context, x + width * 0.16, y + height * 0.32, width * 0.68, height * 0.60, '#6F9691');
  // The light glass crosses the object centre, where the editor draws its label.
  fillRect(context, x + width * 0.20, y + height * 0.37, width * 0.60, height * 0.49, '#D9EDEA');

  if (shortSide >= 18) {
    fillRect(context, x + width * 0.20, y + height * 0.79, width * 0.60, height * 0.07, '#A8CFC6');
  }
  if (shortSide > 40) {
    fillRect(context, x + width * 0.38, y + height * 0.145, width * 0.24, height * 0.065, '#8AA9AA');
  }
}

function drawChair(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const extent: number = Math.min(width, height);
  const lineWidth: number = Math.min(extent * 0.5,
    Math.max(0.5, Math.min(3, extent * 0.035)));
  const inset: number = lineWidth * 0.5;

  // Chair owns its base: fill the full footprint, then stroke half a line
  // width inside so the entire outline remains within the footprint.
  context.fillStyle = style.fillColor;
  context.fillRect(x, y, width, height);
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.strokeRect(x + inset, y + inset,
    width - inset * 2, height - inset * 2);

  // rot 0: backrest at -y, seat faces +y. No rotation here.
  const seatSize: number = extent * 0.52;
  const seatX: number = x + (width - seatSize) * 0.5;
  const seatY: number = y + (height - seatSize) * 0.5 + extent * 0.08;

  if (extent < 18) {
    // Low LOD: square seat + backrest bar only.
    fillRect(context, seatX, seatY, seatSize, seatSize, style.detailColor);
    fillRect(context, seatX, y + inset + extent * 0.04,
      seatSize, extent * 0.12, style.detailColor);
    return;
  }

  const centerX: number = seatX + seatSize * 0.5;
  const centerY: number = seatY + seatSize * 0.5;
  const backRadius: number = seatSize * 0.72;

  // Medium/High: square seat outline + backrest arc.
  context.strokeStyle = style.detailColor;
  context.lineWidth = lineWidth;
  context.strokeRect(seatX, seatY, seatSize, seatSize);
  context.beginPath();
  context.arc(centerX, centerY, backRadius,
    Math.PI * 1.12, Math.PI * 1.88);
  context.stroke();

  if (extent > 40) {
    // High LOD: two simple armrests joined to the arc ends.
    const armOffsetX: number = backRadius * Math.cos(Math.PI * 0.12);
    const armTopY: number = centerY - backRadius * Math.sin(Math.PI * 0.12);
    const armBottomY: number = seatY + seatSize * 0.86;
    drawLine(context, centerX - armOffsetX, armTopY,
      centerX - armOffsetX, armBottomY);
    drawLine(context, centerX + armOffsetX, armTopY,
      centerX + armOffsetX, armBottomY);
  }
}

function drawStorage(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const extent: number = Math.min(width, height);
  const outlineWidth: number = Math.min(extent * 0.12,
    Math.max(0.5, Math.min(3, extent * 0.035)));
  const inset: number = outlineWidth * 0.5;

  // Continuous cabinet top. Keep the perimeter stroke inside the footprint.
  fillRect(context, x, y, width, height, style.fillColor);
  context.strokeStyle = style.strokeColor;
  context.lineWidth = outlineWidth;
  context.strokeRect(x + inset, y + inset, width - outlineWidth, height - outlineWidth);

  // A single closed lid leaves more room at its hinged edge. The filled
  // silhouette and attached hinges remain visible in the thumbnail.
  const lidX: number = x + width * 0.12;
  const lidY: number = y + height * 0.28;
  const lidWidth: number = width * 0.76;
  const lidHeight: number = height * 0.56;
  fillRect(context, lidX, lidY, lidWidth, lidHeight, '#C9D8D2');

  if (extent >= 18) {
    // A fine seam separates the lid from the top at canvas and catalog scale.
    context.strokeStyle = '#9DB4AA';
    context.lineWidth = outlineWidth * 0.58;
    context.strokeRect(lidX, lidY, lidWidth, lidHeight);
  }

  const hingeWidth: number = lidWidth * 0.14;
  const hingeHeight: number = height * 0.10;
  const hingeY: number = lidY - hingeHeight * 0.5;
  fillRect(context, lidX + lidWidth * 0.20, hingeY, hingeWidth, hingeHeight, '#79968B');
  fillRect(context, lidX + lidWidth * 0.66, hingeY, hingeWidth, hingeHeight, '#79968B');

  if (extent > 40) {
    // Muted highlight just inside the free edge of the lid.
    const highlightHeight: number = Math.min(1.1, outlineWidth * 0.38);
    fillRect(context, lidX + lidWidth * 0.20, lidY + lidHeight * 0.88,
      lidWidth * 0.60, highlightHeight, '#E4EEE8');
  }
}

function drawSign(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const extent: number = Math.min(width, height);

  // All proportions stay positive for extent 0.1 and keep every part,
  // including its fill, strictly inside the footprint. No strokes are used.
  const boardWidth: number = width * 0.80;
  const boardThickness: number = height * 0.14;
  const boardX: number = x + (width - boardWidth) * 0.5;
  const boardY: number = y + height * 0.10;

  const postWidth: number = width * 0.10;
  const postX: number = x + (width - postWidth) * 0.5;
  const postTop: number = boardY + boardThickness;

  const baseWidth: number = width * 0.42;
  const baseHeight: number = height * 0.20;
  const baseX: number = x + (width - baseWidth) * 0.5;
  const baseY: number = y + height * 0.72;
  const postHeight: number = baseY - postTop;

  // Neutral footprint fill only; deliberately no enclosing outline.
  fillRect(context, x, y, width, height, style.fillColor);

  // Back (-y): wide, thin board top projection.
  fillRect(context, boardX, boardY, boardWidth, boardThickness,
    style.detailColor);

  // Centre: narrow post connecting board to base.
  fillRect(context, postX, postTop, postWidth, postHeight, '#6C8783');

  // Front (+y): compact stable base, visibly separate from the post.
  fillRect(context, baseX, baseY, baseWidth, baseHeight, '#DDE5E0');

  // Low LOD: board/post/base silhouette is sufficient.
  if (extent < 18) {
    return;
  }

  // Medium LOD (18..40): details sized to remain visible at a 22.11 vp
  // short edge. Board face strip first, then base front edge.
  const boardFaceHeight: number = Math.min(boardThickness * 0.20,
    Math.max(0.5, boardThickness * 0.16));
  fillRect(context, boardX + boardWidth * 0.08,
    boardY + boardThickness * 0.58,
    boardWidth * 0.84, boardFaceHeight, '#F8D7AF');

  const baseSeamHeight: number = Math.min(baseHeight * 0.22,
    Math.max(0.5, baseHeight * 0.12));
  fillRect(context, baseX + baseWidth * 0.10,
    baseY + baseHeight * 0.70,
    baseWidth * 0.80, baseSeamHeight, '#A9BCB6');

  if (extent <= 40) {
    return;
  }

  // High LOD (>40): only two subtle connection details, no dots or frames.
  const collarHeight: number = Math.min(boardThickness * 0.18,
    Math.max(0.5, boardThickness * 0.12));
  const collarWidth: number = postWidth * 1.80;
  fillRect(context, postX + (postWidth - collarWidth) * 0.5,
    postTop, collarWidth, collarHeight, '#6C8783');

  const postHighlightWidth: number = Math.max(0.5, postWidth * 0.18);
  fillRect(context, postX + (postWidth - postHighlightWidth) * 0.5,
    postTop + postHeight * 0.10,
    postHighlightWidth, postHeight * 0.80, FILL_PAGE);
}

function fillPlantLeaf(context: CanvasRenderingContext2D,
  originX: number, originY: number, angle: number,
  length: number, halfWidth: number, color: string): void {
  if (!(length > 0) || !(halfWidth > 0)) {
    return;
  }
  const cos: number = Math.cos(angle);
  const sin: number = Math.sin(angle);
  const tipX: number = originX + cos * length;
  const tipY: number = originY + sin * length;
  const bellyX: number = originX + cos * length * 0.32;
  const bellyY: number = originY + sin * length * 0.32;
  const sideX: number = -sin * halfWidth;
  const sideY: number = cos * halfWidth;
  context.fillStyle = color;
  context.beginPath();
  context.moveTo(originX, originY);
  context.quadraticCurveTo(bellyX + sideX, bellyY + sideY, tipX, tipY);
  context.quadraticCurveTo(bellyX - sideX, bellyY - sideY, originX, originY);
  context.closePath();
  context.fill();
}

function drawPlant(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const extent: number = Math.min(width, height);
  const centerX: number = x + width * 0.5;
  const centerY: number = y + height * 0.5;
  const potY: number = centerY + extent * 0.04;

  fillRect(context, x, y, width, height, style.fillColor);
  fillCircle(context, centerX, potY, extent * 0.31, '#D6B99B');
  fillCircle(context, centerX, potY, extent * 0.245, '#AA8E71');
  if (extent >= 18) {
    context.strokeStyle = '#8E785F';
    context.lineWidth = Math.min(extent * 0.02, 1.4);
    strokeCircle(context, centerX, potY, extent * 0.31);
  }

  // 错开叶柄位置，保留左下方露出的土面。
  fillPlantLeaf(context, centerX - extent * 0.065, centerY + extent * 0.035,
    -2.50, extent * 0.35, extent * 0.145, '#55835E');
  fillPlantLeaf(context, centerX + extent * 0.045, centerY + extent * 0.015,
    -1.22, extent * 0.415, extent * 0.165, '#316A51');
  fillPlantLeaf(context, centerX - extent * 0.015, centerY + extent * 0.09,
    0.44, extent * 0.45, extent * 0.20, '#67986D');

  if (extent > 40) {
    context.strokeStyle = '#86AD83';
    context.lineWidth = Math.min(extent * 0.012, 1.25);
    drawLine(context, centerX + extent * 0.073, centerY - extent * 0.06,
      centerX + extent * 0.15, centerY - extent * 0.27);
    context.strokeStyle = '#99B895';
    drawLine(context, centerX + extent * 0.06, centerY + extent * 0.127,
      centerX + extent * 0.29, centerY + extent * 0.233);
  }
}

function drawPlinth(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const extent: number = Math.min(width, height);
  const lineWidth: number = Math.min(extent * 0.18,
    Math.max(0.5, Math.min(3, extent * 0.035)));
  const inset: number = lineWidth * 0.5;
  const centerX: number = x + width * 0.5;
  const centerY: number = y + height * 0.5;
  const exhibitY: number = centerY - extent * 0.14;

  fillRect(context, x, y, width, height, style.fillColor);
  if (extent >= 18) {
    const rim: number = extent * 0.085;
    fillRect(context, x + rim, y + rim, width - rim * 2, height - rim * 2,
      FILL_WHITE);
  }
  context.strokeStyle = style.strokeColor;
  context.lineWidth = lineWidth;
  context.strokeRect(x + inset, y + inset, width - lineWidth, height - lineWidth);

  // 浅色托座与单件展品在低档同样保留，中央标签区域留浅底。
  fillRect(context, centerX - extent * 0.24, exhibitY - extent * 0.17,
    extent * 0.48, extent * 0.34, '#DFE7E1');
  context.fillStyle = '#C99660';
  context.beginPath();
  context.moveTo(centerX - extent * 0.145, exhibitY - extent * 0.027);
  context.lineTo(centerX - extent * 0.065, exhibitY - extent * 0.115);
  context.lineTo(centerX + extent * 0.075, exhibitY - extent * 0.103);
  context.lineTo(centerX + extent * 0.151, exhibitY - extent * 0.016);
  context.lineTo(centerX + extent * 0.094, exhibitY + extent * 0.095);
  context.lineTo(centerX - extent * 0.103, exhibitY + extent * 0.091);
  context.closePath();
  context.fill();

  if (extent > 40) {
    context.strokeStyle = '#F0D2AA';
    context.lineWidth = Math.min(extent * 0.015, 1.3);
    drawLine(context, centerX - extent * 0.062, exhibitY - extent * 0.062,
      centerX + extent * 0.061, exhibitY - extent * 0.053);
  }
}

function drawRollup(context: CanvasRenderingContext2D, style: ObjectVisualStyle,
  x: number, y: number, width: number, height: number): void {
  const extent: number = Math.min(width, height);
  const detailed: boolean = extent >= 18;

  // 中性 footprint 底色，仅填充、不描外框，避免“通用矩形框”观感。
  fillRect(context, x, y, width, height, style.fillColor);

  // 长横向卷轴底盒，靠近 +y；所有比例均为正数，微小 extent 下也成立。
  const cassetteWidth: number = width * 0.86;
  const cassetteHeight: number = height * 0.22;
  const cassetteX: number = x + (width - cassetteWidth) * 0.5;
  const cassetteY: number = y + height * 0.70;
  const cassetteEdge: number = Math.min(cassetteHeight * 0.16,
    cassetteWidth * 0.012);
  const cassetteInnerWidth: number = cassetteWidth - cassetteEdge * 2;
  const cassetteInnerHeight: number = cassetteHeight - cassetteEdge * 2;

  // -y 方向仅保留很薄的海报上缘投影，不画面板正面。
  const posterWidth: number = width * 0.78;
  const posterThickness: number = height * 0.07;
  const posterX: number = x + (width - posterWidth) * 0.5;
  const posterY: number = y + height * 0.18;

  // 轻量中央连接件：窄条连接海报上缘与卷轴底盒。
  const connectionWidth: number = width * 0.04;
  const connectionX: number = x + (width - connectionWidth) * 0.5;
  const connectionTop: number = posterY + posterThickness;
  const connectionHeight: number = cassetteY - connectionTop;

  // 两只小型稳定脚，位于卷轴前缘（+y），整体留在 footprint 内。
  const footWidth: number = width * 0.06;
  const footHeight: number = height * 0.06;
  const footY: number = cassetteY + cassetteHeight;
  const footLeftX: number = cassetteX + cassetteWidth * 0.06;
  const footRightX: number = cassetteX + cassetteWidth * 0.94 - footWidth;

  fillRect(context, posterX, posterY, posterWidth, posterThickness, '#247C72');
  if (connectionHeight > 0) {
    fillRect(context, connectionX, connectionTop, connectionWidth,
      connectionHeight, '#DDE5E0');
  }

  // 底盒本体：细绿边 + 浅灰绿面；不用描边，因此永不溢出。
  fillRect(context, cassetteX, cassetteY, cassetteWidth, cassetteHeight,
    '#247C72');
  fillRect(context, cassetteX + cassetteEdge, cassetteY + cassetteEdge,
    cassetteInnerWidth, cassetteInnerHeight, '#DDE5E0');

  fillRect(context, footLeftX, footY, footWidth, footHeight, '#247C72');
  fillRect(context, footRightX, footY, footWidth, footHeight, '#247C72');

  // 低 LOD：卷轴底盒 + 海报上缘 + 中央连接 + 稳定脚已足够识别。
  if (!detailed) {
    return;
  }

  // 中 LOD：底盒上的回卷槽 + 中央连接座，明确“可回卷”结构。
  const slotWidth: number = cassetteInnerWidth * 0.88;
  const slotHeight: number = cassetteInnerHeight * 0.14;
  const slotX: number = cassetteX + cassetteEdge +
    (cassetteInnerWidth - slotWidth) * 0.5;
  const slotY: number = cassetteY + cassetteEdge +
    cassetteInnerHeight * 0.32;
  fillRect(context, slotX, slotY, slotWidth, slotHeight, '#F7F8F4');

  const collarWidth: number = connectionWidth * 2.0;
  const collarHeight: number = cassetteHeight * 0.16;
  const collarX: number = x + (width - collarWidth) * 0.5;
  fillRect(context, collarX, cassetteY, collarWidth, collarHeight, '#247C72');

  // 18..40 到此为止。
  if (extent <= 40) {
    return;
  }

  // 高 LOD：仅补两端低对比端帽和一处小连接点，不再增加结构线。
  const capWidth: number = cassetteWidth * 0.025;
  const capHeight: number = cassetteInnerHeight * 0.72;
  const capY: number = cassetteY + cassetteEdge +
    (cassetteInnerHeight - capHeight) * 0.5;
  fillRect(context, cassetteX + cassetteWidth * 0.08, capY,
    capWidth, capHeight, '#F7F8F4');
  fillRect(context, cassetteX + cassetteWidth * 0.92 - capWidth, capY,
    capWidth, capHeight, '#F7F8F4');

  const jointRadius: number = Math.min(connectionWidth * 0.45,
    posterThickness * 0.55, cassetteHeight * 0.10);
  fillCircle(context, x + width * 0.5, connectionTop, jointRadius, '#247C72');
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
  if (style.shape === 'chair') {
    drawChair(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'storage') {
    drawStorage(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'sign') {
    drawSign(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'rollup') {
    drawRollup(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'plant') {
    drawPlant(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'plinth') {
    drawPlinth(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'display_table') {
    drawDisplayTable(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'reception') {
    drawReception(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'shelf') {
    drawShelf(context, style, x, y, width, height);
    return;
  }
  if (style.shape === 'interactive_screen') {
    drawInteractiveScreen(context, x, y, width, height);
    return;
  }
  drawBase(context, style, x, y, width, height);
  drawGeneric(context, style, x, y, width, height);
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
