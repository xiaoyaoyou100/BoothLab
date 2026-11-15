/**
 * BoothLab M1 editor page (A01).
 *
 * One Canvas draws the booth, the 10 cm logical grid, walls/open sides from the
 * catalog template, reserved reminder areas, committed objects, selection and
 * the drag preview. Hit testing is geometric; there is no second overlay layer.
 *
 * All drawing uses Canvas-local vp. The viewport converts world cm to vp
 * exactly once, and touch coordinates are already Canvas-local vp, so no
 * density multiplication is applied here.
 */

import {
  BoothTemplate,
  PlacedObject,
  Point,
  Rect,
  Rotation,
  Side,
  Viewport
} from '../model/BoothModels';
import { EditorController } from '../engine/EditorController';
import {
  createViewport,
  DEFAULT_VIEWPORT_PADDING_VP,
  screenToWorld,
  worldToScreen
} from '../engine/GeometryEngine';

const COLOR_PAGE: string = '#F7F8F4';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_CANVAS: string = '#FFFEF9';
const COLOR_BOOTH: string = '#FFFFFF';
const COLOR_MUTED: string = '#6B7C80';
const COLOR_GRID_MAJOR: string = '#D3E0DA';
const COLOR_OBJECT_FILL: string = '#E8F2EF';
const COLOR_OBJECT_SELECTED_FILL: string = '#FFF0DF';

const GRID_STEP_CM: number = 10;
const MAJOR_GRID_STEP_CM: number = 100;

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

function formatCm(value: number): string {
  if (!Number.isFinite(value)) {
    return '—';
  }
  if (Number.isInteger(value)) {
    return value.toString();
  }
  return value.toFixed(1);
}

function findTouch(touches: TouchObject[], id: number): TouchObject | null {
  for (let i = 0; i < touches.length; i++) {
    if (touches[i].id === id) {
      return touches[i];
    }
  }
  return null;
}

function hasSide(sides: Side[], side: Side): boolean {
  for (let i = 0; i < sides.length; i++) {
    if (sides[i] === side) {
      return true;
    }
  }
  return false;
}

@Entry
@Component
struct Index {
  private controller: EditorController = new EditorController('standard');
  private context: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private viewport: Viewport | null = null;
  private canvasWidthVp: number = 0;
  private canvasHeightVp: number = 0;
  private activeTouchId: number = -1;
  private touchStartedDrag: boolean = false;
  private dragMoved: boolean = false;
  private canvasReady: boolean = false;

  @State hasSelection: boolean = false;
  @State selectedId: string = '';
  @State dragging: boolean = false;
  @State committedSummary: string = '未选中物件';
  @State previewSummary: string = '预览：无';
  @State statusText: string = '点选展示桌后可拖动；拖动结束才提交位置';

  aboutToAppear(): void {
    this.refreshUi();
  }

