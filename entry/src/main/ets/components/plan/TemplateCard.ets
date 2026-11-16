/**
 * TemplateCard (M3-B02 UI).
 *
 * A compact, selectable booth-template card. Its Canvas renders the real
 * template dimensions plus the template's actual wall sides, open entrance
 * sides and reserved areas. It never invents a template, never mutates the
 * supplied BoothTemplate and never reads storage/repository state.
 *
 * The selected card uses a clear BoothLab primary border/tint; a disabled card
 * suppresses selection callbacks entirely.
 */

import { BoothTemplate, Point, Rect, Side } from '../../model/BoothModels';
import { createViewport, worldToScreen } from '../../engine/GeometryEngine';
import {
  getTemplatePreviewGeometry,
  isTemplatePreviewable,
  TemplatePreviewGeometry,
  TemplateSideSegment
} from './PlanThumbnail';

const COLOR_CARD: string = '#FFFFFF';
const COLOR_SELECTED: string = '#E8F2EF';
const COLOR_PAGE: string = '#FFFEF9';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_MUTED: string = '#6B7C80';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_WALL: string = '#263B41';
const COLOR_RESERVED_FILL: string = '#FFF0DF';
const PREVIEW_PADDING_VP: number = 7;

function isFinitePositive(value: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function meters(valueCm: number): string {
  const valueM: number = valueCm / 100;
  if (Number.isInteger(valueM)) {
    return valueM.toString();
  }
  return valueM.toFixed(1);
}

function sideLabel(side: Side): string {
  if (side === 'left') {
    return '左';
  }
  if (side === 'top') {
    return '上';
  }
  if (side === 'right') {
    return '右';
  }
  if (side === 'bottom') {
    return '下';
  }
  return '';
}

function joinSideLabels(sides: Side[]): string {
  const labels: string[] = [];
  for (let i = 0; i < sides.length; i++) {
    const label: string = sideLabel(sides[i]);
    if (label.length > 0) {
      labels.push(label);
    }
  }
  return labels.length === 0 ? '无' : labels.join('、');
}

/**
 * Formats the real template dimensions in both centimetres and metres.
 * Invalid runtime dimensions return an explicit unknown label.
 */
export function formatTemplateDimensions(template: BoothTemplate): string {
  if (template === null || template === undefined ||
    !isFinitePositive(template.widthCm) || !isFinitePositive(template.heightCm)) {
    return '尺寸未知';
  }
  return template.widthCm.toString() + ' × ' + template.heightCm.toString() +
    ' cm · ' + meters(template.widthCm) + ' × ' + meters(template.heightCm) + ' m';
}

/**
 * Summarises the actual wall/open sides. Unknown values are skipped and an
 * empty list is reported as 无 instead of inventing a side.
 */
export function formatTemplateSideSummary(template: BoothTemplate): string {
  if (!isTemplatePreviewable(template)) {
    return '边类型未知';
  }
  return '墙：' + joinSideLabels(template.wallSides) +
    ' · 开放：' + joinSideLabels(template.openSides);
}

@Component
export struct TemplateCard {
  @Prop @Watch('handleTemplateChanged') template: BoothTemplate;
  @Prop selected: boolean = false;
  @Prop disabled: boolean = false;
  onSelect: (templateId: string) => void = () => {};

  private context: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasWidthVp: number = 0;
  private canvasHeightVp: number = 0;
  private canvasReady: boolean = false;
  private viewportScale: number = 0;
  private viewportOffsetX: number = 0;
  private viewportOffsetY: number = 0;
  private hasViewport: boolean = false;

  private handleTemplateChanged(): void {
    this.redraw();
  }

  build() {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Canvas(this.context)
          .width('100%')
          .height(82)
          .backgroundColor(COLOR_PAGE)
          .borderRadius(8)
          .onReady(() => {
            this.canvasReady = true;
            this.redraw();
          })
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.canvasWidthVp = this.toVp(newValue.width);
            this.canvasHeightVp = this.toVp(newValue.height);
            this.redraw();
          })
          .accessibilityText(this.previewAccessibility())

        if (this.selected) {
          Text('已选择')
            .id('template-selected-' + this.templateId())
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(6)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin({ top: 4, right: 4 })
            .accessibilityText('当前模板已选择')
        }
      }
      .width('100%')

      Text(this.displayName())
        .width('100%')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(formatTemplateDimensions(this.template))
        .width('100%')
        .fontSize(10)
        .fontColor(COLOR_MUTED)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(formatTemplateSideSummary(this.template))
        .width('100%')
        .fontSize(10)
        .fontColor(COLOR_MUTED)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 7 }) {
        Row({ space: 3 }) {
          Row()
            .width(11)
            .height(2)
            .backgroundColor(COLOR_WALL)
          Text('墙')
            .fontSize(9)
            .fontColor(COLOR_MUTED)
        }
        Row({ space: 3 }) {
          Row()
            .width(11)
            .height(2)
            .backgroundColor(COLOR_PRIMARY)
          Text('开放')
            .fontSize(9)
            .fontColor(COLOR_MUTED)
        }
        Row({ space: 3 }) {
          Row()
            .width(11)
            .height(2)
            .backgroundColor(COLOR_ACCENT)
          Text('预留')
            .fontSize(9)
            .fontColor(COLOR_MUTED)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.selected ? COLOR_SELECTED : COLOR_CARD)
    .borderRadius(12)
    .border({
      width: this.selected ? 2 : 1,
      color: this.selected ? COLOR_PRIMARY : COLOR_BORDER
    })
    .opacity(this.disabled ? 0.55 : 1)
    .enabled(!this.disabled)
    .id('template-' + this.templateId())
    .accessibilityText(this.cardAccessibility())
    .onClick(() => {
      if (this.disabled) {
        return;
      }
      if (!isTemplatePreviewable(this.template)) {
        return;
      }
      const templateId: string = this.template.id;
      if (typeof templateId !== 'string' || templateId.length === 0) {
        return;
      }
      this.onSelect(templateId);
    })
  }

  private toVp(value: Length): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) && value > 0 ? value : 0;
    }
    if (typeof value === 'string') {
      const parsed: number = parseFloat(value);
      return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
    }
    return 0;
  }

  private templateId(): string {
    if (this.template === null || this.template === undefined ||
      typeof this.template !== 'object') {
      return 'unknown';
    }
    return typeof this.template.id === 'string' && this.template.id.length > 0 ?
      this.template.id : 'unknown';
  }

  private displayName(): string {
    if (this.template === null || this.template === undefined ||
      typeof this.template !== 'object') {
      return '模板数据无效';
    }
    return typeof this.template.name === 'string' && this.template.name.length > 0 ?
      this.template.name : '未命名模板';
  }

  private previewAccessibility(): string {
    if (!isTemplatePreviewable(this.template)) {
      return '展位模板预览不可用';
    }
    return '展位模板预览：' + this.displayName() + '，' +
      formatTemplateDimensions(this.template) + '，' +
      formatTemplateSideSummary(this.template);
  }

  private cardAccessibility(): string {
    const state: string = this.disabled ? '不可用' : (this.selected ? '已选择' : '未选择');
    return '展位模板：' + this.displayName() + '，' + state + '，' +
      formatTemplateDimensions(this.template) + '，' +
      formatTemplateSideSummary(this.template);
  }

  private redraw(): void {
    if (!this.canvasReady || this.canvasWidthVp <= 0 || this.canvasHeightVp <= 0) {
      return;
    }
    this.context.clearRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    this.context.fillStyle = COLOR_PAGE;
    this.context.fillRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    const noDash: number[] = [];
    this.context.setLineDash(noDash);

    if (!isTemplatePreviewable(this.template)) {
      this.drawCenteredMessage('模板数据无效');
      this.hasViewport = false;
      return;
    }
    const viewportResult = createViewport(this.canvasWidthVp, this.canvasHeightVp,
      this.template.widthCm, this.template.heightCm, PREVIEW_PADDING_VP);
    if (viewportResult.code !== 'OK' || viewportResult.data === undefined) {
      this.drawCenteredMessage('模板尺寸无效');
      this.hasViewport = false;
      return;
    }
    const geometry: TemplatePreviewGeometry | null =
      getTemplatePreviewGeometry(this.template);
    if (geometry === null) {
      this.drawCenteredMessage('模板几何无效');
      this.hasViewport = false;
      return;
    }
    this.viewportScale = viewportResult.data.scale;
    this.viewportOffsetX = viewportResult.data.offsetX;
    this.viewportOffsetY = viewportResult.data.offsetY;
    this.hasViewport = true;

    this.drawBooth();
    this.drawReservedAreas(geometry.reservedAreas);
    this.drawSides(geometry.walls, COLOR_WALL, 2.5, false);
    this.drawSides(geometry.openSides, COLOR_PRIMARY, 2, true);
  }

  private drawBooth(): void {
    const topLeft: Point | null = this.worldPointToScreen(0, 0);
    const bottomRight: Point | null =
      this.worldPointToScreen(this.template.widthCm, this.template.heightCm);
    if (topLeft === null || bottomRight === null) {
      return;
    }
    this.context.fillStyle = COLOR_CARD;
    this.context.fillRect(topLeft.x, topLeft.y,
      bottomRight.x - topLeft.x, bottomRight.y - topLeft.y);
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
    this.context.strokeStyle = COLOR_BORDER;
    this.context.lineWidth = 1;
    this.context.strokeRect(topLeft.x, topLeft.y,
      bottomRight.x - topLeft.x, bottomRight.y - topLeft.y);
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
    lineWidth: number, dashed: boolean): void {
    if (dashed) {
      const dash: number[] = [4, 3];
      this.context.setLineDash(dash);
    } else {
      const noDash: number[] = [];
      this.context.setLineDash(noDash);
    }
    this.context.strokeStyle = color;
    this.context.lineWidth = lineWidth;
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
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
  }

  private worldPointToScreen(x: number, y: number): Point | null {
    if (!this.hasViewport) {
      return null;
    }
    const result = worldToScreen({ x: x, y: y }, {
      scale: this.viewportScale,
      offsetX: this.viewportOffsetX,
      offsetY: this.viewportOffsetY
    });
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
    return {
      x: topLeft.x,
      y: topLeft.y,
      width: bottomRight.x - topLeft.x,
      height: bottomRight.y - topLeft.y
    };
  }

  private drawCenteredMessage(message: string): void {
    this.context.font = '11px sans-serif';
    this.context.fillStyle = COLOR_TEXT;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillText(message, this.canvasWidthVp / 2, this.canvasHeightVp / 2);
  }
}
