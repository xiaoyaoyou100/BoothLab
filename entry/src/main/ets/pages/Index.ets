/**
 * BoothLab M2-I01 application shell.
 *
 * This is the only @Entry page. It owns the durable Preferences adapter, the
 * PlanRepository and exactly one SaveCoordinator:
 *
 *   launch -> PreferencesStore.create(host context) -> repository.recoverStore
 *          -> PlanLibrary -> create/open -> EditorWorkspace
 *          -> save -> PlanLibrary -> open/delete -> restart recovery
 *
 * A failed bootstrap is shown as an explicit protected error with a retry
 * button. The shell never fabricates an empty library, never clears storage and
 * never falls back to the M1 in-memory demo. Only Index touches Preferences;
 * the editor engine and the library component never do.
 */

import { common } from '@kit.AbilityKit';
import { BoothPlan, OperationResult, PlanStore } from '../model/BoothModels';
import { SaveState } from '../model/M2Contracts';
import { PlanRepository } from '../repository/PlanRepository';
import {
  RebuildResult,
  RebuildState
} from '../repository/RecoveryContracts';
import { PreferencesStore } from '../storage/PreferencesStore';
import { PlanLibrary } from '../components/plan/PlanLibrary';
import { EditorWorkspace } from '../components/editor/EditorWorkspace';
import { SaveCoordinator } from '../application/SaveCoordinator';
import {
  RebuildCoordinator,
  RebuildUiSnapshot
} from '../application/RebuildCoordinator';

const COLOR_PAGE: string = '#F7F8F4';
const COLOR_PRIMARY: string = '#247C72';
const COLOR_TEXT: string = '#263B41';
const COLOR_MUTED: string = '#6B7C80';
const COLOR_BORDER: string = '#E5EBE7';
const COLOR_DANGER: string = '#B23A2E';
const COLOR_CARD: string = '#FFFFFF';

@Entry
@Component
struct Index {
  @State phase: string = 'loading';
  @State bootstrapError: string = '';

  @State plans: BoothPlan[] = [];
  @State libraryBusy: boolean = false;
  @State libraryMessage: string = '';

  @State editorPlan: BoothPlan | null = null;
  @State editorSaveState: SaveState = 'Dirty';
  @State editorSaveBusy: boolean = false;
  @State editorClosing: boolean = false;
  @State editorMessage: string = '';

  // Recovery-page controls. The coordinator owns the transition rules; Index
  // mirrors its immutable snapshot into primitives so ArkUI re-renders.
  @State rebuildPhase: string = 'BLOCKED';
  @State rebuildGuidance: string = '';
  @State rebuildReviewMessage: string = '';
  @State rebuildFailureMessage: string = '';
  @State rebuildArchiveId: string = '';
  @State rebuildCanOffer: boolean = false;
  @State rebuildCanConfirm: boolean = false;
  @State rebuildCanCancel: boolean = false;
  @State rebuildCanRetryRead: boolean = true;
  @State rebuildBusy: boolean = false;

  private repository: PlanRepository | null = null;
  private coordinator: SaveCoordinator | null = null;
  private rebuildCoordinator: RebuildCoordinator | null = null;
  /** Number of UI save requests in flight, so overlapping saves keep busy true. */
  private saveRequests: number = 0;

  aboutToAppear(): void {
    this.bootstrap();
  }

  onPageHide(): void {
    // Best-effort formal save only. Completion state is read from the
    // coordinator after the real promise resolves; nothing is claimed early.
    const coordinator: SaveCoordinator | null = this.coordinator;
    if (this.phase !== 'editor' || coordinator === null) {
      return;
    }
    if (coordinator.getState() === 'Saved' && !coordinator.isSaving()) {
      return;
    }
    coordinator.save().then((result: OperationResult<BoothPlan>): void => {
      if (this.phase === 'editor' && this.coordinator === coordinator) {
        this.editorSaveState = coordinator.getState();
      }
    }).catch((error: Object): void => {
      // No UI claim: the next explicit save/back reports the real failure.
    });
  }

  onBackPress(): boolean {
    if (this.phase === 'editor') {
      this.leaveEditor();
      return true;
    }
    return false;
  }

