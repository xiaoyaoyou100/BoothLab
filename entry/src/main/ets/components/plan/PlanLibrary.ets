/**
 * PlanLibrary (M3-B02 UI).
 *
 * Presentation-only saved-plan library with BoothLab branding. The parent
 * (Index/A) owns the repository and Preferences, resolves promises, updates
 * `plans`, and reports results through `message`.
 *
 * External contract is unchanged from the frozen M2/M3 contract:
 *   onCreate(name, templateId) when the create button is pressed,
 *   onOpen(planId) when a saved plan is opened,
 *   onDelete(planId, confirmed) after the AlertDialog decision.
 *
 * All plan data rendered here comes from the repository snapshot supplied by
 * the parent; there is no demo/fake plan data. Name trimming is preserved and
 * the original business layer remains responsible for name/template validity.
 */

import { BoothPlan, BoothTemplate } from '../../model/BoothModels';
import { getTemplateById, listTemplates } from '../../catalog/BoothTemplates';
import { PlanThumbnail } from './PlanThumbnail';
import { TemplateCard } from './TemplateCard';

const COLOR_PAGE: string = '#F7F8F4';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_MUTED: string = '#6B7C80';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_DANGER: string = '#B23A2E';
const COLOR_SELECTED_TINT: string = '#E8F2EF';

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

@Component
export struct PlanLibrary {
  @Prop plans: BoothPlan[] = [];
  onCreate: (name: string, templateId: string) => void = () => {};
  onOpen: (planId: string) => void = () => {};
  onDelete: (planId: string, confirmed: boolean) => void = () => {};
  @Prop busy: boolean = false;
  @Prop message: string = '';

  @State planName: string = '';
  @State selectedTemplateId: string = 'standard';
  @State templates: BoothTemplate[] = [];

  aboutToAppear(): void {
    const available: BoothTemplate[] = listTemplates();
    this.templates = available;
    if (this.templates.length > 0) {
      let selectedFound: boolean = false;
      for (let i = 0; i < this.templates.length; i++) {
        if (this.templates[i].id === this.selectedTemplateId) {
          selectedFound = true;
          break;
        }
      }
      if (!selectedFound) {
        this.selectedTemplateId = this.templates[0].id;
      }
    }
  }

