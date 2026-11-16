/**
 * BoothLab M2-I01 editor workspace.
 *
 * Mechanical extraction of the M1/M2-A editor page: one Canvas draws the booth,
 * the 10 cm logical grid, walls/open sides from the catalog template, reserved
 * reminder areas, committed objects, selection and the drag preview. Hit
 * testing is geometric; there is no second overlay layer.
 *
 * The component is a child of the application shell. It receives an opening
 * plan snapshot and imports it once in aboutToAppear; the plan prop is never
 * re-applied after that, so parent rebuilds and save completions cannot erase
 * the editor's local history. Only effective formal changes (when the
 * controller's session revision advances) are reported through onChanged.
 *
 * All drawing uses Canvas-local vp. The viewport converts world cm to vp
 * exactly once, and touch coordinates are already Canvas-local vp, so no
 * density multiplication is applied here.
 */

import {
  BoothPlan,
  BoothTemplate,
  CatalogItem,
  LayoutIssue,
  OperationCode,
  PlacedObject,
  Point,
  Rect,
  Rotation,
  Side,
  Viewport
} from '../../model/BoothModels';
import { SaveState } from '../../model/M2Contracts';
import { listCatalogItems } from '../../catalog/ObjectCatalogData';
import { EditorController } from '../../engine/EditorController';
import { EditorChangeNotifier } from '../../application/EditorChangeNotifier';
import {
  createViewport,
  DEFAULT_VIEWPORT_PADDING_VP,
  screenToWorld,
  worldToScreen
} from '../../engine/GeometryEngine';
import { drawObjectVisual } from '../catalog/ObjectVisuals';
import { ObjectCatalogPicker } from '../catalog/ObjectCatalogPicker';

const COLOR_PAGE: string = '#F7F8F4';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_CANVAS: string = '#FFFEF9';
const COLOR_BOOTH: string = '#FFFFFF';
const COLOR_MUTED: string = '#6B7C80';
const COLOR_GRID_MAJOR: string = '#D3E0DA';
const COLOR_DANGER: string = '#B91C1C';
const COLOR_WARNING: string = '#B45309';

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

export function formatCm(value: number): string {
  if (!Number.isFinite(value)) {
    return '—';
  }
  if (Number.isInteger(value)) {
    return value.toString();
  }
  return value.toFixed(1);
}

export function formatMeters(cm: number): string {
  if (!Number.isFinite(cm)) {
    return '—';
  }
  const metres: number = cm / 100;
  if (Number.isInteger(metres)) {
    return metres.toString();
  }
  return metres.toFixed(1);
}

/**
 * Truthful save/closing label. The externally owned saveState remains the
 * source of truth; saveBusy and closing only refine the wording while a real
 * save/leave is in progress. A real SaveError always wins over the transient
 * closing wording.
 */
export function formatSaveStateLabel(saveState: SaveState, saveBusy: boolean,
  closing: boolean): string {
  if (saveState === 'SaveError') {
    return '保存失败';
  }
  if (closing) {
    return saveState === 'Saving' || saveBusy ? '正在保存并返回' : '正在返回';
  }
  if (saveBusy || saveState === 'Saving') {
    return '保存中';
  }
  if (saveState === 'Saved') {
    return '已保存';
  }
  if (saveState === 'Dirty') {
    return '未保存';
  }
  return '未保存';
}

export function formatSaveButtonLabel(saveState: SaveState, saveBusy: boolean,
  closing: boolean): string {
  if (closing) {
    return '返回中';
  }
  if (saveBusy || saveState === 'Saving') {
    return '保存中';
  }
  if (saveState === 'SaveError') {
    return '重试';
  }
  return '保存';
}

export function canSaveAction(locked: boolean, saveBusy: boolean,
  saveState: SaveState): boolean {
  if (locked || saveBusy || saveState === 'Saving') {
    return false;
  }
  return true;
}

export function canBackAction(closing: boolean): boolean {
  return !closing;
}

export function canUndoAction(canUndo: boolean, dragging: boolean, locked: boolean): boolean {
  return canUndo && !dragging && !locked;
}

export function canRedoAction(canRedo: boolean, dragging: boolean, locked: boolean): boolean {
  return canRedo && !dragging && !locked;
}

export function canDeleteAction(hasSelection: boolean, dragging: boolean,
  locked: boolean): boolean {
  return hasSelection && !dragging && !locked;
}

export function canRotateAction(hasSelection: boolean, dragging: boolean,
  locked: boolean): boolean {
  return hasSelection && !dragging && !locked;
}

export function canCenterAction(hasSelection: boolean, dragging: boolean,
  locked: boolean): boolean {
  return hasSelection && !dragging && !locked;
}

export function canAddAction(locked: boolean, dragging: boolean): boolean {
  return !locked && !dragging;
}

export function formatObjectCount(count: number): string {
  if (!Number.isFinite(count) || count < 0) {
    return '物件 0 件';
  }
  return '物件 ' + Math.floor(count).toString() + ' 件';
}

export function formatLayoutIssueSummary(count: number): string {
  if (!Number.isFinite(count) || count <= 0) {
    return '布局正常';
  }
  return '布局提醒 ' + Math.floor(count).toString() + ' 条';
}

export function formatSelectedCenterText(centerX: number, centerY: number): string {
  if (!Number.isFinite(centerX) || !Number.isFinite(centerY)) {
    return '中心坐标无效';
  }
  return '中心 (' + formatCm(centerX) + ', ' + formatCm(centerY) + ') cm';
}

export function formatFootprintText(widthCm: number, heightCm: number): string {
  if (!Number.isFinite(widthCm) || !Number.isFinite(heightCm) ||
    widthCm <= 0 || heightCm <= 0) {
    return '占位尺寸未知';
  }
  return '占位 ' + formatCm(widthCm) + '×' + formatCm(heightCm) + ' cm';
}

