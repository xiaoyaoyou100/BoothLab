/**
 * BoothLab M3-B01 object catalog picker.
 *
 * Presentation-only component: the parent owns plans and passes the catalog
 * items it wants to expose. A tap produces exactly one `onSelect(catalogId)`
 * call; the parent validates the id, finds a legal centre and calls the
 * existing add path. This component never imports Controller, Repository or
 * Preferences and never mutates the caller's items.
 *
 * Category filtering and the highlighted card are local presentation state.
 * `disabled` (for example while dragging or while the editor is locked)
 * suppresses selection callbacks and is shown explicitly on every card.
 * Each card renders the shared procedural top view from ObjectVisuals.
 */

import { CatalogItem, Rotation } from '../../model/BoothModels';
import { drawObjectVisual } from './ObjectVisuals';

const COLOR_PAGE: string = '#F7F8F4';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_MUTED: string = '#6B7C80';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_SELECTED_FILL: string = '#E8F2EF';
const COLOR_DISABLED_FILL: string = '#EEF1EF';

const ALL_CATEGORY: string = '全部';
const UNCATEGORIZED: string = '未分类';
const NO_ROTATION: Rotation = 0;
const PREVIEW_WIDTH_VP: number = 72;
const PREVIEW_HEIGHT_VP: number = 44;
const CARD_HEIGHT_VP: number = 60;
const CARD_GAP_VP: number = 8;
const MAX_LIST_HEIGHT_VP: number = 304;

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

