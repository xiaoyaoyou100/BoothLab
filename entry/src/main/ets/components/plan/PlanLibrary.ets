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

import { KeyboardAvoidMode } from '@kit.ArkUI';
import { BoothPlan, BoothTemplate } from '../../model/BoothModels';
import { getTemplateById, listTemplates } from '../../catalog/BoothTemplates';
import { PlanThumbnail } from './PlanThumbnail';
import { TemplateCard } from './TemplateCard';

const COLOR_PAGE: string = '#F7F8F4';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_MUTED: string = '#617477';
const COLOR_BORDER: string = '#DDE5E0';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_DANGER: string = '#B23A2E';
const COLOR_SELECTED_TINT: string = '#E8F2EF';
const COLOR_ALERT_BG: string = '#FFF4EA';
const COLOR_ALERT_TEXT: string = '#9A5A1E';

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
  @State createExpanded: boolean = false;
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToAppear(): void {
    this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
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

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
  }

  build() {
    Scroll() {
      this.libraryContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_PAGE)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  libraryContent() {
    Column({ space: 8 }) {
      this.brandHeader()

      if (this.busy) {
        Row({ space: 8 }) {
          Row()
            .width(3)
            .height(24)
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(2)
          Text(this.statusText())
            .fontSize(13)
            .fontColor(COLOR_TEXT)
            .layoutWeight(1)
            .accessibilityText('方案库状态：' + this.statusText())
        }
        .id('library-message')
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(COLOR_CARD)
        .borderRadius(10)
        .border({ width: 1, color: COLOR_BORDER })
      } else if (this.message.length > 0 && this.isSuccessMessage(this.message)) {
        Row({ space: 8 }) {
          Row()
            .width(3)
            .height(20)
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(2)
          Text(this.message)
            .fontSize(12)
            .fontColor(COLOR_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .accessibilityText('方案库状态：' + this.message)
        }
        .id('library-message')
        .width('100%')
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor(COLOR_SELECTED_TINT)
        .borderRadius(10)
        .border({ width: 1, color: COLOR_BORDER })
      } else if (this.message.length > 0) {
        Row({ space: 8 }) {
          Row()
            .width(3)
            .height(38)
            .backgroundColor(COLOR_ACCENT)
            .borderRadius(2)
          Column({ space: 2 }) {
            Text('提示')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_ALERT_TEXT)
              .width('100%')
            Text(this.message)
              .fontSize(13)
              .fontColor(COLOR_TEXT)
              .width('100%')
              .accessibilityText('方案库提醒：' + this.message)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .id('library-message')
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(COLOR_ALERT_BG)
        .borderRadius(10)
        .border({ width: 1, color: COLOR_ACCENT })
      }

      Button(this.createExpanded ? '收起新建表单' : '新建展位方案')
        .id('create-plan-toggle')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.createExpanded ? COLOR_TEXT : '#FFFFFF')
        .backgroundColor(this.createExpanded ? COLOR_CARD : COLOR_PRIMARY)
        .borderRadius(12)
        .border({ width: 1, color: this.createExpanded ? COLOR_BORDER : COLOR_PRIMARY })
        .enabled(!this.busy)
        .opacity(this.busy ? 0.45 : 1)
        .onClick(() => {
          if (!this.busy) {
            this.createExpanded = !this.createExpanded;
          }
        })
        .accessibilityText(this.createExpanded ? '收起新建展位表单' : '展开新建展位方案表单')

      if (this.createExpanded) {
        Column({ space: 6 }) {
          Text('填写方案信息')
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .accessibilityText('填写展位方案信息')

          Text('输入名称并选择真实展位模板，创建后可继续编辑。')
            .width('100%')
            .fontSize(12)
            .fontColor(COLOR_MUTED)

          TextInput({ placeholder: '展位方案名称（1-30 个字符）', text: this.planName })
            .id('plan-name-input')
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor(COLOR_TEXT)
            .backgroundColor(COLOR_CARD)
            .borderRadius(12)
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
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(12)
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
        .padding(16)
        .backgroundColor(COLOR_CARD)
        .borderRadius(16)
        .border({ width: 1, color: COLOR_BORDER })
      }

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
          Text('点击上方“新建展位方案”开始创建。')
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
        Column({ space: 8 }) {
          ForEach(this.plans, (plan: BoothPlan) => {
            Column({ space: 8 }) {
              PlanThumbnail({ plan: plan })
              Column({ space: 2 }) {
                Text(plan.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .accessibilityText('展位方案名称：' + plan.name)
                Text(this.planSummary(plan))
                  .fontSize(13)
                  .fontColor(COLOR_MUTED)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .accessibilityText('方案信息：' + this.planSummary(plan))
                Text('更新 ' + this.formatUpdatedAt(plan.updatedAt))
                  .fontSize(12)
                  .fontColor(COLOR_MUTED)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .accessibilityText('更新时间：' + this.formatUpdatedAt(plan.updatedAt))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .accessibilityText('展位方案：' + plan.name + '，模板 ' +
                this.templateName(plan.templateId) + '，共 ' +
                plan.objects.length.toString() + ' 件物件，更新于 ' +
                this.formatUpdatedAt(plan.updatedAt))

              Row({ space: 8 }) {
                Button('删除')
                  .id('delete-plan-' + plan.id)
                  .type(ButtonType.Normal)
                  .width(80)
                  .height(44)
                  .padding(0)
                  .fontSize(14)
                  .fontColor(COLOR_DANGER)
                  .backgroundColor(COLOR_CARD)
                  .borderRadius(12)
                  .border({ width: 1, color: COLOR_BORDER })
                  .enabled(!this.busy)
                  .opacity(this.busy ? 0.45 : 1)
                  .onClick(() => {
                    if (!this.busy) {
                      this.confirmDelete(plan);
                    }
                  })
                  .accessibilityText('删除展位方案：' + plan.name)

                Blank()

                Button('打开')
                  .id('open-plan-' + plan.id)
                  .type(ButtonType.Normal)
                  .width(80)
                  .height(44)
                  .padding(0)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .backgroundColor(COLOR_PRIMARY)
                  .borderRadius(12)
                  .enabled(!this.busy)
                  .opacity(this.busy ? 0.45 : 1)
                  .onClick(() => {
                    if (!this.busy) {
                      this.onOpen(plan.id);
                    }
                  })
                  .accessibilityText('打开展位方案：' + plan.name)
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(COLOR_CARD)
            .borderRadius(16)
            .border({ width: 1, color: COLOR_BORDER })
          }, (plan: BoothPlan): string => plan.id)
        }
        .id('plan-list')
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 10 })
    .backgroundColor(COLOR_PAGE)
  }

  @Builder
  brandHeader() {
    Column({ space: 1 }) {
      Text('展构 · BoothLab')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
        .accessibilityText('展构 BoothLab')
      Text('展位方案库 · 本地保存')
        .fontSize(12)
        .fontColor(COLOR_MUTED)
        .width('100%')
        .accessibilityText('展位方案库，本地保存')
    }
    .id('brand-header')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private isSuccessMessage(value: string): boolean {
    return value === '展位方案已保存。' || value === '展位方案已删除。' || value === '已取消删除。';
  }

  private statusText(): string {
    if (this.message.length > 0) {
      return '处理中… · ' + this.message;
    }
    return '处理中…';
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