  build() {
    Column() {
      if (this.phase === 'loading') {
        this.loadingView()
      } else if (this.phase === 'error') {
        this.bootstrapErrorView()
      } else if (this.phase === 'editor' && this.editorPlan !== null) {
        EditorWorkspace({
          plan: this.editorPlan as BoothPlan,
          saveState: this.editorSaveState,
          saveBusy: this.editorSaveBusy,
          closing: this.editorClosing,
          message: this.editorMessage,
          onChanged: (plan: BoothPlan): void => {
            this.handleEditorChanged(plan);
          },
          onSave: (): void => {
            this.handleEditorSave();
          },
          onBack: (): void => {
            this.leaveEditor();
          }
        })
      } else {
        PlanLibrary({
          plans: this.plans,
          busy: this.libraryBusy,
          message: this.libraryMessage,
          onCreate: (name: string, templateId: string): void => {
            this.handleCreate(name, templateId);
          },
          onOpen: (planId: string): void => {
            this.handleOpen(planId);
          },
          onDelete: (planId: string, confirmed: boolean): void => {
            this.handleDelete(planId, confirmed);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_PAGE)
  }

  @Builder
  loadingView() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(COLOR_PRIMARY)
      Text('正在恢复方案库…')
        .fontSize(15)
        .fontColor(COLOR_TEXT)
        .accessibilityText('正在恢复方案库')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  bootstrapErrorView() {
    Scroll() {
      Column({ space: 12 }) {
        Text('方案库无法打开')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_DANGER)
          .accessibilityText('方案库无法打开')
        Text(this.bootstrapError)
          .id('bootstrap-error')
          .fontSize(14)
          .fontColor(COLOR_TEXT)
          .textAlign(TextAlign.Center)
          .accessibilityText('错误详情：' + this.bootstrapError)
        Text('原始方案数据无法直接恢复使用。应用不会自动清空方案库，也不会导入演示方案。')
          .fontSize(13)
          .fontColor(COLOR_MUTED)
          .textAlign(TextAlign.Center)
        if (this.rebuildReviewMessage.length > 0) {
          Text('恢复审查：' + this.rebuildReviewMessage)
            .id('rebuild-review-message')
            .fontSize(13)
            .fontColor(COLOR_TEXT)
            .textAlign(TextAlign.Center)
            .accessibilityText('恢复审查结果：' + this.rebuildReviewMessage)
        }
        if (this.rebuildGuidance.length > 0) {
          Text(this.rebuildGuidance)
            .id('rebuild-blocked-reason')
            .fontSize(13)
            .fontColor(COLOR_MUTED)
            .textAlign(TextAlign.Center)
            .accessibilityText('重建可用性说明：' + this.rebuildGuidance)
        }
        if (this.rebuildFailureMessage.length > 0) {
          Text('重建失败：' + this.rebuildFailureMessage)
            .id('rebuild-failure')
            .fontSize(13)
            .fontColor(COLOR_DANGER)
            .textAlign(TextAlign.Center)
            .accessibilityText('重建失败：' + this.rebuildFailureMessage)
        }
        if (this.rebuildArchiveId.length > 0) {
          Text('损坏快照归档 ID：' + this.rebuildArchiveId)
            .id('rebuild-archive-id')
            .fontSize(13)
            .fontColor(COLOR_TEXT)
            .textAlign(TextAlign.Center)
            .accessibilityText('损坏快照归档 ID：' + this.rebuildArchiveId)
        }
        if (this.rebuildPhase === 'REBUILDING') {
          Column({ space: 6 }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(COLOR_PRIMARY)
            Text('正在重建方案库…')
              .fontSize(14)
              .fontColor(COLOR_TEXT)
            Text('重建期间已禁用重复操作，请等待完成。')
              .fontSize(12)
              .fontColor(COLOR_MUTED)
              .textAlign(TextAlign.Center)
          }
          .id('rebuild-progress')
          .width('100%')
          .padding(12)
          .alignItems(HorizontalAlign.Center)
          .accessibilityText('正在重建方案库，已禁用重复操作')
        } else if (this.rebuildPhase === 'CONFIRMING') {
          this.rebuildConfirmView()
        } else {
          Row({ space: 10 }) {
            Button('重试读取')
              .id('bootstrap-retry')
              .type(ButtonType.Normal)
              .height(42)
              .layoutWeight(1)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor(COLOR_PRIMARY)
              .borderRadius(10)
              .enabled(this.rebuildCanRetryRead)
              .opacity(this.rebuildCanRetryRead ? 1 : 0.45)
              .accessibilityText('重新读取方案库恢复状态')
              .onClick(() => {
                this.retryRecovery();
              })
            if (this.rebuildPhase === 'FAILED' && this.rebuildCanOffer) {
              Button('重新尝试重建')
                .id('rebuild-retry')
                .type(ButtonType.Normal)
                .height(42)
                .layoutWeight(1)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor(COLOR_DANGER)
                .borderRadius(10)
                .accessibilityText('重新尝试重建方案库，需再次确认')
                .onClick(() => {
                  this.handleRebuildRequest();
                })
            } else if (this.rebuildCanOffer) {
              Button('重建方案库')
                .id('rebuild-entry')
                .type(ButtonType.Normal)
                .height(42)
                .layoutWeight(1)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor(COLOR_DANGER)
                .borderRadius(10)
                .accessibilityText('重建方案库，需要独立二次确认')
                .onClick(() => {
                  this.handleRebuildRequest();
                })
            }
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(24)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(COLOR_PAGE)
  }

  @Builder
  rebuildConfirmView() {
    Column({ space: 8 }) {
      Text('再次确认重建')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_DANGER)
        .accessibilityText('再次确认重建')
      Text('确认后将先归档两份原始损坏快照，再把方案库重建为空白。原方案内容无法恢复，也不会导入演示方案。')
        .fontSize(13)
        .fontColor(COLOR_TEXT)
        .textAlign(TextAlign.Center)
      Text('取消不会改变方案数据，也不会改变已有归档。')
        .fontSize(12)
        .fontColor(COLOR_MUTED)
        .textAlign(TextAlign.Center)
      Row({ space: 10 }) {
        Button('取消')
          .id('rebuild-cancel')
          .type(ButtonType.Normal)
          .height(42)
          .layoutWeight(1)
          .fontSize(15)
          .fontColor(COLOR_TEXT)
          .backgroundColor(COLOR_PAGE)
          .borderRadius(10)
          .border({ width: 1, color: COLOR_BORDER })
          .enabled(this.rebuildCanCancel)
          .accessibilityText('取消重建，不改变方案数据和归档')
          .onClick(() => {
            this.handleRebuildCancel();
          })
        Button('确认重建')
          .id('rebuild-confirm')
          .type(ButtonType.Normal)
          .height(42)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(COLOR_DANGER)
          .borderRadius(10)
          .enabled(this.rebuildCanConfirm)
          .accessibilityText('确认重建方案库，先归档再写入空库')
          .onClick(() => {
            this.handleRebuildConfirm();
          })
      }
      .width('100%')
    }
    .id('rebuild-confirm-panel')
    .width('100%')
    .padding(12)
    .backgroundColor(COLOR_CARD)
    .borderRadius(10)
    .border({ width: 1, color: COLOR_BORDER })
    .accessibilityText('重建二次确认面板')
  }

  // ------------------------------------------------------------------
  // Bootstrap
  // ------------------------------------------------------------------

  private async bootstrap(): Promise<void> {
    this.phase = 'loading';
    this.bootstrapError = '';
    this.libraryBusy = false;
    this.rebuildCoordinator = null;
    this.resetRebuildUi();
    try {
      const host: common.Context | null = this.resolveHostContext();
      if (host === null) {
        this.failBootstrap('无法获取应用上下文，方案库未加载。');
        return;
      }
      const storageResult: OperationResult<PreferencesStore> =
        await PreferencesStore.create(host);
      if (storageResult.code !== 'OK' || storageResult.data === undefined) {
        this.failBootstrap('持久化存储初始化失败：' + storageResult.message);
        return;
      }
      // The same PreferencesStore is both the snapshot storage and the recovery
      // archive port. Without this second argument B never offers rebuild.
      const storage: PreferencesStore = storageResult.data;
      const repository: PlanRepository = new PlanRepository(storage, storage);
      this.repository = repository;
      this.rebuildCoordinator = new RebuildCoordinator(
        (): RebuildState => repository.getRebuildState(),
        (confirmed: boolean): Promise<RebuildResult> => repository.rebuildStore(confirmed)
      );
      await this.recoverIntoLibrary();
    } catch (error) {
      this.failBootstrap('方案库初始化发生未预期错误。');
    }
  }

  /** Runs the real B recovery and then either opens the library or the
   * protected failure page. Never fabricates an empty library here. */
  private async recoverIntoLibrary(): Promise<void> {
    const repository: PlanRepository | null = this.repository;
    const rebuild: RebuildCoordinator | null = this.rebuildCoordinator;
    if (repository === null || rebuild === null) {
      this.failBootstrap('方案库恢复状态不可用。');
      return;
    }
    this.phase = 'loading';
    this.bootstrapError = '';
    this.libraryBusy = false;
    try {
      const recovered: OperationResult<PlanStore> = await repository.recoverStore();
      if (recovered.code === 'OK' && recovered.data !== undefined) {
        this.enterLibrary(repository, recovered.message);
        return;
      }
      this.showRecoveryFailure('方案库恢复失败：' + recovered.message, rebuild);
    } catch (error) {
      this.showRecoveryFailure('方案库恢复失败：发生未预期错误。', rebuild);
    }
  }

  private enterLibrary(repository: PlanRepository, message: string): void {
    this.coordinator = new SaveCoordinator(repository);
    this.plans = repository.listPlans();
    this.libraryMessage = message;
    this.libraryBusy = false;
    this.editorPlan = null;
    this.editorClosing = false;
    this.phase = 'library';
  }

  private showRecoveryFailure(message: string, rebuild: RebuildCoordinator): void {
    this.bootstrapError = message;
    this.applyRebuildSnapshot(rebuild.prepare(message));
    this.phase = 'error';
    this.libraryBusy = false;
  }

  private retryRecovery(): void {
    this.runRetryRecovery();
  }

  /** Re-reads through the real repository without replacing it, so a rebuild
   * failure's message and archive id remain visible on the next review. */
  private async runRetryRecovery(): Promise<void> {
    if (this.rebuildBusy) {
      return;
    }
    if (this.repository === null || this.rebuildCoordinator === null) {
      this.bootstrap();
      return;
    }
    await this.recoverIntoLibrary();
  }

  private applyRebuildSnapshot(snapshot: RebuildUiSnapshot): void {
    this.rebuildPhase = snapshot.phase;
    this.rebuildGuidance = snapshot.guidance;
    this.rebuildReviewMessage = snapshot.reviewMessage;
    this.rebuildFailureMessage = snapshot.failureMessage;
    this.rebuildArchiveId = snapshot.archiveId;
    this.rebuildCanOffer = snapshot.canOfferRebuild;
    this.rebuildCanConfirm = snapshot.canConfirm;
    this.rebuildCanCancel = snapshot.canCancel;
    this.rebuildCanRetryRead = snapshot.canRetryRead;
    this.rebuildBusy = snapshot.busy;
  }

  private resetRebuildUi(): void {
    this.rebuildPhase = 'BLOCKED';
    this.rebuildGuidance = '';
    this.rebuildReviewMessage = '';
    this.rebuildFailureMessage = '';
    this.rebuildArchiveId = '';
    this.rebuildCanOffer = false;
    this.rebuildCanConfirm = false;
    this.rebuildCanCancel = false;
    this.rebuildCanRetryRead = true;
    this.rebuildBusy = false;
  }

  private handleRebuildRequest(): void {
    const rebuild: RebuildCoordinator | null = this.rebuildCoordinator;
    if (rebuild === null || this.rebuildBusy) {
      return;
    }
    this.applyRebuildSnapshot(rebuild.requestRebuild());
  }

  private handleRebuildCancel(): void {
    const rebuild: RebuildCoordinator | null = this.rebuildCoordinator;
    if (rebuild === null || this.rebuildBusy) {
      return;
    }
    this.applyRebuildSnapshot(rebuild.cancelRebuild());
  }

  private handleRebuildConfirm(): void {
    const rebuild: RebuildCoordinator | null = this.rebuildCoordinator;
    const repository: PlanRepository | null = this.repository;
    if (rebuild === null || repository === null || this.rebuildBusy) {
      return;
    }
    const pending: Promise<RebuildUiSnapshot> = rebuild.confirmRebuild();
    // confirmRebuild enters REBUILDING synchronously; mirror it before the
    // await so repeat taps are disabled while B is still working.
    this.applyRebuildSnapshot(rebuild.getSnapshot());
    pending.then((snapshot: RebuildUiSnapshot): void => {
      if (this.rebuildCoordinator !== rebuild) {
        return;
      }
      this.applyRebuildSnapshot(snapshot);
      if (snapshot.phase === 'REBUILT') {
        this.finishRebuild(repository, snapshot);
      }
    }).catch((error: Object): void => {
      if (this.rebuildCoordinator !== rebuild) {
        return;
      }
      this.applyRebuildSnapshot(rebuild.getSnapshot());
    });
  }

  /** Only a REBUILT result reaches here: the repository is already the real
   * empty schema-1 store, so normal create/save/open flows become available. */
  private finishRebuild(repository: PlanRepository,
    snapshot: RebuildUiSnapshot): void {
    let message: string = snapshot.successMessage.length > 0 ?
      snapshot.successMessage : '方案库已重建为空库。';
    if (snapshot.archiveId.length > 0) {
      message = message + ' 原始损坏快照归档 ID：' + snapshot.archiveId + '。';
    }
    this.bootstrapError = '';
    this.enterLibrary(repository, message);
  }

  private failBootstrap(message: string): void {
    // Explicit protected failure. Persisted data is never cleared or reset.
    this.bootstrapError = message;
    this.phase = 'error';
    this.libraryBusy = false;
  }

  private resolveHostContext(): common.Context | null {
    try {
      const uiContext = this.getUIContext();
      if (uiContext === null || uiContext === undefined) {
        return null;
      }
      const host = uiContext.getHostContext();
      if (host === null || host === undefined) {
        return null;
      }
      return host;
    } catch (error) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Library actions (all awaited, all refreshed from the repository)
  // ------------------------------------------------------------------

  private async handleCreate(name: string, templateId: string): Promise<void> {
    if (this.repository === null || this.libraryBusy) {
      return;
    }
    this.libraryBusy = true;
    this.libraryMessage = '正在创建展位方案…';
    try {
      const created: OperationResult<BoothPlan> =
        await this.repository.createPlan(name, templateId);
      if (created.code !== 'OK' || created.data === undefined) {
        this.libraryMessage = '创建失败：' + created.message;
        return;
      }
      // A new plan is always opened through the repository so activePlanId is
      // persisted; the editor receives that durable snapshot, not a seed.
      const opened: OperationResult<BoothPlan> =
        await this.repository.openPlan(created.data.id);
      if (opened.code !== 'OK' || opened.data === undefined) {
        this.refreshPlans();
        this.libraryMessage = '方案已创建，但打开失败：' + opened.message;
        return;
      }
      this.refreshPlans();
      this.enterEditor(opened.data);
    } catch (error) {
      this.libraryMessage = '创建失败：发生未预期错误。';
    } finally {
      this.libraryBusy = false;
    }
  }

  private async handleOpen(planId: string): Promise<void> {
    if (this.repository === null || this.libraryBusy) {
      return;
    }
    this.libraryBusy = true;
    this.libraryMessage = '正在打开展位方案…';
    try {
      const opened: OperationResult<BoothPlan> = await this.repository.openPlan(planId);
      if (opened.code !== 'OK' || opened.data === undefined) {
        this.refreshPlans();
        this.libraryMessage = '打开失败：' + opened.message;
        return;
      }
      this.refreshPlans();
      this.enterEditor(opened.data);
    } catch (error) {
      this.libraryMessage = '打开失败：发生未预期错误。';
    } finally {
      this.libraryBusy = false;
    }
  }

  private async handleDelete(planId: string, confirmed: boolean): Promise<void> {
    if (this.repository === null || this.libraryBusy) {
      return;
    }
    if (!confirmed) {
      this.libraryMessage = '已取消删除。';
      return;
    }
    this.libraryBusy = true;
    this.libraryMessage = '正在删除展位方案…';
    try {
      const result: OperationResult<boolean> =
        await this.repository.deletePlan(planId, true);
      if (result.code === 'OK' && result.data === true) {
        this.refreshPlans();
        this.libraryMessage = '展位方案已删除。';
      } else {
        // Failed delete keeps the list exactly as the repository reports it.
        this.libraryMessage = '删除失败：' + result.message;
      }
    } catch (error) {
      this.libraryMessage = '删除失败：发生未预期错误。';
    } finally {
      this.libraryBusy = false;
    }
  }

  private refreshPlans(): void {
    if (this.repository !== null) {
      this.plans = this.repository.listPlans();
    }
  }

  // ------------------------------------------------------------------
  // Editor session: one coordinator, opening snapshot never overwritten
  // ------------------------------------------------------------------

  private enterEditor(plan: BoothPlan): void {
    if (this.coordinator === null) {
      return;
    }
    this.coordinator.bind(plan);
    if (this.coordinator.getDraft() === null) {
      // A repository plan that cannot be bound is reported here instead of
      // mounting an editor whose save path could never become truthful.
      this.libraryMessage = '无法打开该展位方案：方案数据无效。';
      this.refreshPlans();
      return;
    }
    this.editorPlan = plan;
    this.editorSaveState = this.coordinator.getState();
    this.editorSaveBusy = false;
    this.editorClosing = false;
    this.editorMessage = '';
    this.saveRequests = 0;
    this.phase = 'editor';
  }

  /**
   * Records an effective editor change. The opening plan prop is intentionally
   * not replaced: the editor keeps its own controller/history and only the
   * coordinator's draft advances.
   */
  private handleEditorChanged(plan: BoothPlan): void {
    const coordinator: SaveCoordinator | null = this.coordinator;
    if (coordinator === null) {
      return;
    }
    const result: OperationResult<boolean> = coordinator.update(plan);
    if (result.code !== 'OK') {
      this.editorMessage = '编辑未能记录：' + result.message;
      return;
    }
    this.editorSaveState = coordinator.getState();
  }

  private handleEditorSave(): void {
    this.runEditorSave();
  }

  private async runEditorSave(): Promise<void> {
    const coordinator: SaveCoordinator | null = this.coordinator;
    if (coordinator === null) {
      return;
    }
    if (this.editorSaveBusy) {
      return;
    }
    this.beginSaveUi();
    this.editorMessage = '';
    // Explicit UI/coordinator sync before the await.
    this.editorSaveState = 'Saving';
    try {
      const result: OperationResult<BoothPlan> = await coordinator.save();
      // Explicit sync after the await; never assume Saved.
      this.editorSaveState = coordinator.getState();
      if (result.code !== 'OK') {
        this.editorMessage = '保存失败：' + result.message;
      } else {
        this.refreshPlans();
        if (this.editorSaveState === 'Saved') {
          this.libraryMessage = '展位方案已保存。';
        } else if (this.editorSaveState === 'Dirty') {
          this.editorMessage = '保存期间记录到新的编辑，最新内容尚未保存。';
        }
      }
    } catch (error) {
      this.editorSaveState = coordinator.getState();
      this.editorMessage = '保存失败：发生未预期错误。';
    }
    this.endSaveUi();
  }

  private leaveEditor(): void {
    this.runLeaveEditor();
  }

  /**
   * Toolbar back and OS back both land here. The latest draft is saved before
   * leaving; a failed save keeps the editor open with a visible error. If a
   * newer edit landed during an ordinary save, the loop saves that latest
   * snapshot instead of silently leaving on the older acknowledgement.
   */
  private async runLeaveEditor(): Promise<void> {
    const coordinator: SaveCoordinator | null = this.coordinator;
    if (this.phase !== 'editor' || coordinator === null) {
      return;
    }
    if (this.editorClosing) {
      return;
    }
    this.editorClosing = true;
    this.editorMessage = '';
    this.beginSaveUi();
    let canLeave: boolean = false;
    try {
      for (let attempt = 0; attempt < 3; attempt++) {
        if (coordinator.getState() === 'Saved' && !coordinator.isSaving()) {
          canLeave = true;
          break;
        }
        this.editorSaveState = 'Saving';
        const result: OperationResult<BoothPlan> = await coordinator.save();
        this.editorSaveState = coordinator.getState();
        if (result.code !== 'OK') {
          this.editorMessage = '返回前保存失败：' + result.message;
          break;
        }
        if (this.editorSaveState === 'Saved') {
          canLeave = true;
          break;
        }
        // Dirty: an edit arrived during the save. Retry with the latest draft.
      }
      if (canLeave) {
        this.refreshPlans();
        this.libraryMessage = '展位方案已保存。';
        this.editorSaveState = 'Saved';
        this.editorPlan = null;
        this.editorClosing = false;
        this.phase = 'library';
      } else {
        if (this.editorMessage.length === 0) {
          this.editorMessage = '返回前保存未完成，已留在编辑页。';
        }
        this.editorClosing = false;
      }
    } catch (error) {
      this.editorSaveState = coordinator.getState();
      this.editorMessage = '返回前保存失败：发生未预期错误。';
      this.editorClosing = false;
    }
    this.endSaveUi();
  }

  private beginSaveUi(): void {
    this.saveRequests = this.saveRequests + 1;
    this.editorSaveBusy = true;
  }

  private endSaveUi(): void {
    if (this.saveRequests > 0) {
      this.saveRequests = this.saveRequests - 1;
    }
    this.editorSaveBusy = this.saveRequests > 0;
  }
}
