/**
 * PlanThumbnail (M3-B02 UI).
 *
 * Draws a saved plan's real template geometry and committed object positions.
 * The template walls, open entrance sides and reserved areas come from the
 * supplied BoothTemplate; objects are drawn through the read-only B01
 * `drawObjectVisual` helper using their actual committed rotation and the
 * catalog's UNROTATED widthCm/heightCm scaled by the existing viewport.
 *
 * The component is presentation-only: it receives a plan snapshot from its
 * parent, never reads a repository or Preferences, never writes back to the
 * plan and never invents a size for an unknown catalog id.
 */

import {
  BoothPlan,
  BoothTemplate,
  CatalogItem,
  PlacedObject,
  Point,
  Rect,
  Rotation,
  Side,
  Viewport
} from '../../model/BoothModels';
import { getTemplateById } from '../../catalog/BoothTemplates';
import { getCatalogItemById } from '../../catalog/ObjectCatalogData';
import { createViewport, worldToScreen } from '../../engine/GeometryEngine';
import { drawObjectVisual } from '../catalog/ObjectVisuals';

const COLOR_THUMB_BG: string = '#FFFEF9';
const COLOR_BOOTH: string = '#FFFFFF';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_WALL: string = '#263B41';
const COLOR_RESERVED_FILL: string = '#FFF0DF';
const THUMB_PADDING_VP: number = 8;