  build() {
    Column() {
      Column({ space: 2 }) {
        Text('展构 · BoothLab')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
        Text('标准展位 6m×4m')
          .fontSize(13)
          .fontColor(COLOR_MUTED)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 18, right: 18, top: 14, bottom: 8 })

      Canvas(this.context)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(COLOR_CANVAS)
        .accessibilityText('展位编辑画布：标准展位六米乘四米，包含一张可拖动的展示桌')
        .onReady(() => {
          this.handleReady();
        })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.handleAreaChange(newValue);
        })
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })

      Column({ space: 3 }) {
        Text(this.committedSummary)
          .fontSize(13)
          .fontColor(COLOR_TEXT)
          .width('100%')
          .height(20)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText('所选物件坐标：' + this.committedSummary)
        Text(this.previewSummary)
          .fontSize(12)
          .fontColor(COLOR_MUTED)
          .width('100%')
          .height(18)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText('拖动预览：' + this.previewSummary)
      }
      .width('100%')
      .height(54)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 18, right: 18, top: 8, bottom: 4 })

      Row({ space: 10 }) {
        Button('旋转 90°')
          .type(ButtonType.Normal)
          .backgroundColor(COLOR_PRIMARY)
          .fontColor('#FFFFFF')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(42)
          .borderRadius(10)
          .layoutWeight(1)
          .enabled(this.hasSelection && !this.dragging)
          .opacity(this.hasSelection && !this.dragging ? 1 : 0.45)
          .accessibilityText('将选中的物件顺时针旋转九十度')
          .onClick(() => {
            this.handleRotateClick();
          })
        Button('回到中心')
          .type(ButtonType.Normal)
          .backgroundColor(COLOR_ACCENT)
          .fontColor(COLOR_TEXT)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(42)
          .borderRadius(10)
          .layoutWeight(1)
          .enabled(this.hasSelection && !this.dragging)
          .opacity(this.hasSelection && !this.dragging ? 1 : 0.45)
          .accessibilityText('将选中的物件移动到展位中心')
          .onClick(() => {
            this.handleCenterClick();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 4, bottom: 10 })

      Text(this.statusText)
        .fontSize(12)
        .fontColor(COLOR_TEXT)
        .width('100%')
        .height(50)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 18, right: 18, bottom: 8 })
        .accessibilityText('操作状态：' + this.statusText)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_PAGE)
  }

  // ------------------------------------------------------------------
  // State and viewport
  // ------------------------------------------------------------------

  private handleReady(): void {
    this.canvasReady = true;
    this.refreshViewport();
    this.drawCanvas();
  }

  private handleAreaChange(newValue: Area): void {
    const width: number = lengthToVp(newValue.width);
    const height: number = lengthToVp(newValue.height);
    if (width === this.canvasWidthVp && height === this.canvasHeightVp) {
      return;
    }
    this.canvasWidthVp = width;
    this.canvasHeightVp = height;
    if (this.controller.isDragging()) {
      this.controller.cancelDrag();
      this.statusText = '画布尺寸变化，已取消拖动，位置未改变';
    }
    this.activeTouchId = -1;
    this.touchStartedDrag = false;
    this.dragMoved = false;
    this.refreshViewport();
    this.refreshUi();
    this.drawCanvas();
  }

  private refreshViewport(): void {
    const template: BoothTemplate = this.controller.getTemplate();
    const result = createViewport(this.canvasWidthVp, this.canvasHeightVp,
      template.widthCm, template.heightCm, DEFAULT_VIEWPORT_PADDING_VP);
    if (result.code === 'OK' && result.data !== undefined) {
      this.viewport = result.data;
    } else {
      this.viewport = null;
    }
  }

  private refreshUi(): void {
    const selected: PlacedObject | null = this.controller.getSelectedObject();
    if (selected === null) {
      this.hasSelection = false;
      this.selectedId = '';
      this.committedSummary = '未选中物件';
    } else {
      this.hasSelection = true;
      this.selectedId = selected.id;
      this.committedSummary = '已选：' + this.catalogName(selected.catalogId) +
        ' · 中心 (' + formatCm(selected.centerX) + ', ' + formatCm(selected.centerY) +
        ') cm · 旋转 ' + selected.rotation + '°';
    }

    const preview: PlacedObject | null = this.controller.getPreviewObject();
    if (preview === null) {
      this.previewSummary = '预览：无';
    } else {
      this.previewSummary = '预览：中心 (' + formatCm(preview.centerX) + ', ' +
        formatCm(preview.centerY) + ') cm（未提交）';
    }
    this.dragging = this.controller.isDragging();
  }

  private catalogName(catalogId: string): string {
    const result = this.controller.getCatalogItem(catalogId);
    if (result.code === 'OK' && result.data !== undefined) {
      return result.data.name;
    }
    return catalogId;
  }

  // ------------------------------------------------------------------
  // Toolbar actions
  // ------------------------------------------------------------------

  private handleRotateClick(): void {
    if (this.selectedId === '' || this.dragging) {
      this.statusText = '请选择一个未在拖动中的物件';
      return;
    }
    const result = this.controller.rotateObject(this.selectedId);
    if (result.code === 'OK') {
      this.statusText = '已顺时针旋转 90°';
    } else if (result.code === 'OUT_OF_BOUNDS') {
      this.statusText = '旋转被拒绝：旋转后会超出展位边界，已保持原方向';
    } else if (result.code === 'NOT_FOUND') {
      this.statusText = '旋转失败：所选物件不存在';
    } else {
      this.statusText = '旋转失败：输入无效';
    }
    this.refreshUi();
    this.drawCanvas();
  }

  private handleCenterClick(): void {
    if (this.selectedId === '' || this.dragging) {
      this.statusText = '请选择一个未在拖动中的物件';
      return;
    }
    const template: BoothTemplate = this.controller.getTemplate();
    const center: Point = { x: template.widthCm / 2, y: template.heightCm / 2 };
    const result = this.controller.moveObject(this.selectedId, center);
    if (result.code === 'OK') {
      this.statusText = '已回到展位中心';
    } else if (result.code === 'OUT_OF_BOUNDS') {
      this.statusText = '回到中心被拒绝：物件占位会超出展位';
    } else if (result.code === 'NOT_FOUND') {
      this.statusText = '回到中心失败：所选物件不存在';
    } else {
      this.statusText = '回到中心失败：输入无效';
    }
    this.refreshUi();
    this.drawCanvas();
  }

  // ------------------------------------------------------------------
  // Touch handling: one initiating finger controls the gesture
  // ------------------------------------------------------------------

  private handleTouch(event: TouchEvent): void {
    event.stopPropagation();
    if (this.viewport === null) {
      this.statusText = '画布不可用：视口尺寸无效';
      return;
    }
    if (event.type === TouchType.Down) {
      this.handleTouchDown(event);
    } else if (event.type === TouchType.Move) {
      this.handleTouchMove(event);
    } else if (event.type === TouchType.Up) {
      this.handleTouchUp(event);
    } else if (event.type === TouchType.Cancel) {
      this.handleTouchCancel(event);
    }
  }

  private handleTouchDown(event: TouchEvent): void {
    if (this.activeTouchId !== -1) {
      return;
    }
    if (event.changedTouches.length === 0) {
      return;
    }
    const touch: TouchObject = event.changedTouches[0];
    this.activeTouchId = touch.id;
    this.touchStartedDrag = false;
    this.dragMoved = false;

    const world: Point | null = this.toWorld(touch.x, touch.y);
    if (world === null) {
      this.activeTouchId = -1;
      this.statusText = '坐标转换失败，未开始拖动';
      this.refreshUi();
      this.drawCanvas();
      return;
    }

    const hit = this.controller.hitTest(world);
    if (hit.code !== 'OK') {
      this.activeTouchId = -1;
      this.statusText = '选择失败：' + hit.message;
      this.refreshUi();
      this.drawCanvas();
      return;
    }
    if (hit.data === null || hit.data === undefined) {
      this.controller.selectObject(null);
      this.statusText = '已取消选择';
      this.refreshUi();
      this.drawCanvas();
      return;
    }
    const hitId: string = hit.data;

    const begin = this.controller.beginDrag(hitId, world);
    if (begin.code === 'OK') {
      this.touchStartedDrag = true;
      this.statusText = '拖动中；松开后若完全在展位内才提交';
    } else {
      this.controller.selectObject(hitId);
      this.statusText = '拖动开始失败：' + begin.message;
    }
    this.refreshUi();
    this.drawCanvas();
  }

  private handleTouchMove(event: TouchEvent): void {
    if (this.activeTouchId === -1 || !this.touchStartedDrag) {
      return;
    }
    const touch: TouchObject | null = findTouch(event.changedTouches, this.activeTouchId);
    if (touch === null) {
      return;
    }
    const world: Point | null = this.toWorld(touch.x, touch.y);
    if (world === null) {
      this.controller.cancelDrag();
      this.activeTouchId = -1;
      this.touchStartedDrag = false;
      this.dragMoved = false;
      this.statusText = '坐标转换失败，已取消拖动，位置未改变';
      this.refreshUi();
      this.drawCanvas();
      return;
    }
    const update = this.controller.updateDrag(world);
    if (update.code !== 'OK') {
      this.statusText = '拖动更新失败：' + update.message;
    } else {
      this.dragMoved = true;
    }
    this.refreshUi();
    this.drawCanvas();
  }

  private handleTouchUp(event: TouchEvent): void {
    if (this.activeTouchId === -1) {
      return;
    }
    if (!this.touchStartedDrag) {
      this.activeTouchId = -1;
      this.dragMoved = false;
      this.refreshUi();
      this.drawCanvas();
      return;
    }

    let touch: TouchObject | null = findTouch(event.changedTouches, this.activeTouchId);
    if (touch === null) {
      if (event.changedTouches.length > 0) {
        // Another finger lifted; the initiating touch still owns the drag.
        return;
      }
      touch = findTouch(event.touches, this.activeTouchId);
    }
    if (touch === null) {
      this.controller.cancelDrag();
      this.activeTouchId = -1;
      this.touchStartedDrag = false;
      this.dragMoved = false;
      this.statusText = '未找到结束触点，已取消拖动，位置未改变';
      this.refreshUi();
      this.drawCanvas();
      return;
    }

    // Push the final UP point through updateDrag before committing, so the
    // last small move is not lost.
    const world: Point | null = this.toWorld(touch.x, touch.y);
    if (world === null) {
      this.controller.cancelDrag();
      this.activeTouchId = -1;
      this.touchStartedDrag = false;
      this.dragMoved = false;
      this.statusText = '坐标转换失败，已取消拖动，位置未改变';
      this.refreshUi();
      this.drawCanvas();
      return;
    }
    const update = this.controller.updateDrag(world);
    if (update.code !== 'OK') {
      this.controller.cancelDrag();
      this.activeTouchId = -1;
      this.touchStartedDrag = false;
      this.dragMoved = false;
      this.statusText = '最终触点无效，已取消拖动';
      this.refreshUi();
      this.drawCanvas();
      return;
    }

    const end = this.controller.endDrag();
    if (end.code === 'OK') {
      this.statusText = this.dragMoved ? '已提交移动' : '已选择物件';
    } else if (end.code === 'OUT_OF_BOUNDS') {
      this.statusText = '超出展位边界，已恢复上次位置';
    } else {
      this.statusText = '移动提交失败：' + end.message;
    }
    this.activeTouchId = -1;
    this.touchStartedDrag = false;
    this.dragMoved = false;
    this.refreshUi();
    this.drawCanvas();
  }

  private handleTouchCancel(event: TouchEvent): void {
    if (this.activeTouchId === -1) {
      return;
    }
    if (event.changedTouches.length > 0 &&
      findTouch(event.changedTouches, this.activeTouchId) === null) {
      // Cancel belongs to another finger; keep the initiating drag alive.
      return;
    }
    if (this.touchStartedDrag) {
      this.controller.cancelDrag();
      this.statusText = '拖动已取消，位置未改变';
    }
    this.activeTouchId = -1;
    this.touchStartedDrag = false;
    this.dragMoved = false;
    this.refreshUi();
    this.drawCanvas();
  }

  private toWorld(screenX: number, screenY: number): Point | null {
    if (this.viewport === null) {
      return null;
    }
    const point: Point = { x: screenX, y: screenY };
    const result = screenToWorld(point, this.viewport);
    if (result.code !== 'OK' || result.data === undefined) {
      return null;
    }
    return result.data;
  }

  // ------------------------------------------------------------------
  // Drawing
  // ------------------------------------------------------------------

  private drawCanvas(): void {
    if (!this.canvasReady || this.canvasWidthVp <= 0 || this.canvasHeightVp <= 0) {
      return;
    }
    this.context.clearRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    this.context.fillStyle = COLOR_CANVAS;
    this.context.fillRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    const noDash: number[] = [];
    this.context.setLineDash(noDash);

    if (this.viewport === null) {
      this.drawCenteredMessage('画布尺寸不足，无法绘制展位');
      return;
    }

    const template: BoothTemplate = this.controller.getTemplate();
    this.drawBoothBase(template);
    this.drawGrid(template);
    this.drawReservedAreas(template);
    this.drawWalls(template);
    this.drawObjects();
    this.drawSelectedOutline();
    this.drawPreview();
    this.drawEntryDirection(template);
  }

  private drawBoothBase(template: BoothTemplate): void {
    const topLeft: Point | null = this.worldPointToScreen(0, 0);
    const bottomRight: Point | null = this.worldPointToScreen(template.widthCm, template.heightCm);
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

  private drawGrid(template: BoothTemplate): void {
    const minorDash: number[] = [];
    this.context.setLineDash(minorDash);
    this.context.strokeStyle = COLOR_BORDER;
    this.context.lineWidth = 0.5;
    this.context.beginPath();
    for (let x = GRID_STEP_CM; x < template.widthCm; x += GRID_STEP_CM) {
      const top: Point | null = this.worldPointToScreen(x, 0);
      const bottom: Point | null = this.worldPointToScreen(x, template.heightCm);
      if (top !== null && bottom !== null) {
        this.context.moveTo(top.x, top.y);
        this.context.lineTo(bottom.x, bottom.y);
      }
    }
    for (let y = GRID_STEP_CM; y < template.heightCm; y += GRID_STEP_CM) {
      const left: Point | null = this.worldPointToScreen(0, y);
      const right: Point | null = this.worldPointToScreen(template.widthCm, y);
      if (left !== null && right !== null) {
        this.context.moveTo(left.x, left.y);
        this.context.lineTo(right.x, right.y);
      }
    }
    this.context.stroke();

    this.context.strokeStyle = COLOR_GRID_MAJOR;
    this.context.lineWidth = 1;
    this.context.beginPath();
    for (let x = MAJOR_GRID_STEP_CM; x < template.widthCm; x += MAJOR_GRID_STEP_CM) {
      const top: Point | null = this.worldPointToScreen(x, 0);
      const bottom: Point | null = this.worldPointToScreen(x, template.heightCm);
      if (top !== null && bottom !== null) {
        this.context.moveTo(top.x, top.y);
        this.context.lineTo(bottom.x, bottom.y);
      }
    }
    for (let y = MAJOR_GRID_STEP_CM; y < template.heightCm; y += MAJOR_GRID_STEP_CM) {
      const left: Point | null = this.worldPointToScreen(0, y);
      const right: Point | null = this.worldPointToScreen(template.widthCm, y);
      if (left !== null && right !== null) {
        this.context.moveTo(left.x, left.y);
        this.context.lineTo(right.x, right.y);
      }
    }
    this.context.stroke();
  }

  private drawReservedAreas(template: BoothTemplate): void {
    for (let i = 0; i < template.reservedAreas.length; i++) {
      const screen: Rect | null = this.worldRectToScreen(template.reservedAreas[i]);
      if (screen === null) {
        continue;
      }
      this.context.strokeStyle = COLOR_ACCENT;
      this.context.lineWidth = 1.2;
      this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
      if (screen.width >= 42 && screen.height >= 12) {
        const label: string = screen.width >= 84 ? '预留区（提示）' : '预留区';
        const fontSize: number = Math.max(8, Math.min(10, screen.height * 0.4));
        this.context.font = fontSize.toFixed(0) + 'px sans-serif';
        this.context.fillStyle = COLOR_ACCENT;
        this.context.textAlign = 'center';
        this.context.textBaseline = 'middle';
        this.context.fillText(label, screen.x + screen.width / 2, screen.y + screen.height / 2);
      }
    }
  }

  private drawWalls(template: BoothTemplate): void {
    this.context.strokeStyle = COLOR_PRIMARY;
    this.context.lineWidth = 5;
    for (let i = 0; i < template.wallSides.length; i++) {
      this.drawSideLine(template.wallSides[i], template);
    }

    const dashed: number[] = [6, 5];
    this.context.setLineDash(dashed);
    this.context.strokeStyle = COLOR_ACCENT;
    this.context.lineWidth = 2;
    for (let i = 0; i < template.openSides.length; i++) {
      this.drawSideLine(template.openSides[i], template);
    }
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
  }

  private drawSideLine(side: Side, template: BoothTemplate): void {
    let start: Point;
    let end: Point;
    if (side === 'left') {
      start = { x: 0, y: 0 };
      end = { x: 0, y: template.heightCm };
    } else if (side === 'top') {
      start = { x: 0, y: 0 };
      end = { x: template.widthCm, y: 0 };
    } else if (side === 'right') {
      start = { x: template.widthCm, y: 0 };
      end = { x: template.widthCm, y: template.heightCm };
    } else {
      start = { x: 0, y: template.heightCm };
      end = { x: template.widthCm, y: template.heightCm };
    }
    const a: Point | null = this.worldPointToScreen(start.x, start.y);
    const b: Point | null = this.worldPointToScreen(end.x, end.y);
    if (a === null || b === null) {
      return;
    }
    this.context.beginPath();
    this.context.moveTo(a.x, a.y);
    this.context.lineTo(b.x, b.y);
    this.context.stroke();
  }

  private drawObjects(): void {
    const objects: PlacedObject[] = this.controller.getObjects();
    const preview: PlacedObject | null = this.controller.getPreviewObject();
    if (preview !== null) {
      for (let i = 0; i < objects.length; i++) {
        if (objects[i].id === preview.id) {
          objects[i] = preview;
        }
      }
    }
    objects.sort((a: PlacedObject, b: PlacedObject) => a.zIndex - b.zIndex);
    for (let i = 0; i < objects.length; i++) {
      const object: PlacedObject = objects[i];
      const footprint = this.controller.getFootprint(object);
      if (footprint.code !== 'OK' || footprint.data === undefined) {
        continue;
      }
      const screen: Rect | null = this.worldRectToScreen(footprint.data);
      if (screen === null) {
        continue;
      }
      const selected: boolean = this.selectedId === object.id;
      this.context.fillStyle = selected ? COLOR_OBJECT_SELECTED_FILL : COLOR_OBJECT_FILL;
      this.context.fillRect(screen.x, screen.y, screen.width, screen.height);
      this.context.strokeStyle = selected ? COLOR_ACCENT : COLOR_PRIMARY;
      this.context.lineWidth = selected ? 2 : 1.5;
      this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
      this.drawObjectLabel(object, screen);
      this.drawOrientationMarker(object.rotation, screen, selected ? COLOR_ACCENT : COLOR_PRIMARY);
    }
  }

  private drawObjectLabel(object: PlacedObject, screen: Rect): void {
    if (screen.width < 30 || screen.height < 14) {
      return;
    }
    const fontSize: number = Math.max(9, Math.min(13, screen.height * 0.3));
    this.context.font = fontSize.toFixed(0) + 'px sans-serif';
    this.context.fillStyle = COLOR_TEXT;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillText(this.catalogName(object.catalogId),
      screen.x + screen.width / 2, screen.y + screen.height / 2);
  }

  /**
   * A corner notch marks the local top-left corner after clockwise rotation:
   * 0 -> top-left, 90 -> top-right, 180 -> bottom-right, 270 -> bottom-left.
   * Four 90 degree turns therefore return to exactly the same visual marker.
   */
  private drawOrientationMarker(rotation: Rotation, screen: Rect, color: string): void {
    const extent: number = Math.min(screen.width, screen.height);
    const inset: number = Math.max(3, Math.min(6, extent * 0.18));
    const radius: number = Math.max(2.5, Math.min(4, extent * 0.12));
    let markerX: number = screen.x + inset;
    let markerY: number = screen.y + inset;
    if (rotation === 90) {
      markerX = screen.x + screen.width - inset;
      markerY = screen.y + inset;
    } else if (rotation === 180) {
      markerX = screen.x + screen.width - inset;
      markerY = screen.y + screen.height - inset;
    } else if (rotation === 270) {
      markerX = screen.x + inset;
      markerY = screen.y + screen.height - inset;
    }

    this.context.beginPath();
    this.context.arc(markerX, markerY, radius, 0, Math.PI * 2);
    this.context.fillStyle = color;
    this.context.fill();
  }

  private drawSelectedOutline(): void {
    const preview: PlacedObject | null = this.controller.getPreviewObject();
    const selected: PlacedObject | null = preview === null ? this.controller.getSelectedObject() : preview;
    if (selected === null) {
      return;
    }
    const footprint = this.controller.getFootprint(selected);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      return;
    }
    const screen: Rect | null = this.worldRectToScreen(footprint.data);
    if (screen === null) {
      return;
    }
    this.context.strokeStyle = COLOR_ACCENT;
    this.context.lineWidth = 3;
    this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
  }

  private drawPreview(): void {
    if (!this.controller.isDragging()) {
      return;
    }
    const preview: PlacedObject | null = this.controller.getPreviewObject();
    if (preview === null) {
      return;
    }
    const footprint = this.controller.getFootprint(preview);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      return;
    }
    const screen: Rect | null = this.worldRectToScreen(footprint.data);
    if (screen === null) {
      return;
    }
    const dashed: number[] = [6, 4];
    this.context.setLineDash(dashed);
    this.context.strokeStyle = COLOR_ACCENT;
    this.context.lineWidth = 2.5;
    this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
  }

  private drawEntryDirection(template: BoothTemplate): void {
    if (hasSide(template.openSides, 'bottom')) {
      const anchor: Point | null = this.worldPointToScreen(template.widthCm / 2, template.heightCm);
      if (anchor !== null) {
        this.context.font = '12px sans-serif';
        this.context.fillStyle = COLOR_PRIMARY;
        this.context.textAlign = 'center';
        this.context.textBaseline = 'top';
        this.context.fillText('入口方向 ↓', anchor.x, anchor.y + 8);
      }
    }
    if (hasSide(template.openSides, 'right')) {
      const anchor: Point | null = this.worldPointToScreen(template.widthCm, template.heightCm / 2);
      if (anchor !== null) {
        this.context.font = '11px sans-serif';
        this.context.fillStyle = COLOR_ACCENT;
        this.context.textAlign = 'left';
        this.context.textBaseline = 'middle';
        this.context.fillText('开放', anchor.x + 8, anchor.y);
      }
    }
  }

  private drawCenteredMessage(message: string): void {
    this.context.font = '13px sans-serif';
    this.context.fillStyle = COLOR_TEXT;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillText(message, this.canvasWidthVp / 2, this.canvasHeightVp / 2);
  }

  private worldPointToScreen(x: number, y: number): Point | null {
    if (this.viewport === null) {
      return null;
    }
    const world: Point = { x: x, y: y };
    const result = worldToScreen(world, this.viewport);
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
}