export function formatRotationText(rotation: number): string {
  if (!Number.isFinite(rotation)) {
    return '旋转 —';
  }
  return '旋转 ' + Math.round(rotation).toString() + '°';
}

export function formatIssueTypeLabel(code: string): string {
  if (code === 'OVERLAP') {
    return '重叠';
  }
  if (code === 'ENTRY_OCCUPIED') {
    return '预留区';
  }
  if (code === 'BLOCKED_AREA') {
    return '禁放区';
  }
  if (code === 'OUT_OF_BOUNDS') {
    return '越界';
  }
  return '数据异常';
}

export function formatIssueSeverityLabel(severity: string): string {
  if (severity === 'error') {
    return '错误';
  }
  if (severity === 'warning') {
    return '提醒';
  }
  return '提示';
}

export function formatIssueIdsLabel(objectIds: string[]): string {
  if (objectIds.length === 0) {
    return '展位或数据';
  }
  let text: string = '';
  for (let i = 0; i < objectIds.length; i++) {
    if (i > 0) {
      text += ' / ';
    }
    text += objectIds[i];
  }
  return text;
}

/**
 * Highest-severity issue linked to one object. Used only for selected-object
 * presentation (outline colour and the property badge), never for placement.
 */
export function findIssueSeverityForObject(issues: LayoutIssue[], objectId: string): string {
  if (objectId === '') {
    return '';
  }
  let hasWarning: boolean = false;
  for (let i = 0; i < issues.length; i++) {
    const issue: LayoutIssue = issues[i];
    let linked: boolean = false;
    for (let j = 0; j < issue.objectIds.length; j++) {
      if (issue.objectIds[j] === objectId) {
        linked = true;
        break;
      }
    }
    if (!linked) {
      continue;
    }
    if (issue.severity === 'error') {
      return 'error';
    }
    if (issue.severity === 'warning') {
      hasWarning = true;
    }
  }
  return hasWarning ? 'warning' : '';
}

/**
 * Screen-space draw request for one committed/preview object. widthVp and
 * heightVp are always the UNROTATED catalog extents scaled once by the
 * existing viewport; rotation is passed through unchanged exactly once.
 */
export interface ObjectVisualDraw {
  imageKey: string;
  centerX: number;
  centerY: number;
  widthVp: number;
  heightVp: number;
  rotation: Rotation;
}

/**
 * Resolves one object's Canvas-local draw request. The world centre goes
 * through the existing worldToScreen transform; the drawn extents come from
 * the real catalog's unrotated widthCm/heightCm multiplied by viewport.scale.
 * No rotated footprint is used here, so 90/270 cannot be swapped twice.
 */
export function resolveObjectVisualDraw(viewport: Viewport | null,
  object: PlacedObject, catalog: CatalogItem): ObjectVisualDraw | null {
  if (viewport === null) {
    return null;
  }
  if (!Number.isFinite(catalog.widthCm) || !Number.isFinite(catalog.heightCm) ||
    catalog.widthCm <= 0 || catalog.heightCm <= 0) {
    return null;
  }
  const world: Point = { x: object.centerX, y: object.centerY };
  const screen = worldToScreen(world, viewport);
  if (screen.code !== 'OK' || screen.data === undefined) {
    return null;
  }
  const widthVp: number = viewport.scale * catalog.widthCm;
  const heightVp: number = viewport.scale * catalog.heightCm;
  if (!Number.isFinite(widthVp) || !Number.isFinite(heightVp) ||
    widthVp <= 0 || heightVp <= 0) {
    return null;
  }
  const draw: ObjectVisualDraw = {
    imageKey: typeof catalog.imageKey === 'string' ? catalog.imageKey : '',
    centerX: screen.data.x,
    centerY: screen.data.y,
    widthVp: widthVp,
    heightVp: heightVp,
    rotation: object.rotation
  };
  return draw;
}

/**
 * Resolves one committed/preview object through the frozen controller catalog
 * lookup and then the cm -> vp draw helper. An unknown catalog id returns null
 * so the Canvas skips it instead of inventing a footprint or image key.
 */
export function resolveObjectVisualForCatalogId(controller: EditorController,
  viewport: Viewport | null, object: PlacedObject): ObjectVisualDraw | null {
  const catalogResult = controller.getCatalogItem(object.catalogId);
  if (catalogResult.code !== 'OK' || catalogResult.data === undefined) {
    return null;
  }
  return resolveObjectVisualDraw(viewport, object, catalogResult.data);
}

/**
 * Finds a legal centre near the booth centre for a catalog item. Overlap is
 * allowed (the layout panel reports it); only complete containment in the
 * booth is required. Unknown/invalid dimensions have no legal centre.
 */
export function findLegalAddCenter(template: BoothTemplate,
  item: CatalogItem): Point | null {
  if (!Number.isFinite(item.widthCm) || !Number.isFinite(item.heightCm) ||
    item.widthCm <= 0 || item.heightCm <= 0) {
    return null;
  }
  const halfWidth: number = item.widthCm / 2;
  const halfHeight: number = item.heightCm / 2;
  const minX: number = halfWidth;
  const maxX: number = template.widthCm - halfWidth;
  const minY: number = halfHeight;
  const maxY: number = template.heightCm - halfHeight;
  if (minX > maxX || minY > maxY) {
    return null;
  }
  const centerX: number = Math.min(Math.max(template.widthCm / 2, minX), maxX);
  const centerY: number = Math.min(Math.max(template.heightCm / 2, minY), maxY);
  const center: Point = { x: centerX, y: centerY };
  return center;
}