  build() {
    Column({ space: 8 }) {
      this.brandHeader()

      if (this.message.length > 0) {
        Row({ space: 8 }) {
          Row()
            .width(3)
            .height(30)
            .backgroundColor(COLOR_ACCENT)
            .borderRadius(2)
          Text(this.message)
            .fontSize(12)
            .fontColor(COLOR_TEXT)
            .layoutWeight(1)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .accessibilityText('方案库状态：' + this.message)
        }
        .id('library-message')
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor('#FFF7EA')
        .borderRadius(10)
        .border({ width: 1, color: COLOR_ACCENT })
      }

      Column({ space: 6 }) {
        Text('新建展位方案')
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
          .accessibilityText('新建展位方案')

        Text('输入名称并选择真实展位模板，创建后可继续编辑。')
          .width('100%')
          .fontSize(11)
          .fontColor(COLOR_MUTED)

        TextInput({ placeholder: '展位方案名称（1-30 个字符）', text: this.planName })
          .id('plan-name-input')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor(COLOR_TEXT)
          .backgroundColor(COLOR_CARD)
          .borderRadius(10)
          .border({ width: 1, color: COLOR_BORDER })
          .enabled(!this.busy)
          .opacity(this.busy ? 0.55 : 1)
          .onChange((value: string) => {
            this.planName = value;
          })
          .accessibilityText('展位方案名称输入框，输入 1 到 30 个字符')

        Text('展位模板')
          .width('100%')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT)
          .margin({ top: 2 })

        if (this.templates.length === 0) {
          Text('暂无可用展位模板')
            .width('100%')
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .padding(12)
            .textAlign(TextAlign.Center)
            .backgroundColor(COLOR_CARD)
            .borderRadius(10)
            .border({ width: 1, color: COLOR_BORDER })
            .accessibilityText('暂无可用展位模板')
        } else {
          Row({ space: 8 }) {
            ForEach(this.templates, (template: BoothTemplate) => {
              Column() {
                TemplateCard({
                  template: template,
                  selected: this.selectedTemplateId === template.id,
                  disabled: this.busy,
                  onSelect: (templateId: string): void => {
                    if (!this.busy) {
                      this.selectedTemplateId = templateId;
                    }
                  }
                })
              }
              .layoutWeight(1)
            }, (template: BoothTemplate): string => template.id)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }

        Button(this.busy ? '处理中…' : '新建展位方案')
          .id('create-plan')
          .type(ButtonType.Normal)
          .width('100%')
          .height(42)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(10)
          .enabled(!this.busy)
          .opacity(this.busy ? 0.45 : 1)
          .onClick(() => {
            if (this.busy) {
              return;
            }
            // Trim is intentionally preserved; validation stays in the
            // original business layer.
            this.onCreate(this.planName.trim(), this.selectedTemplateId);
          })
          .accessibilityText('使用当前名称和模板新建展位方案')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(COLOR_CARD)
      .borderRadius(14)
      .border({ width: 1, color: COLOR_BORDER })

      Row({ space: 8 }) {
        Text('已保存方案')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
          .accessibilityText('已保存展位方案')
        Text(this.plans.length.toString())
          .fontSize(11)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(COLOR_SELECTED_TINT)
          .borderRadius(8)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .accessibilityText('共 ' + this.plans.length.toString() + ' 个方案')
        Blank()
      }
      .id('plan-count')
      .width('100%')

      if (this.plans.length === 0) {
        Column({ space: 4 }) {
          Text('还没有展位方案')
            .fontSize(15)
            .fontColor(COLOR_TEXT)
            .accessibilityText('方案库为空')
          Text('在上方输入名称、选择模板后，点击“新建展位方案”。')
            .fontSize(12)
            .fontColor(COLOR_MUTED)
            .textAlign(TextAlign.Center)
            .accessibilityText('新建展位方案提示')
        }
        .width('100%')
        .padding(18)
        .backgroundColor(COLOR_CARD)
        .borderRadius(12)
        .border({ width: 1, color: COLOR_BORDER })
        .id('plan-empty')
      } else {
        List({ space: 8 }) {
          ForEach(this.plans, (plan: BoothPlan) => {
            ListItem() {
              Column({ space: 7 }) {
                PlanThumbnail({ plan: plan })
                Row({ space: 6 }) {
                  Column({ space: 2 }) {
                    Text(plan.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(COLOR_TEXT)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .accessibilityText('展位方案名称：' + plan.name)
                    Text(this.planSummary(plan))
                      .fontSize(11)
                      .fontColor(COLOR_MUTED)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .accessibilityText('方案信息：' + this.planSummary(plan))
                    Text('更新 ' + this.formatUpdatedAt(plan.updatedAt))
                      .fontSize(10)
                      .fontColor(COLOR_MUTED)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .accessibilityText('更新时间：' + this.formatUpdatedAt(plan.updatedAt))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .accessibilityText('展位方案：' + plan.name + '，模板 ' +
                    this.templateName(plan.templateId) + '，共 ' +
                    plan.objects.length.toString() + ' 件物件，更新于 ' +
                    this.formatUpdatedAt(plan.updatedAt))

                  Button('打开')
                    .id('open-plan-' + plan.id)
                    .type(ButtonType.Normal)
                    .width(54)
                    .height(34)
                    .padding(0)
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .backgroundColor(COLOR_PRIMARY)
                    .borderRadius(8)
                    .enabled(!this.busy)
                    .opacity(this.busy ? 0.45 : 1)
                    .onClick(() => {
                      if (!this.busy) {
                        this.onOpen(plan.id);
                      }
                    })
                    .accessibilityText('打开展位方案：' + plan.name)

                  Button('删除')
                    .id('delete-plan-' + plan.id)
                    .type(ButtonType.Normal)
                    .width(54)
                    .height(34)
                    .padding(0)
                    .fontSize(13)
                    .fontColor(COLOR_DANGER)
                    .backgroundColor(COLOR_CARD)
                    .borderRadius(8)
                    .border({ width: 1, color: COLOR_BORDER })
                    .enabled(!this.busy)
                    .opacity(this.busy ? 0.45 : 1)
                    .onClick(() => {
                      if (!this.busy) {
                        this.confirmDelete(plan);
                      }
                    })
                    .accessibilityText('删除展位方案：' + plan.name)
                }
                .width('100%')
              }
              .width('100%')
              .padding(9)
              .backgroundColor(COLOR_CARD)
              .borderRadius(12)
              .border({ width: 1, color: COLOR_BORDER })
            }
          }, (plan: BoothPlan): string => plan.id)
        }
        .id('plan-list')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 10 })
    .backgroundColor(COLOR_PAGE)
  }

  @Builder
  brandHeader() {
    Row({ space: 10 }) {
      Row() {
        Text('B')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .accessibilityText('BoothLab 标志')
      }
      .width(42)
      .height(42)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(COLOR_PRIMARY)
      .borderRadius(12)

      Column({ space: 1 }) {
        Text('BoothLab')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
          .accessibilityText('BoothLab')
        Text('展位方案库 · 本地保存')
          .fontSize(11)
          .fontColor(COLOR_MUTED)
          .accessibilityText('展位方案库，本地保存')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('M3')
        .fontSize(10)
        .fontColor(COLOR_PRIMARY)
        .backgroundColor(COLOR_SELECTED_TINT)
        .borderRadius(8)
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .accessibilityText('BoothLab M3')
    }
    .id('brand-header')
    .width('100%')
    .height(44)
  }

  private templateName(templateId: string): string {
    const template: BoothTemplate | undefined = getTemplateById(templateId);
    return template === undefined ? '未知模板' : template.name;
  }

  private planSummary(plan: BoothPlan): string {
    return this.templateName(plan.templateId) + ' · ' +
      plan.objects.length.toString() + ' 件物件';
  }

  private formatUpdatedAt(timestamp: number): string {
    if (!Number.isFinite(timestamp)) {
      return '未知时间';
    }
    const date: Date = new Date(timestamp);
    return date.getFullYear().toString() + '-' + pad2(date.getMonth() + 1) + '-' +
      pad2(date.getDate()) + ' ' + pad2(date.getHours()) + ':' + pad2(date.getMinutes());
  }

  private confirmDelete(plan: BoothPlan): void {
    if (this.busy) {
      return;
    }
    AlertDialog.show({
      title: '删除展位方案',
      message: '确定删除“' + plan.name + '”吗？删除后无法恢复。',
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: '取消',
        fontColor: COLOR_TEXT,
        action: () => {
          if (!this.busy) {
            this.onDelete(plan.id, false);
          }
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: COLOR_DANGER,
        action: () => {
          if (!this.busy) {
            this.onDelete(plan.id, true);
          }
        }
      },
      cancel: () => {
        if (!this.busy) {
          this.onDelete(plan.id, false);
        }
      }
    });
  }
}
