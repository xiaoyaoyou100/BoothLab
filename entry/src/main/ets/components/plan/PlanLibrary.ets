/**
 * PlanLibrary (M2-B UI).
 *
 * Pure presentation component for the saved-plan library. It never reads the
 * repository or Preferences directly: the parent (A) owns the repository,
 * resolves promises, updates `plans`, and reports results through `message`.
 *
 * The component only calls:
 *   onCreate(name, templateId) when the create button is pressed,
 *   onOpen(planId) when a plan card is opened,
 *   onDelete(planId, confirmed) after the AlertDialog decision.
 *
 * All plan data rendered here comes from the repository snapshot supplied by
 * the parent; there is no demo/fake plan data and no test-only UI.
 */

import { BoothPlan, BoothTemplate } from '../../model/BoothModels';
import { getTemplateById, listTemplates } from '../../catalog/BoothTemplates';
import { PlanThumbnail } from './PlanThumbnail';

const COLOR_PAGE: string = '#F7F8F4';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_ACCENT: string = '#FFB56B';
const COLOR_TEXT: string = '#263B41';
const COLOR_MUTED: string = '#6B7C80';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_DANGER: string = '#B23A2E';

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
    const selectable: BoothTemplate[] = [];
    for (let i = 0; i < available.length; i++) {
      const template: BoothTemplate = available[i];
      if (template.id === 'standard' || template.id === 'corner') {
        selectable.push(template);
      }
    }
    this.templates = selectable;
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
    Column({ space: 10 }) {
      Text('我的展位方案')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
        .accessibilityText('我的展位方案列表标题')

      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(13)
          .fontColor(COLOR_TEXT)
          .width('100%')
          .padding(10)
          .backgroundColor(COLOR_ACCENT)
          .borderRadius(8)
          .accessibilityText('方案库状态：' + this.message)
      }

      TextInput({ placeholder: '展位方案名称（1-30 个字符）', text: this.planName })
        .id('plan-name-input')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(COLOR_TEXT)
        .backgroundColor(COLOR_CARD)
        .borderRadius(10)
        .border({ width: 1, color: COLOR_BORDER })
        .enabled(!this.busy)
        .onChange((value: string) => {
          this.planName = value;
        })
        .accessibilityText('展位方案名称输入框，输入 1 到 30 个字符')

      Row({ space: 8 }) {
        ForEach(this.templates, (template: BoothTemplate) => {
          Button(this.templateLabel(template))
            .id('template-' + template.id)
            .type(ButtonType.Normal)
            .height(40)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor(this.selectedTemplateId === template.id ? '#FFFFFF' : COLOR_TEXT)
            .backgroundColor(this.selectedTemplateId === template.id ? COLOR_PRIMARY : COLOR_CARD)
            .borderRadius(10)
            .border({ width: 1, color: COLOR_BORDER })
            .enabled(!this.busy)
            .opacity(this.busy ? 0.45 : 1)
            .onClick(() => {
              if (!this.busy) {
                this.selectedTemplateId = template.id;
              }
            })
            .accessibilityText('选择展位模板：' + template.name +
              (this.selectedTemplateId === template.id ? '，已选中' : ''))
        }, (template: BoothTemplate): string => template.id)
      }
      .width('100%')

      Button(this.busy ? '处理中…' : '新建展位方案')
        .id('create-plan')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .fontSize(16)
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
          this.onCreate(this.planName.trim(), this.selectedTemplateId);
        })
        .accessibilityText('使用当前名称和模板新建展位方案')

      Divider().color(COLOR_BORDER)

      if (this.plans.length === 0) {
        Column({ space: 4 }) {
          Text('方案库为空')
            .fontSize(16)
            .fontColor(COLOR_TEXT)
            .accessibilityText('方案库为空')
          Text('输入名称并选择模板后，点击“新建展位方案”开始。')
            .fontSize(13)
            .fontColor(COLOR_MUTED)
            .textAlign(TextAlign.Center)
            .accessibilityText('新建展位方案提示')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(COLOR_CARD)
        .borderRadius(10)
        .id('plan-empty')
      } else {
        List({ space: 10 }) {
          ForEach(this.plans, (plan: BoothPlan) => {
            ListItem() {
              Column({ space: 8 }) {
                PlanThumbnail({ plan: plan })
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(plan.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(COLOR_TEXT)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .accessibilityText('展位方案名称：' + plan.name)
                    Text(this.planSummary(plan))
                      .fontSize(12)
                      .fontColor(COLOR_MUTED)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .accessibilityText('方案信息：' + this.planSummary(plan))
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
                    .height(36)
                    .fontSize(14)
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
                    .height(36)
                    .fontSize(14)
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
              .padding(10)
              .backgroundColor(COLOR_CARD)
              .borderRadius(12)
              .border({ width: 1, color: COLOR_BORDER })
            }
          }, (plan: BoothPlan): string => plan.id)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(COLOR_PAGE)
  }

  private templateLabel(template: BoothTemplate): string {
    return template.name + ' ' + this.meters(template.widthCm) + 'm×' +
      this.meters(template.heightCm) + 'm';
  }

  private meters(valueCm: number): string {
    const valueM: number = valueCm / 100;
    if (Number.isInteger(valueM)) {
      return valueM.toString();
    }
    return valueM.toFixed(1);
  }

  private templateName(templateId: string): string {
    const template: BoothTemplate | undefined = getTemplateById(templateId);
    return template === undefined ? '未知模板' : template.name;
  }

  private planSummary(plan: BoothPlan): string {
    return this.templateName(plan.templateId) + ' · ' +
      plan.objects.length.toString() + ' 件物件 · 更新于 ' +
      this.formatUpdatedAt(plan.updatedAt);
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