/** Picker selection is blocked while dragging or while the editor is locked. */
export function isPickerDisabled(locked: boolean, dragging: boolean): boolean {
  return locked || dragging;
}

/** Truthful outcome of one picker selection attempt. */
export interface CatalogAddAttempt {
  code: OperationCode;
  message: string;
  catalogId: string;
  catalogItem: CatalogItem | null;
  center: Point | null;
  addedObject: PlacedObject | null;
}

/**
 * The single picker -> existing-add-path adapter. It validates the catalogId
 * through the frozen controller/catalog lookup, finds a legal centre and calls
 * the existing Controller add path exactly once. It never selects the new
 * object, never changes preview/drag/history state itself, and never reports a
 * success before Controller confirms one.
 */
export function addCatalogObject(controller: EditorController,
  catalogId: string, disabled: boolean): CatalogAddAttempt {
  if (disabled) {
    return {
      code: 'INVALID_ARGUMENT',
      message: '添加失败：当前不可添加物件，请先结束拖动或等待操作完成',
      catalogId: catalogId,
      catalogItem: null,
      center: null,
      addedObject: null
    };
  }
  const catalogResult = controller.getCatalogItem(catalogId);
  if (catalogResult.code !== 'OK' || catalogResult.data === undefined) {
    return {
      code: 'NOT_FOUND',
      message: '添加失败：物件类型不在目录中',
      catalogId: catalogId,
      catalogItem: null,
      center: null,
      addedObject: null
    };
  }
  const item: CatalogItem = catalogResult.data;
  const center: Point | null = findLegalAddCenter(controller.getTemplate(), item);
  if (center === null) {
    return {
      code: 'OUT_OF_BOUNDS',
      message: '添加失败：展位内没有可容纳该物件的中心位置',
      catalogId: catalogId,
      catalogItem: item,
      center: null,
      addedObject: null
    };
  }
  const added = controller.addObject(catalogId, center);
  if (added.code === 'OK' && added.data !== undefined) {
    return {
      code: 'OK',
      message: '添加成功',
      catalogId: catalogId,
      catalogItem: item,
      center: center,
      addedObject: added.data
    };
  }
  let message: string = '添加失败：' + added.message;
  if (added.code === 'OUT_OF_BOUNDS') {
    message = '添加被拒绝：物件占位会超出展位边界';
  } else if (added.code === 'NOT_FOUND') {
    message = '添加失败：物件类型不在目录中';
  } else if (added.code === 'INVALID_ARGUMENT') {
    message = '添加失败：输入无效，未添加物件';
  }
  return {
    code: added.code,
    message: message,
    catalogId: catalogId,
    catalogItem: item,
    center: center,
    addedObject: null
  };
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

@Component
export struct EditorWorkspace {
  /** Opening snapshot. Imported once; later local edits stay inside the controller. */
  @Prop plan: BoothPlan;
  @Prop saveState: SaveState = 'Dirty';
  @Prop saveBusy: boolean = false;
  /** Set by the shell while it waits for the final save before leaving. */
  @Prop closing: boolean = false;
  @Prop message: string = '';
  onChanged: (plan: BoothPlan) => void = () => {};
  onSave: () => void = () => {};
  onBack: () => void = () => {};

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
  private changeNotifier: EditorChangeNotifier = new EditorChangeNotifier();

  private catalogItems: CatalogItem[] = listCatalogItems();

  @State editorReady: boolean = false;
  @State importError: string = '';
  @State planNameTitle: string = '';
  @State objectCount: number = 0;
  @State hasSelection: boolean = false;
  @State selectedId: string = '';
  @State selectedName: string = '';
  @State selectedFootprintText: string = '';
  @State selectedRotationDeg: number = 0;
  @State selectedIssueSeverity: string = '';
  @State dragging: boolean = false;
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;
  @State pickerVisible: boolean = false;
  @State pickerMessage: string = '';
  @State templateSummary: string = '';
  @State committedSummary: string = '点按画布中的物件进行选择或拖动';
  @State previewSummary: string = '预览：无';
  @State layoutIssues: LayoutIssue[] = [];
  @State statusText: string = '点按物件可选择或拖动；拖动结束才提交位置';

  aboutToAppear(): void {
    // The formal plan replaces the M1 demo seed entirely. A rejected import
    // leaves the editor disabled with an explicit error and never shows demo
    // content as if it were the user's plan.
    const imported = this.controller.importPlan(this.plan);
    if (imported.code !== 'OK' || imported.data === undefined) {
      this.importError = imported.message.length > 0 ? imported.message : '展位方案数据无效。';
      this.editorReady = false;
      return;
    }
    // Baseline is set before the first refresh so importing alone never looks
    // like a formal edit to the parent.
    this.changeNotifier.reset(this.controller.getChangeRevision());
    this.planNameTitle = imported.data.name;
    this.editorReady = true;
    this.refreshUi();
  }

  build() {
    Column() {
      // Header: navigation, real plan/template identity, object count and the
      // externally owned save/closing state. Back and save stay in this fixed
      // header, so they remain reachable without scrolling the editor body.
      Row({ space: 8 }) {
        Button('返回')
          .id('back-library')
          .type(ButtonType.Normal)
          .backgroundColor(COLOR_BORDER)
          .fontColor(COLOR_TEXT)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .height(40)
          .borderRadius(10)
          .width(60)
          .enabled(canBackAction(this.closing))
          .opacity(canBackAction(this.closing) ? 1 : 0.45)
          .accessibilityText('返回展位方案库')
          .onClick(() => {
            this.handleBackClick();
          })

        Column({ space: 2 }) {
          Text(this.planNameTitle.length > 0 ? this.planNameTitle : '展位方案')
            .id('editor-plan-name')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .accessibilityText('当前展位方案：' + this.planNameTitle)
          Row({ space: 6 }) {
            Text(this.templateSummary)
              .fontSize(11)
              .fontColor(COLOR_MUTED)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(formatObjectCount(this.objectCount))
              .id('object-count')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_PRIMARY)
              .maxLines(1)
              .accessibilityText('当前物件数量：' + this.objectCount.toString() + ' 件')
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 3 }) {
          Text(this.saveLabelNow())
            .id('save-status')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.saveStateColor())
            .backgroundColor(this.saveStateBackground())
            .borderRadius(6)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .maxLines(1)
            .accessibilityText('保存状态：' + this.saveLabelNow())
          Button(this.saveButtonLabelNow())
            .id('save-plan')
            .type(ButtonType.Normal)
            .backgroundColor(COLOR_PRIMARY)
            .fontColor('#FFFFFF')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .height(34)
            .borderRadius(9)
            .width(68)
            .enabled(this.canPressSave())
            .opacity(this.canPressSave() ? 1 : 0.45)
            .accessibilityText('保存当前展位方案')
            .onClick(() => {
              this.handleSaveClick();
            })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 6 })
      .backgroundColor('#FFFFFF')
      .alignItems(VerticalAlign.Center)

      if (this.closing && this.saveState !== 'SaveError') {
        Row({ space: 6 }) {
          Text('●')
            .fontSize(9)
            .fontColor(COLOR_PRIMARY)
          Text('正在保存并返回，请稍候…')
            .fontSize(11)
            .fontColor(COLOR_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .id('closing-state')
        .width('100%')
        .padding({ left: 18, right: 18, top: 4, bottom: 4 })
        .backgroundColor('#E8F2EF')
        .accessibilityText('正在保存并返回，请稍候')
      }

      if (this.message.length > 0) {
        Text(this.message)
          .id('editor-message')
          .fontSize(11)
          .fontColor(COLOR_DANGER)
          .backgroundColor('#FDECEC')
          .width('100%')
          .padding({ left: 18, right: 18, top: 4, bottom: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText('编辑状态：' + this.message)
      }

      if (this.importError.length > 0) {
        Column({ space: 8 }) {
          Text('无法打开展位方案')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_DANGER)
          Text(this.importError)
            .id('editor-import-error')
            .fontSize(13)
            .fontColor(COLOR_TEXT)
            .textAlign(TextAlign.Center)
          Text('请返回方案库并重新打开该方案。')
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .padding(24)
        .justifyContent(FlexAlign.Center)
      } else {
        // A02 object library entry. The B picker opens in a bounded bottom
        // sheet so the weighted Canvas, bounded issues list, toolbars and
        // save/back controls keep their usable sizes near 390vp. Only the
        // picker's own list scrolls, so there is no nested page/list scroll
        // conflict, and opening/closing the sheet never resizes or commits the
        // drag preview.
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('物件库')
              .id('object-catalog')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
              .width('100%')
              .maxLines(1)
              .accessibilityText('物件库')
            Text(this.catalogSummaryText())
              .id('catalog-summary')
              .fontSize(11)
              .fontColor(COLOR_MUTED)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.pickerVisible ? '收起物件库' : '添加物件')
            .id('add-object')
            .type(ButtonType.Normal)
            .backgroundColor(COLOR_PRIMARY)
            .fontColor('#FFFFFF')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(42)
            .borderRadius(10)
            .width(108)
            .enabled(this.canOpenPickerNow())
            .opacity(this.canOpenPickerNow() ? 1 : 0.45)
            .accessibilityText('打开物件库，点选一个物件添加到展位')
            .onClick(() => {
              this.handlePickerToggle();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 6 })
        .bindSheet($$this.pickerVisible, this.pickerSheetBuilder(), {
          height: 560,
          showClose: true,
          dragBar: true,
          backgroundColor: COLOR_PAGE,
          onDisappear: () => {
            this.pickerVisible = false;
          }
        })

        // The canvas keeps a real weighted area (never an overlay), with a
        // generous minimum so the 600x400 cm booth remains readable near 390vp.
        Canvas(this.context)
          .id('editor-canvas')
          .width('100%')
          .layoutWeight(1)
          .constraintSize({ minHeight: 200 })
          .backgroundColor(COLOR_CANVAS)
          .borderRadius(12)
          .enabled(!this.isLocked())
          .accessibilityText('展位编辑画布：' + this.templateSummary +
            '；点按物件可选择或拖动；入口与预留区提醒为教学提示')
          .onReady(() => {
            this.handleReady();
          })
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.handleAreaChange(newValue);
          })
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })

        // Bounded, scrollable issues. Severity is shown separately so warning
        // and error text levels stay distinguishable at a glance.
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(formatLayoutIssueSummary(this.layoutIssues.length))
              .id('layout-issues-title')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.layoutIssues.length === 0 ? COLOR_PRIMARY : COLOR_WARNING)
              .maxLines(1)
            if (this.layoutIssues.length > 0) {
              Text('点按条目定位物件')
                .fontSize(10)
                .fontColor(COLOR_MUTED)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .height(20)
          .alignItems(VerticalAlign.Center)

          if (this.layoutIssues.length > 0) {
            List({ space: 3 }) {
              ForEach(this.layoutIssues, (issue: LayoutIssue, index: number) => {
                ListItem() {
                  Row({ space: 6 }) {
                    Text(formatIssueSeverityLabel(issue.severity))
                      .fontSize(9)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(issue.severity === 'error' ? COLOR_DANGER : COLOR_WARNING)
                      .backgroundColor(issue.severity === 'error' ? '#FADCDC' : '#FFE8C7')
                      .borderRadius(4)
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .width(32)
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                    Column({ space: 1 }) {
                      Text(formatIssueTypeLabel(issue.code) + ' · ' +
                        formatIssueIdsLabel(issue.objectIds))
                        .fontSize(10)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(COLOR_TEXT)
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(issue.message)
                        .fontSize(9)
                        .fontColor(COLOR_MUTED)
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .id(this.issueElementId(issue, index))
                  .width('100%')
                  .height(38)
                  .padding({ left: 6, right: 6 })
                  .backgroundColor(issue.severity === 'error' ? '#FDECEC' : '#FFF7ED')
                  .borderRadius(6)
                  .onClick(() => {
                    this.handleIssueClick(issue);
                  })
                  .accessibilityText(formatIssueSeverityLabel(issue.severity) + '：' +
                    formatIssueTypeLabel(issue.code) + '。' + issue.message +
                    ' 相关物件：' + formatIssueIdsLabel(issue.objectIds))
                }
              }, (issue: LayoutIssue, index: number) => this.issueElementId(issue, index))
            }
            .width('100%')
            .height(82)
            .scrollBar(BarState.Auto)
            .borderRadius(8)

            Text('教学提示：入口/预留区提醒仅用于布局练习，不构成消防或安全合规结论。')
              .id('issue-teaching-note')
              .fontSize(9)
              .fontColor(COLOR_MUTED)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .accessibilityText('教学提示：入口和预留区提醒仅用于布局练习，不构成消防或安全合规结论')
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })

        // Readable selected-object properties. Center remains the committed
        // centre in cm; the drag preview is reported separately and is never
        // written into the committed summary.
        Row() {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(this.hasSelection && this.selectedName.length > 0 ?
                this.selectedName : '未选中物件')
                .id('selection-title')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.hasSelection && this.selectedIssueSeverity.length > 0) {
                Text(this.selectedIssueSeverity === 'error' ? '布局错误' : '布局提醒')
                  .id('selected-issue')
                  .fontSize(9)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.selectedIssueSeverity === 'error' ? COLOR_DANGER : COLOR_WARNING)
                  .backgroundColor(this.selectedIssueSeverity === 'error' ? '#FADCDC' : '#FFE8C7')
                  .borderRadius(5)
                  .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                  .maxLines(1)
              }
              if (this.hasSelection) {
                Text(formatRotationText(this.selectedRotationDeg))
                  .id('selected-rotation')
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_PRIMARY)
                  .backgroundColor('#E8F2EF')
                  .borderRadius(5)
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .maxLines(1)
              }
            }
            .width('100%')

            Text(this.committedSummary)
              .id('selected-summary')
              .fontSize(12)
              .fontColor(COLOR_TEXT)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .accessibilityText('所选物件：' + this.committedSummary)
            Row({ space: 8 }) {
              if (this.hasSelection && this.selectedFootprintText.length > 0) {
                Text(this.selectedFootprintText)
                  .id('selected-footprint')
                  .fontSize(10)
                  .fontColor(COLOR_MUTED)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              Text(this.previewSummary)
                .id('preview-summary')
                .fontSize(10)
                .fontColor(COLOR_MUTED)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .accessibilityText('拖动预览：' + this.previewSummary)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })

        Row({ space: 8 }) {
          Button('撤销')
            .id('undo')
            .type(ButtonType.Normal)
            .backgroundColor(COLOR_BORDER)
            .fontColor(COLOR_TEXT)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(44)
            .borderRadius(10)
            .layoutWeight(1)
            .enabled(this.canUndoNow())
            .opacity(this.canUndoNow() ? 1 : 0.45)
            .accessibilityText('撤销上一步有效编辑')
            .onClick(() => {
              this.handleUndoClick();
            })
          Button('重做')
            .id('redo')
            .type(ButtonType.Normal)
            .backgroundColor(COLOR_BORDER)
            .fontColor(COLOR_TEXT)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(44)
            .borderRadius(10)
            .layoutWeight(1)
            .enabled(this.canRedoNow())
            .opacity(this.canRedoNow() ? 1 : 0.45)
            .accessibilityText('重做已撤销的编辑')
            .onClick(() => {
              this.handleRedoClick();
            })
          Button('删除')
            .id('delete-object')
            .type(ButtonType.Normal)
            .backgroundColor(COLOR_ACCENT)
            .fontColor(COLOR_TEXT)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(44)
            .borderRadius(10)
            .layoutWeight(1)
            .enabled(this.canDeleteNow())
            .opacity(this.canDeleteNow() ? 1 : 0.45)
            .accessibilityText('删除选中的物件')
            .onClick(() => {
              this.handleDeleteClick();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 2 })

        Row({ space: 8 }) {
          Button('旋转 90°')
            .id('rotate-object')
            .type(ButtonType.Normal)
            .backgroundColor(COLOR_PRIMARY)
            .fontColor('#FFFFFF')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(44)
            .borderRadius(10)
            .layoutWeight(1)
            .enabled(this.canRotateNow())
            .opacity(this.canRotateNow() ? 1 : 0.45)
            .accessibilityText('将选中的物件顺时针旋转九十度')
            .onClick(() => {
              this.handleRotateClick();
            })
          Button('回到中心')
            .id('center-object')
            .type(ButtonType.Normal)
            .backgroundColor(COLOR_ACCENT)
            .fontColor(COLOR_TEXT)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(44)
            .borderRadius(10)
            .layoutWeight(1)
            .enabled(this.canCenterNow())
            .opacity(this.canCenterNow() ? 1 : 0.45)
            .accessibilityText('将选中的物件移动到展位中心')
            .onClick(() => {
              this.handleCenterClick();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 2 })

        Text(this.statusText)
          .id('editor-state')
          .fontSize(11)
          .fontColor(COLOR_TEXT)
          .width('100%')
          .height(38)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 12, right: 12, top: 4, bottom: 6 })
          .accessibilityText('操作状态：' + this.statusText)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_PAGE)
  }

  /**
   * Bounded picker sheet. The picker receives the real catalog snapshot and is
   * disabled while locked or dragging. A failed add stays in the sheet with its
   * truthful reason; the card highlight alone is never treated as success.
   */
  @Builder
  pickerSheetBuilder() {
    Column({ space: 8 }) {
      if (this.pickerMessage.length > 0) {
        Text(this.pickerMessage)
          .id('picker-add-message')
          .fontSize(12)
          .fontColor(COLOR_DANGER)
          .backgroundColor('#FDECEC')
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(8)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText('添加结果：' + this.pickerMessage)
      }
      ObjectCatalogPicker({
        items: this.catalogItems,
        disabled: this.pickerDisabledNow(),
        onSelect: (catalogId: string) => {
          this.handleCatalogSelection(catalogId);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_PAGE)
  }

  // ------------------------------------------------------------------
  // Save/back presentation
  // ------------------------------------------------------------------

  private isLocked(): boolean {
    return !this.editorReady || this.closing;
  }

  private canPressSave(): boolean {
    return canSaveAction(this.isLocked(), this.saveBusy, this.saveState);
  }

  private canUndoNow(): boolean {
    return canUndoAction(this.canUndo, this.dragging, this.isLocked());
  }

  private canRedoNow(): boolean {
    return canRedoAction(this.canRedo, this.dragging, this.isLocked());
  }

  private canDeleteNow(): boolean {
    return canDeleteAction(this.hasSelection, this.dragging, this.isLocked());
  }

  private canRotateNow(): boolean {
    return canRotateAction(this.hasSelection, this.dragging, this.isLocked());
  }

  private canCenterNow(): boolean {
    return canCenterAction(this.hasSelection, this.dragging, this.isLocked());
  }

  private saveLabelNow(): string {
    return formatSaveStateLabel(this.saveState, this.saveBusy, this.closing);
  }

  private saveButtonLabelNow(): string {
    return formatSaveButtonLabel(this.saveState, this.saveBusy, this.closing);
  }

  private saveStateColor(): string {
    if (this.saveState === 'SaveError') {
      return COLOR_DANGER;
    }
    if (this.saveState === 'Dirty' && !this.closing) {
      return COLOR_WARNING;
    }
    return COLOR_PRIMARY;
  }

  private saveStateBackground(): string {
    if (this.saveState === 'SaveError') {
      return '#FDECEC';
    }
    if (this.saveState === 'Dirty' && !this.closing) {
      return '#FFF7ED';
    }
    return '#E8F2EF';
  }

  private handleSaveClick(): void {
    if (!this.canPressSave()) {
      return;
    }
    this.onSave();
  }

  private handleBackClick(): void {
    if (this.closing) {
      return;
    }
    this.onBack();
  }

  // ------------------------------------------------------------------
  // Object library (B picker -> existing legal-centre/add path)
  // ------------------------------------------------------------------

  private catalogSummaryText(): string {
    return this.catalogItems.length.toString() + ' 件可选 · 真实目录尺寸';
  }

  private pickerDisabledNow(): boolean {
    return isPickerDisabled(this.isLocked(), this.dragging);
  }

  private canOpenPickerNow(): boolean {
    return !this.pickerDisabledNow();
  }

  private handlePickerToggle(): void {
    if (this.pickerVisible) {
      this.pickerVisible = false;
      return;
    }
    if (!this.canOpenPickerNow()) {
      this.statusText = this.dragging ? '拖动中不能添加物件' : '当前不可添加物件';
      return;
    }
    this.pickerMessage = '';
    this.pickerVisible = true;
  }

  /**
   * One enabled picker selection performs exactly one add attempt through the
   * shared adapter. Success closes the sheet and reports the committed result;
   * failure keeps it open with the truthful reason. The picker's local highlight
   * is never interpreted as a successful add.
   */
  private handleCatalogSelection(catalogId: string): void {
    if (this.pickerDisabledNow()) {
      this.pickerMessage = '添加失败：当前不可添加物件，请先结束拖动或等待操作完成';
      return;
    }
    const attempt: CatalogAddAttempt =
      addCatalogObject(this.controller, catalogId, false);
    if (attempt.code === 'OK' && attempt.addedObject !== null &&
      attempt.catalogItem !== null) {
      this.statusText = '已添加' + attempt.catalogItem.name + '，中心 (' +
        formatCm(attempt.addedObject.centerX) + ', ' +
        formatCm(attempt.addedObject.centerY) + ') cm';
      this.pickerMessage = '';
      this.pickerVisible = false;
    } else {
      this.statusText = attempt.message;
      this.pickerMessage = attempt.message;
    }
    this.refreshUi();
    this.drawCanvas();
  }

  // ------------------------------------------------------------------
  // State and viewport
  // ------------------------------------------------------------------

  private handleReady(): void {
    if (!this.editorReady) {
      return;
    }
    this.canvasReady = true;
    this.refreshViewport();
    this.drawCanvas();
  }

  private handleAreaChange(newValue: Area): void {
    if (!this.editorReady) {
      return;
    }
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
    if (!this.editorReady) {
      return;
    }
    const template: BoothTemplate = this.controller.getTemplate();
    this.templateSummary = template.name + ' ' + formatMeters(template.widthCm) +
      'm×' + formatMeters(template.heightCm) + 'm';
    // Recompute from committed state on every refresh; preview/selection never
    // feed the validator, so this panel cannot go stale.
    this.layoutIssues = this.controller.getLayoutIssues();

    const committed: PlacedObject[] = this.controller.getObjects();
    this.objectCount = committed.length;

    const selected: PlacedObject | null = this.controller.getSelectedObject();
    if (selected === null) {
      this.hasSelection = false;
      this.selectedId = '';
      this.selectedName = '';
      this.selectedFootprintText = '';
      this.selectedRotationDeg = 0;
      this.selectedIssueSeverity = '';
      this.committedSummary = '点按画布中的物件进行选择或拖动';
    } else {
      this.hasSelection = true;
      this.selectedId = selected.id;
      this.selectedName = this.catalogName(selected.catalogId);
      this.committedSummary = formatSelectedCenterText(selected.centerX, selected.centerY);
      const footprint = this.controller.getFootprint(selected);
      if (footprint.code === 'OK' && footprint.data !== undefined) {
        this.selectedFootprintText = formatFootprintText(footprint.data.width,
          footprint.data.height);
      } else {
        this.selectedFootprintText = '占位尺寸未知';
      }
      this.selectedRotationDeg = selected.rotation;
      // Presentation-only link from the selected object to its highest
      // severity issue. It is recomputed from committed state on every
      // refresh and never feeds validator, history or persistence.
      this.selectedIssueSeverity =
        findIssueSeverityForObject(this.layoutIssues, selected.id);
    }

    const preview: PlacedObject | null = this.controller.getPreviewObject();
    if (preview === null) {
      this.previewSummary = '预览：无';
    } else {
      this.previewSummary = '预览：中心 (' + formatCm(preview.centerX) + ', ' +
        formatCm(preview.centerY) + ') cm（未提交）';
    }
    this.dragging = this.controller.isDragging();
    this.canUndo = this.controller.canUndo();
    this.canRedo = this.controller.canRedo();
    this.notifyFormalChangeIfNeeded();
  }

  /**
   * Reports a formal snapshot only when the controller's independent session
   * revision advanced. updatedAt is persisted metadata only and may not change
   * at very large finite values. Selection, preview, viewport resize and
   * save-state rebuilds never advance the revision, so they never reach the
   * parent.
   */
  private notifyFormalChangeIfNeeded(): void {
    if (!this.editorReady) {
      return;
    }
    const exported = this.controller.exportPlan();
    if (exported.code !== 'OK' || exported.data === undefined) {
      return;
    }
    if (!this.changeNotifier.shouldNotify(this.controller.getChangeRevision())) {
      return;
    }
    this.onChanged(exported.data);
  }

  private catalogName(catalogId: string): string {
    const result = this.controller.getCatalogItem(catalogId);
    if (result.code === 'OK' && result.data !== undefined) {
      return result.data.name;
    }
    return catalogId;
  }

  /** Stable clickable id: issue-<code>-<objectIds>; empty ids get an index. */
  private issueElementId(issue: LayoutIssue, index: number): string {
    let elementId: string = 'issue-' + issue.code;
    for (let i = 0; i < issue.objectIds.length; i++) {
      elementId += '-' + issue.objectIds[i];
    }
    if (issue.objectIds.length === 0) {
      elementId += '-none-' + index;
    }
    return elementId;
  }

  /** Selects the first affected committed object; never shifts any object. */
  private handleIssueClick(issue: LayoutIssue): void {
    if (this.isLocked()) {
      return;
    }
    if (this.dragging) {
      this.statusText = '拖动中不能切换选中，请先松开手指';
      return;
    }
    if (issue.objectIds.length === 0) {
      this.statusText = '该提醒不对应具体物件，请检查展位或数据';
      this.refreshUi();
      this.drawCanvas();
      return;
    }
    const targetId: string = issue.objectIds[0];
    const selected = this.controller.selectObject(targetId);
    if (selected.code === 'OK') {
      this.statusText = '已选中 ' + targetId + '，请按提醒调整位置';
    } else {
      this.statusText = '该提醒对应的物件已不存在';
    }
    this.refreshUi();
    this.drawCanvas();
  }

  // ------------------------------------------------------------------
  // Toolbar actions
  // ------------------------------------------------------------------

  private handleDeleteClick(): void {
    if (this.isLocked()) {
      return;
    }
    if (this.dragging) {
      this.statusText = '拖动中不能删除物件';
      return;
    }
    if (this.selectedId === '') {
      this.statusText = '请先选择一个物件再删除';
      return;
    }
    const result = this.controller.removeObject(this.selectedId);
    if (result.code === 'OK') {
      this.statusText = '已删除所选物件；可撤销恢复';
    } else if (result.code === 'NOT_FOUND') {
      this.statusText = '删除失败：所选物件不存在';
    } else {
      this.statusText = '删除失败：' + result.message;
    }
    this.refreshUi();
    this.drawCanvas();
  }

  private handleUndoClick(): void {
    if (this.isLocked()) {
      return;
    }
    if (this.dragging) {
      this.statusText = '拖动中不能撤销';
      return;
    }
    const result = this.controller.undo();
    if (result.code === 'OK') {
      this.statusText = '已撤销上一步有效编辑';
    } else if (result.code === 'NO_HISTORY') {
      this.statusText = '没有可撤销的操作';
    } else {
      this.statusText = '撤销失败：' + result.message;
    }
    this.refreshUi();
    this.drawCanvas();
  }

  private handleRedoClick(): void {
    if (this.isLocked()) {
      return;
    }
    if (this.dragging) {
      this.statusText = '拖动中不能重做';
      return;
    }
    const result = this.controller.redo();
    if (result.code === 'OK') {
      this.statusText = '已重做上一步撤销的编辑';
    } else if (result.code === 'NO_HISTORY') {
      this.statusText = '没有可重做的操作';
    } else {
      this.statusText = '重做失败：' + result.message;
    }
    this.refreshUi();
    this.drawCanvas();
  }

  private handleRotateClick(): void {
    if (this.isLocked()) {
      return;
    }
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
    if (this.isLocked()) {
      return;
    }
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
    if (this.isLocked()) {
      return;
    }
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
    if (!this.editorReady || !this.canvasReady ||
      this.canvasWidthVp <= 0 || this.canvasHeightVp <= 0) {
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
      this.context.fillStyle = '#FFF8EF';
      this.context.fillRect(screen.x, screen.y, screen.width, screen.height);
      this.context.strokeStyle = COLOR_ACCENT;
      this.context.lineWidth = 1.2;
      this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
      if (screen.width >= 42 && screen.height >= 12) {
        const label: string = screen.width >= 96 ? '预留区（教学提示）' : '预留区';
        const fontSize: number = Math.max(8, Math.min(10, screen.height * 0.4));
        this.context.font = fontSize.toFixed(0) + 'px sans-serif';
        this.context.fillStyle = COLOR_WARNING;
        this.context.textAlign = 'center';
        this.context.textBaseline = 'middle';
        this.context.fillText(label, screen.x + screen.width / 2, screen.y + screen.height / 2);
      }
    }
  }

  private drawWalls(template: BoothTemplate): void {
    this.context.strokeStyle = COLOR_PRIMARY;
    this.context.lineWidth = 6;
    for (let i = 0; i < template.wallSides.length; i++) {
      this.drawSideLine(template.wallSides[i], template);
    }

    const dashed: number[] = [7, 5];
    this.context.setLineDash(dashed);
    this.context.strokeStyle = COLOR_ACCENT;
    this.context.lineWidth = 2.5;
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
      // Unknown catalog ids have no real dimensions or visual. Reject them
      // rather than inventing a size; the committed object stays untouched.
      const visual: ObjectVisualDraw | null =
        resolveObjectVisualForCatalogId(this.controller, this.viewport, object);
      if (visual === null) {
        continue;
      }
      // The procedural top view owns the object body. Its extents are the
      // UNROTATED catalog sizes scaled once, and rotation is applied once
      // inside drawObjectVisual; the rotated footprint is never re-rotated.
      drawObjectVisual(this.context, visual.imageKey, visual.centerX,
        visual.centerY, visual.widthVp, visual.heightVp, visual.rotation);

      const footprint = this.controller.getFootprint(object);
      if (footprint.code !== 'OK' || footprint.data === undefined) {
        continue;
      }
      const screen: Rect | null = this.worldRectToScreen(footprint.data);
      if (screen === null) {
        continue;
      }
      const selected: boolean = this.selectedId === object.id;
      const strokeColor: string = selected ? this.selectedOutlineColor() : COLOR_PRIMARY;
      this.drawObjectLabel(object, screen);
      this.drawOrientationMarker(object.rotation, screen, strokeColor);
    }
  }

  /** Presentation-only emphasis linked to the selected object's issues. */
  private selectedOutlineColor(): string {
    if (this.selectedIssueSeverity === 'error') {
      return COLOR_DANGER;
    }
    if (this.selectedIssueSeverity === 'warning') {
      return COLOR_WARNING;
    }
    return COLOR_ACCENT;
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
    const outlineColor: string = this.selectedOutlineColor();
    this.context.strokeStyle = outlineColor;
    this.context.lineWidth = 3;
    this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
    this.drawSelectionHandles(screen, outlineColor);
  }

  /** Four compact corner handles make the selection outline easy to spot. */
  private drawSelectionHandles(screen: Rect, color: string): void {
    const size: number = 5;
    const offset: number = size / 2;
    this.context.fillStyle = color;
    this.context.fillRect(screen.x - offset, screen.y - offset, size, size);
    this.context.fillRect(screen.x + screen.width - offset, screen.y - offset, size, size);
    this.context.fillRect(screen.x - offset, screen.y + screen.height - offset, size, size);
    this.context.fillRect(screen.x + screen.width - offset,
      screen.y + screen.height - offset, size, size);
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
    this.context.fillStyle = '#FFF3E4';
    this.context.fillRect(screen.x, screen.y, screen.width, screen.height);
    const dashed: number[] = [6, 4];
    this.context.setLineDash(dashed);
    this.context.strokeStyle = COLOR_ACCENT;
    this.context.lineWidth = 2.5;
    this.context.strokeRect(screen.x, screen.y, screen.width, screen.height);
    const noDash: number[] = [];
    this.context.setLineDash(noDash);
    this.context.beginPath();
    this.context.arc(screen.x + screen.width / 2, screen.y + screen.height / 2,
      2.5, 0, Math.PI * 2);
    this.context.fillStyle = COLOR_ACCENT;
    this.context.fill();
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
        this.context.fillText('开放 →', anchor.x + 8, anchor.y);
      }
    }
    if (hasSide(template.openSides, 'left')) {
      const anchor: Point | null = this.worldPointToScreen(0, template.heightCm / 2);
      if (anchor !== null) {
        this.context.font = '11px sans-serif';
        this.context.fillStyle = COLOR_ACCENT;
        this.context.textAlign = 'right';
        this.context.textBaseline = 'middle';
        this.context.fillText('← 开放', anchor.x - 8, anchor.y);
      }
    }
    if (hasSide(template.openSides, 'top')) {
      const anchor: Point | null = this.worldPointToScreen(template.widthCm / 2, 0);
      if (anchor !== null) {
        this.context.font = '11px sans-serif';
        this.context.fillStyle = COLOR_ACCENT;
        this.context.textAlign = 'center';
        this.context.textBaseline = 'bottom';
        this.context.fillText('↑ 开放', anchor.x, anchor.y - 6);
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