/** One template boundary side expressed in world centimetres. */
export interface TemplateSideSegment {
  side: Side;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

/** Fresh presentation geometry derived from one real template. */
export interface TemplatePreviewGeometry {
  walls: TemplateSideSegment[];
  openSides: TemplateSideSegment[];
  reservedAreas: Rect[];
}

/** One catalog object resolved to Canvas-local vp, with unrotated extents. */
export interface ThumbnailObjectDraw {
  imageKey: string;
  centerX: number;
  centerY: number;
  width: number;
  height: number;
  rotation: Rotation;
}

function lengthToVp(value: Length): number {
  if (typeof value === 'number') {
    return Number.isFinite(value) && value > 0 ? value : 0;
  }
  if (typeof value === 'string') {
    const parsed: number = parseFloat(value);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }
  return 0;
}

function isFinitePositive(value: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function isUsableRect(rect: Rect): boolean {
  if (rect === null || rect === undefined || typeof rect !== 'object') {
    return false;
  }
  return Number.isFinite(rect.x) && Number.isFinite(rect.y) &&
    isFinitePositive(rect.width) && isFinitePositive(rect.height);
}

function cloneRect(rect: Rect): Rect {
  return {
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height
  };
}

function sideSegment(template: BoothTemplate, side: Side): TemplateSideSegment | null {
  const width: number = template.widthCm;
  const height: number = template.heightCm;
  if (side === 'left') {
    return { side: 'left', x1: 0, y1: 0, x2: 0, y2: height };
  }
  if (side === 'top') {
    return { side: 'top', x1: 0, y1: 0, x2: width, y2: 0 };
  }
  if (side === 'right') {
    return { side: 'right', x1: width, y1: 0, x2: width, y2: height };
  }
  if (side === 'bottom') {
    return { side: 'bottom', x1: 0, y1: height, x2: width, y2: height };
  }
  return null;
}

/**
 * True only when a runtime template has usable dimensions and side/area lists.
 * Unknown runtime values are rejected instead of causing an invented preview.
 */
export function isTemplatePreviewable(template: BoothTemplate): boolean {
  if (template === null || template === undefined || typeof template !== 'object') {
    return false;
  }
  if (!isFinitePositive(template.widthCm) || !isFinitePositive(template.heightCm)) {
    return false;
  }
  return Array.isArray(template.wallSides) && Array.isArray(template.openSides) &&
    Array.isArray(template.reservedAreas);
}

/**
 * Builds fresh wall/open-side/reserved-area geometry for a real template.
 * Unknown side values are skipped, invalid reserved rects are ignored, and the
 * source template is never mutated. Returns null for unusable templates.
 */
export function getTemplatePreviewGeometry(
  template: BoothTemplate): TemplatePreviewGeometry | null {
  if (!isTemplatePreviewable(template)) {
    return null;
  }
  const walls: TemplateSideSegment[] = [];
  for (let i = 0; i < template.wallSides.length; i++) {
    const segment: TemplateSideSegment | null =
      sideSegment(template, template.wallSides[i]);
    if (segment !== null) {
      walls.push(segment);
    }
  }
  const openSides: TemplateSideSegment[] = [];
  for (let i = 0; i < template.openSides.length; i++) {
    const segment: TemplateSideSegment | null =
      sideSegment(template, template.openSides[i]);
    if (segment !== null) {
      openSides.push(segment);
    }
  }
  const reservedAreas: Rect[] = [];
  for (let i = 0; i < template.reservedAreas.length; i++) {
    const rect: Rect = template.reservedAreas[i];
    if (isUsableRect(rect)) {
      reservedAreas.push(cloneRect(rect));
    }
  }
  return {
    walls: walls,
    openSides: openSides,
    reservedAreas: reservedAreas
  };
}

/**
 * Resolves one committed object to Canvas-local vp.
 *
 * The draw extents are always `viewport.scale * catalog.widthCm` and
 * `viewport.scale * catalog.heightCm` (UNROTATED). The committed rotation is
 * passed through unchanged exactly once; drawObjectVisual rotates around the
 * centre. An unknown catalog or invalid catalog dimensions produce null, so no
 * physical size is invented.
 */
export function resolveThumbnailObjectDraw(viewport: Viewport,
  object: PlacedObject, catalog: CatalogItem | undefined): ThumbnailObjectDraw | null {
  if (viewport === null || viewport === undefined || typeof viewport !== 'object') {
    return null;
  }
  if (object === null || object === undefined || typeof object !== 'object') {
    return null;
  }
  if (catalog === null || catalog === undefined || typeof catalog !== 'object') {
    return null;
  }
  if (!isFinitePositive(viewport.scale)) {
    return null;
  }
  if (!isFinitePositive(catalog.widthCm) || !isFinitePositive(catalog.heightCm)) {
    return null;
  }
  const worldCenter: Point = { x: object.centerX, y: object.centerY };
  const screenResult = worldToScreen(worldCenter, viewport);
  if (screenResult.code !== 'OK' || screenResult.data === undefined) {
    return null;
  }
  const width: number = viewport.scale * catalog.widthCm;
  const height: number = viewport.scale * catalog.heightCm;
  if (!isFinitePositive(width) || !isFinitePositive(height)) {
    return null;
  }
  return {
    imageKey: catalog.imageKey,
    centerX: screenResult.data.x,
    centerY: screenResult.data.y,
    width: width,
    height: height,
    rotation: object.rotation
  };
}

/**
 * Draws one placed object through B01 ObjectVisuals. Returns false when the
 * object cannot be resolved (unknown catalog or invalid geometry), in which
 * case the Canvas is untouched. Never mutates the object or catalog.
 */
export function drawThumbnailObject(context: CanvasRenderingContext2D,
  viewport: Viewport, object: PlacedObject,
  catalog: CatalogItem | undefined): boolean {
  if (context === null || context === undefined) {
    return false;
  }
  const draw: ThumbnailObjectDraw | null =
    resolveThumbnailObjectDraw(viewport, object, catalog);
  if (draw === null) {
    return false;
  }
  drawObjectVisual(context, draw.imageKey, draw.centerX, draw.centerY,
    draw.width, draw.height, draw.rotation);
  return true;
}

/**
 * Draws all usable committed objects in ascending zIndex. Unknown catalog ids
 * are skipped rather than drawn with an invented footprint. Returns the number
 * of objects actually drawn; the plan and its objects are not mutated.
 */
export function drawThumbnailObjects(context: CanvasRenderingContext2D,
  plan: BoothPlan, viewport: Viewport): number {
  if (context === null || context === undefined) {
    return 0;
  }
  if (plan === null || plan === undefined || typeof plan !== 'object' ||
    !Array.isArray(plan.objects)) {
    return 0;
  }
  const sorted: PlacedObject[] = [];
  for (let i = 0; i < plan.objects.length; i++) {
    const object: PlacedObject = plan.objects[i];
    if (object !== null && object !== undefined && typeof object === 'object') {
      sorted.push(object);
    }
  }
  sorted.sort((a: PlacedObject, b: PlacedObject): number => a.zIndex - b.zIndex);

  let drawn: number = 0;
  for (let i = 0; i < sorted.length; i++) {
    const object: PlacedObject = sorted[i];
    const catalog: CatalogItem | undefined = getCatalogItemById(object.catalogId);
    if (drawThumbnailObject(context, viewport, object, catalog)) {
      drawn++;
    }
  }
  return drawn;
}

@Component
export struct PlanThumbnail {
  @Prop @Watch('handlePlanChanged') plan: BoothPlan;

  private context: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasWidthVp: number = 0;
  private canvasHeightVp: number = 0;
  private canvasReady: boolean = false;
  private viewport: Viewport | null = null;

  private handlePlanChanged(): void {
    this.redraw();
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height(112)
      .backgroundColor(COLOR_THUMB_BG)
      .borderRadius(10)
      .accessibilityText(this.describePlan())
      .id('plan-thumbnail-' + this.plan.id)
      .onReady(() => {
        this.canvasReady = true;
        this.redraw();
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.canvasWidthVp = lengthToVp(newValue.width);
        this.canvasHeightVp = lengthToVp(newValue.height);
        this.redraw();
      })
  }

  private describePlan(): string {
    const template: BoothTemplate | undefined = getTemplateById(this.plan.templateId);
    const templateName: string = template === undefined ? '未知模板' : template.name;
    return '展位方案预览：' + this.plan.name + '，模板 ' + templateName + '，' +
      this.plan.objects.length + ' 件物件。';
  }

  private redraw(): void {
    if (!this.canvasReady || this.canvasWidthVp <= 0 || this.canvasHeightVp <= 0) {
      return;
    }
    this.context.clearRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    this.context.fillStyle = COLOR_THUMB_BG;
    this.context.fillRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    const noDash: number[] = [];
    this.context.setLineDash(noDash);

    if (this.plan === null || this.plan === undefined || typeof this.plan !== 'object') {
      this.drawCenteredMessage('方案数据无效');
      return;
    }
    if (!Array.isArray(this.plan.objects)) {
      this.drawCenteredMessage('方案物件数据无效');
      return;
    }
    const template: BoothTemplate | undefined = getTemplateById(this.plan.templateId);
    if (template === undefined || !isTemplatePreviewable(template)) {
      this.drawCenteredMessage('未知展位模板');
      return;
    }

    const viewportResult = createViewport(this.canvasWidthVp, this.canvasHeightVp,
      template.widthCm, template.heightCm, THUMB_PADDING_VP);
    if (viewportResult.code !== 'OK' || viewportResult.data === undefined) {
      this.drawCenteredMessage('预览尺寸无效');
      return;
    }
    const geometry: TemplatePreviewGeometry | null =
      getTemplatePreviewGeometry(template);
    if (geometry === null) {
      this.drawCenteredMessage('模板几何无效');
      return;
    }
    const viewport: Viewport = viewportResult.data;
    this.viewport = viewport;

    this.drawBooth(template);
    this.drawReservedAreas(geometry.reservedAreas);
    drawThumbnailObjects(this.context, this.plan, viewport);
    this.drawSides(geometry.walls, COLOR_WALL, 2.5);
    this.drawDashedSides(geometry.openSides, COLOR_PRIMARY, 2);
  }

  private drawBooth(template: BoothTemplate): void {
    const topLeft: Point | null = this.worldPointToScreen(0, 0);
    const bottomRight: Point | null =
      this.worldPointToScreen(template.widthCm, template.heightCm);
    if (topLeft === null || bottomRight === null) {
      return;
    }
    const width: number = bottomRight.x - topLeft.x;
    const height: number = bottomRight.y - topLeft.y;
    this.context.fillStyle = COLOR_BOOTH;
    this.context.fillRect(topLeft.x, topLeft.y, width, height);
    this.context.strokeStyle = COLOR_BORDER;
    this.context.lineWidth = 1;
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
    this.context.strokeRect(topLeft.x, topLeft.y, width, height);
  }

  private drawReservedAreas(areas: Rect[]): void {
    for (let i = 0; i < areas.length; i++) {
      const screen: Rect | null = this.worldRectToScreen(areas[i]);
      if (screen === null) {
        continue;
      }
      this.context.fillStyle = COLOR_RESERVED_FILL;
      this.context.fillRect(screen.x, screen.y, screen.width, screen.height);
      const dashed: number[] = [3, 2];
      this.context.setLineDash(dashed);
      this.context.strokeStyle = COLOR_ACCENT;
      this.context.lineWidth = 1;
      this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
    }
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
  }

  private drawSides(segments: TemplateSideSegment[], color: string,
    lineWidth: number): void {
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
    this.context.strokeStyle = color;
    this.context.lineWidth = lineWidth;
    this.strokeSegments(segments);
  }

  private drawDashedSides(segments: TemplateSideSegment[], color: string,
    lineWidth: number): void {
    const dashed: number[] = [4, 3];
    this.context.setLineDash(dashed);
    this.context.strokeStyle = color;
    this.context.lineWidth = lineWidth;
    this.strokeSegments(segments);
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
  }

  private strokeSegments(segments: TemplateSideSegment[]): void {
    for (let i = 0; i < segments.length; i++) {
      const segment: TemplateSideSegment = segments[i];
      const start: Point | null = this.worldPointToScreen(segment.x1, segment.y1);
      const end: Point | null = this.worldPointToScreen(segment.x2, segment.y2);
      if (start === null || end === null) {
        continue;
      }
      this.context.beginPath();
      this.context.moveTo(start.x, start.y);
      this.context.lineTo(end.x, end.y);
      this.context.stroke();
    }
  }

  private worldPointToScreen(x: number, y: number): Point | null {
    if (this.viewport === null) {
      return null;
    }
    const point: Point = { x: x, y: y };
    const result = worldToScreen(point, this.viewport);
    if (result.code !== 'OK' || result.data === undefined) {
      return null;
    }
    return result.data;
  }

  private worldRectToScreen(rect: Rect): Rect | null {
    const topLeft: Point | null = this.worldPointToScreen(rect.x, rect.y);
    const bottomRight: Point | null =
      this.worldPointToScreen(rect.x + rect.width, rect.y + rect.height);
    if (topLeft === null || bottomRight === null) {
      return null;
    }
    const screen: Rect = {
      x: topLeft.x,
      y: topLeft.y,
      width: bottomRight.x - topLeft.x,
      height: bottomRight.y - topLeft.y
    };
    return screen;
  }

  private drawCenteredMessage(message: string): void {
    this.context.font = '12px sans-serif';
    this.context.fillStyle = COLOR_TEXT;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillText(message, this.canvasWidthVp / 2, this.canvasHeightVp / 2);
  }
}