function isPositiveNumber(value: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function formatDimension(value: number): string {
  if (!isPositiveNumber(value)) {
    return '—';
  }
  if (Number.isInteger(value)) {
    return value.toString();
  }
  return value.toFixed(1);
}

/**
 * One procedural preview. The Canvas has a fixed touch-friendly size; the
 * object is scaled uniformly from its real catalog aspect ratio solely for
 * presentation, so ObjectVisuals still receives vp extents and no cm values.
 */
@Component
struct ObjectCatalogVisual {
  @Prop @Watch('handleItemChanged') item: CatalogItem;

  private context: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasWidthVp: number = 0;
  private canvasHeightVp: number = 0;
  private canvasReady: boolean = false;

  private handleItemChanged(): void {
    this.redraw();
  }

  build() {
    Canvas(this.context)
      .width(PREVIEW_WIDTH_VP)
      .height(PREVIEW_HEIGHT_VP)
      .backgroundColor(COLOR_PAGE)
      .borderRadius(8)
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

  private redraw(): void {
    if (!this.canvasReady || this.canvasWidthVp <= 0 || this.canvasHeightVp <= 0) {
      return;
    }
    this.context.clearRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    this.context.fillStyle = COLOR_PAGE;
    this.context.fillRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);

    if (this.item === null || this.item === undefined) {
      return;
    }
    const imageKey: string = typeof this.item.imageKey === 'string' ? this.item.imageKey : '';

    let footprintWidth: number = PREVIEW_WIDTH_VP * 0.72;
    let footprintHeight: number = PREVIEW_HEIGHT_VP * 0.6;
    if (isPositiveNumber(this.item.widthCm) && isPositiveNumber(this.item.heightCm)) {
      const maxWidth: number = this.canvasWidthVp - 12;
      const maxHeight: number = this.canvasHeightVp - 10;
      const scale: number = Math.min(maxWidth / this.item.widthCm, maxHeight / this.item.heightCm);
      footprintWidth = this.item.widthCm * scale;
      footprintHeight = this.item.heightCm * scale;
    }
    if (!(footprintWidth > 0) || !(footprintHeight > 0)) {
      return;
    }
    drawObjectVisual(this.context, imageKey,
      this.canvasWidthVp * 0.5, this.canvasHeightVp * 0.5,
      footprintWidth, footprintHeight, NO_ROTATION);
  }
}

@Component
export struct ObjectCatalogPicker {
  @Prop items: CatalogItem[] = [];
  @Prop disabled: boolean = false;
  onSelect: (catalogId: string) => void = () => {};

  @State selectedCatalogId: string = '';
  @State activeCategory: string = ALL_CATEGORY;

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('添加物件')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
            .accessibilityText('物件库标题')
          Text(this.summaryText())
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .accessibilityText('物件库信息：' + this.summaryText())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.disabled ? '已锁定' : '点选添加')
          .fontSize(11)
          .fontColor(COLOR_TEXT)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.disabled ? COLOR_DISABLED_FILL : COLOR_ACCENT)
          .borderRadius(12)
          .accessibilityText(this.disabled ? '物件库已锁定' : '点选卡片添加物件')
      }
      .width('100%')

      if (this.safeItems().length === 0) {
        Column({ space: 4 }) {
          Text('暂无可添加的物件')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT)
            .accessibilityText('暂无可添加的物件')
          Text('请先在物件目录中配置可用物件。')
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .textAlign(TextAlign.Center)
            .accessibilityText('物件库为空提示')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(COLOR_CARD)
        .borderRadius(10)
        .border({ width: 1, color: COLOR_BORDER })
        .id('catalog-empty')
      } else {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.categoryOptions(), (category: string) => {
              Button(category)
                .id('catalog-category-' + category)
                .type(ButtonType.Normal)
                .height(40)
                .padding({ left: 14, right: 14 })
                .fontSize(13)
                .fontColor(this.activeFilter() === category ? '#FFFFFF' : COLOR_TEXT)
                .backgroundColor(this.activeFilter() === category ? COLOR_PRIMARY : COLOR_CARD)
                .borderRadius(10)
                .border({ width: 1, color: COLOR_BORDER })
                .enabled(!this.disabled)
                .opacity(this.disabled ? 0.55 : 1)
                .onClick(() => {
                  if (!this.disabled) {
                    this.activeCategory = category;
                  }
                })
                .accessibilityText('筛选物件分类：' + category +
                  (this.activeFilter() === category ? '，已选中' : ''))
            }, (category: string): string => category)
          }
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        if (this.visibleItems().length === 0) {
          Column({ space: 4 }) {
            Text('该分类暂无物件')
              .fontSize(15)
              .fontColor(COLOR_TEXT)
              .accessibilityText('当前分类暂无物件')
            Text('请选择其他分类。')
              .fontSize(12)
              .fontColor(COLOR_MUTED)
              .accessibilityText('请选择其他分类')
          }
          .width('100%')
          .padding(20)
          .backgroundColor(COLOR_CARD)
          .borderRadius(10)
          .border({ width: 1, color: COLOR_BORDER })
          .id('catalog-filter-empty')
        } else {
          List({ space: CARD_GAP_VP }) {
            ForEach(this.visibleItems(), (item: CatalogItem) => {
              ListItem() {
                this.itemCard(item)
              }
              .width('100%')
            }, (item: CatalogItem): string => item.id)
          }
          .width('100%')
          .height(this.listHeight())
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .id('catalog-item-list')
        }
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(COLOR_PAGE)
    .borderRadius(12)
    .id('object-catalog-picker')
  }

  @Builder
  itemCard(item: CatalogItem) {
    Row({ space: 10 }) {
      ObjectCatalogVisual({ item: item })

      Column({ space: 3 }) {
        Text(this.displayName(item))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.displayCategory(item))
          .fontSize(11)
          .fontColor(COLOR_PRIMARY)
          .width('100%')
        Text(this.dimensionText(item))
          .fontSize(11)
          .fontColor(COLOR_MUTED)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('＋')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT)
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.disabled ? COLOR_DISABLED_FILL : COLOR_ACCENT)
        .borderRadius(15)
        .accessibilityText(this.disabled ? '当前不可添加' : '添加' + this.displayName(item))
    }
    .width('100%')
    .height(CARD_HEIGHT_VP)
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(this.selectedCatalogId === item.id ? COLOR_SELECTED_FILL : COLOR_CARD)
    .borderRadius(10)
    .border({
      width: this.selectedCatalogId === item.id ? 2 : 1,
      color: this.selectedCatalogId === item.id ? COLOR_PRIMARY : COLOR_BORDER
    })
    .enabled(!this.disabled)
    .opacity(this.disabled ? 0.55 : 1)
    .onClick(() => {
      this.requestSelect(item);
    })
    .accessibilityText(this.cardAccessibilityText(item))
    .id('catalog-item-' + item.id)
  }

  /**
   * Returns renderable items without mutating the caller's array. Entries with
   * no usable id are skipped and duplicate ids are shown only once so ForEach
   * keys stay unique.
   */
  private safeItems(): CatalogItem[] {
    const result: CatalogItem[] = [];
    if (!Array.isArray(this.items)) {
      return result;
    }
    const seenIds: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: CatalogItem = this.items[i];
      if (item === null || item === undefined || typeof item !== 'object') {
        continue;
      }
      if (typeof item.id !== 'string' || item.id.length === 0) {
        continue;
      }
      let duplicate: boolean = false;
      for (let j = 0; j < seenIds.length; j++) {
        if (seenIds[j] === item.id) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        seenIds.push(item.id);
        result.push(item);
      }
    }
    return result;
  }

  private categoryFor(item: CatalogItem): string {
    if (typeof item.category === 'string' && item.category.length > 0) {
      return item.category;
    }
    return UNCATEGORIZED;
  }

  private categoryOptions(): string[] {
    const result: string[] = [ALL_CATEGORY];
    const items: CatalogItem[] = this.safeItems();
    const seen: string[] = [];
    for (let i = 0; i < items.length; i++) {
      const category: string = this.categoryFor(items[i]);
      let found: boolean = false;
      for (let j = 0; j < seen.length; j++) {
        if (seen[j] === category) {
          found = true;
          break;
        }
      }
      if (!found) {
        seen.push(category);
        result.push(category);
      }
    }
    return result;
  }

  private activeFilter(): string {
    const options: string[] = this.categoryOptions();
    for (let i = 0; i < options.length; i++) {
      if (options[i] === this.activeCategory) {
        return this.activeCategory;
      }
    }
    return ALL_CATEGORY;
  }

  private visibleItems(): CatalogItem[] {
    const items: CatalogItem[] = this.safeItems();
    const active: string = this.activeFilter();
    if (active === ALL_CATEGORY) {
      return items;
    }
    const filtered: CatalogItem[] = [];
    for (let i = 0; i < items.length; i++) {
      if (this.categoryFor(items[i]) === active) {
        filtered.push(items[i]);
      }
    }
    return filtered;
  }

  private listHeight(): number {
    const count: number = this.visibleItems().length;
    if (count <= 0) {
      return CARD_HEIGHT_VP;
    }
    const natural: number = count * CARD_HEIGHT_VP + (count - 1) * CARD_GAP_VP;
    return Math.min(MAX_LIST_HEIGHT_VP, natural);
  }

  private summaryText(): string {
    const items: CatalogItem[] = this.safeItems();
    let text: string = items.length.toString() + ' 件可选';
    if (this.selectedCatalogId.length > 0) {
      for (let i = 0; i < items.length; i++) {
        if (items[i].id === this.selectedCatalogId) {
          text = text + ' · 已选 ' + this.displayName(items[i]);
          break;
        }
      }
    }
    return text;
  }

  private displayName(item: CatalogItem): string {
    if (typeof item.name === 'string' && item.name.length > 0) {
      return item.name;
    }
    return '未命名物件';
  }

  private displayCategory(item: CatalogItem): string {
    return this.categoryFor(item);
  }

  private dimensionText(item: CatalogItem): string {
    if (!isPositiveNumber(item.widthCm) || !isPositiveNumber(item.heightCm)) {
      return '尺寸未知';
    }
    return formatDimension(item.widthCm) + ' × ' + formatDimension(item.heightCm) + ' cm';
  }

  private cardAccessibilityText(item: CatalogItem): string {
    let text: string = this.displayName(item) + '，' + this.displayCategory(item) +
      '，尺寸 ' + this.dimensionText(item);
    if (this.selectedCatalogId === item.id) {
      text = text + '，当前高亮';
    }
    if (this.disabled) {
      text = text + '，当前不可添加';
    } else {
      text = text + '，点按添加一个';
    }
    return text;
  }

  private requestSelect(item: CatalogItem): void {
    if (this.disabled) {
      return;
    }
    if (item === null || item === undefined || typeof item.id !== 'string' || item.id.length === 0) {
      return;
    }
    this.selectedCatalogId = item.id;
    this.onSelect(item.id);
  }
}
