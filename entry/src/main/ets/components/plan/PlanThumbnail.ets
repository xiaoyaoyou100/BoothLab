/**
 * PlanThumbnail (M2-B UI).
 *
 * Draws the real committed object footprints of a BoothPlan on a Canvas using
 * the actual template dimensions (standard/corner are 600x400 cm). It never
 * uses a static placeholder image and it never invents a box for an object
 * whose catalog id is unknown: unknown objects are simply not drawn.
 *
 * The component is presentation-only: it receives a plan snapshot from its
 * parent and touches no repository or storage.
 */

import {
  BoothPlan,
  BoothTemplate,
  PlacedObject,
  Point,
  Rect,
  Viewport
} from '../../model/BoothModels';
import { getTemplateById } from '../../catalog/BoothTemplates';
import { getCatalogItemById } from '../../catalog/ObjectCatalogData';
import {
  createViewport,
  getFootprintRect,
  worldToScreen
} from '../../engine/GeometryEngine';

const COLOR_THUMB_BG: string = '#FFFEF9';
const COLOR_BOOTH: string = '#FFFFFF';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_OBJECT_FILL: string = '#E8F2EF';
const THUMB_PADDING_VP: number = 8;

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
    return '展位方案预览：' + this.plan.name + '，' + this.plan.objects.length + ' 件物件。';
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

    if (this.plan === null || typeof this.plan !== 'object') {
      this.drawCenteredMessage('方案数据无效');
      return;
    }
    if (!Array.isArray(this.plan.objects)) {
      this.drawCenteredMessage('方案物件数据无效');
      return;
    }
    const template: BoothTemplate | undefined = getTemplateById(this.plan.templateId);
    if (template === undefined) {
      this.drawCenteredMessage('未知展位模板');
      return;
    }

    const viewportResult = createViewport(this.canvasWidthVp, this.canvasHeightVp,
      template.widthCm, template.heightCm, THUMB_PADDING_VP);
    if (viewportResult.code !== 'OK' || viewportResult.data === undefined) {
      this.drawCenteredMessage('预览尺寸无效');
      return;
    }
    this.viewport = viewportResult.data;

    this.drawBooth(template);
    this.drawReservedAreas(template);
    this.drawObjects();
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
    this.context.strokeRect(topLeft.x, topLeft.y, width, height);
  }

  private drawReservedAreas(template: BoothTemplate): void {
    const dashed: number[] = [4, 3];
    this.context.setLineDash(dashed);
    this.context.strokeStyle = COLOR_ACCENT;
    this.context.lineWidth = 1;
    for (let i = 0; i < template.reservedAreas.length; i++) {
      const screen: Rect | null = this.worldRectToScreen(template.reservedAreas[i]);
      if (screen !== null) {
        this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
      }
    }
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
  }

  private drawObjects(): void {
    const sorted: PlacedObject[] = [];
    for (let i = 0; i < this.plan.objects.length; i++) {
      sorted.push(this.plan.objects[i]);
    }
    sorted.sort((a: PlacedObject, b: PlacedObject): number => a.zIndex - b.zIndex);

    for (let i = 0; i < sorted.length; i++) {
      const object: PlacedObject = sorted[i];
      if (object === null || typeof object !== 'object') {
        continue;
      }
      const catalog = getCatalogItemById(object.catalogId);
      if (catalog === undefined) {
        // No false placeholder for an unknown catalog item.
        continue;
      }
      const footprintResult = getFootprintRect(object, catalog);
      if (footprintResult.code !== 'OK' || footprintResult.data === undefined) {
        continue;
      }
      const screen: Rect | null = this.worldRectToScreen(footprintResult.data);
      if (screen === null) {
        continue;
      }
      this.context.fillStyle = COLOR_OBJECT_FILL;
      this.context.fillRect(screen.x, screen.y, screen.width, screen.height);
      this.context.strokeStyle = COLOR_PRIMARY;
      this.context.lineWidth = 1.2;
      this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
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
