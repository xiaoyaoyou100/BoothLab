/**
 * BoothLab M2-BOTH-CORRUPTED-RECOVERY A-side UI state gate.
 *
 * This coordinator owns the *UI* state machine for the protected recovery page.
 * It performs no storage work and creates no repository: it only asks the
 * B-owned PlanRepository for its reviewed RebuildState and, after two explicit
 * user steps (entry + independent confirmation), forwards rebuildStore(true).
 *
 * Invariants enforced here:
 * - Merely preparing the page or asking for the confirmation panel never calls
 *   rebuildStore and never writes anything.
 * - Cancelling the confirmation performs zero B calls and preserves the failure
 *   message and archive id already shown.
 * - A confirmed rebuild is forwarded exactly once; while it is in flight the
 *   busy flag is true, duplicate confirms are no-ops, and success is published
 *   only after the B promise resolves with REBUILT.
 * - A rebuild entry is exposed only while B reports phase READY, rebuildable
 *   true, and archive capability available. FUTURE_SCHEMA / IO_ERROR / other
 *   blocked reviews therefore never show an actionable rebuild control.
 * - Failure keeps the B message and (when returned) the archive id, and only a
 *   fresh B state that is READY again enables an explicit retry.
 */

import { PlanStore } from '../model/BoothModels';
import {
  RebuildReason,
  RebuildResult,
  RebuildState
} from '../repository/RecoveryContracts';

/** UI-only phase; never persisted and never derived from disk directly. */
export type RebuildUiPhase =
  | 'BLOCKED'
  | 'AVAILABLE'
  | 'CONFIRMING'
  | 'REBUILDING'
  | 'FAILED'
  | 'REBUILT';

/**
 * A complete immutable view of the recovery controls. Index copies these
 * primitives into @State fields after every coordinator transition.
 */
export interface RebuildUiSnapshot {
  phase: RebuildUiPhase;
  reason: RebuildReason;
  /** Failure passed to prepare() (the repository recovery error). */
  recoveryError: string;
  /** B's reviewed message for the current primary/backup classification. */
  reviewMessage: string;
  /** User-facing explanation of why rebuild is or is not available. */
  guidance: string;
  /** Last rebuild failure message, preserved across cancel/retry reads. */
  failureMessage: string;
  /** Last archive id returned by B, preserved until a new one arrives. */
  archiveId: string;
  /** Set only after a confirmed rebuild actually returned REBUILT. */
  successMessage: string;
  /** Last B RebuildStatus, or NONE before the first confirmed attempt. */
  lastStatus: string;
  /** True only when an actionable rebuild entry should be rendered. */
  canOfferRebuild: boolean;
  /** True only while the independent confirmation panel is actionable. */
  canConfirm: boolean;
  /** True only while the confirmation can be cancelled without side effects. */
  canCancel: boolean;
  /** False while a rebuild is in flight so retry-read stays disabled. */
  canRetryRead: boolean;
  busy: boolean;
  /** B's empty store snapshot, present only when phase is REBUILT. */
  store: PlanStore | null;
}

function guidanceFor(reason: RebuildReason, rebuildable: boolean): string {
  if (rebuildable) {
    return '主备两份快照均已损坏，且未检测到未来版本或读取异常。重建会先归档原始文本，再把方案库恢复为空白。';
  }
  if (reason === 'FUTURE_SCHEMA') {
    return '检测到未知的未来版本数据，当前版本不会覆盖、归档或重建，请使用更新版本的应用打开。';
  }
  if (reason === 'IO_ERROR') {
    return '存储读取失败，无法确认数据状态，已禁止重建。请检查存储后重试读取。';
  }
  if (reason === 'ARCHIVE_UNAVAILABLE') {
    return '恢复归档能力不可用，无法保全原始数据，已禁止破坏性重建。';
  }
  if (reason === 'INCOMPLETE_DAMAGE') {
    return '数据损坏不完整（主备快照并非同时存在且损坏），为保护仍可用的数据，不提供重建。';
  }
  if (reason === 'ALREADY_REBUILT') {
    return '方案库已重建为空库，不再提供重建入口。';
  }
  if (reason === 'NO_REBUILD_NEEDED') {
    return '当前数据无需重建。';
  }
  return '当前状态不允许重建，请重试读取或检查存储状态。';
}

export class RebuildCoordinator {
  /** Read-only B state accessor (PlanRepository.getRebuildState). */
  private readRebuildState: () => RebuildState;
  /** The single B mutation entry point (PlanRepository.rebuildStore). */
  private requestRebuildStore: (confirmed: boolean) => Promise<RebuildResult>;

  private phase: RebuildUiPhase = 'BLOCKED';
  private review: RebuildState | null = null;
  private recoveryError: string = '';
  private failureMessage: string = '';
  private archiveId: string = '';
  private successMessage: string = '';
  private lastStatus: string = 'NONE';
  /** Where cancel() returns to; AVAILABLE or FAILED (retry after failure). */
  private returnPhase: RebuildUiPhase = 'AVAILABLE';
  /** True when the latest B review still offers rebuild after a failure. */
  private retryAvailable: boolean = false;
  private rebuilding: boolean = false;
  private rebuiltStore: PlanStore | null = null;

  constructor(readRebuildState: () => RebuildState,
    requestRebuildStore: (confirmed: boolean) => Promise<RebuildResult>) {
    this.readRebuildState = readRebuildState;
    this.requestRebuildStore = requestRebuildStore;
  }

  /**
   * Reads B's reviewed state after a recovery attempt. This is a pure read:
   * no rebuildStore call and no archive mutation. A previous failure message
   * and archive id are retained so a retry-read page can still show them.
   */
  prepare(recoveryError: string): RebuildUiSnapshot {
    if (this.rebuilding) {
      return this.snapshot();
    }
    this.recoveryError = recoveryError;
    let state: RebuildState | null = null;
    try {
      state = this.readRebuildState();
    } catch (error) {
      state = null;
    }
    this.review = state;
    this.retryAvailable = false;
    if (state !== null && state.phase === 'READY' && state.rebuildable) {
      this.phase = 'AVAILABLE';
    } else {
      this.phase = 'BLOCKED';
    }
    return this.snapshot();
  }

  /**
   * First user step: opens the independent confirmation panel. Performs no B
   * call at all, so cancelling after this point cannot touch data or archive.
   */
  requestRebuild(): RebuildUiSnapshot {
    if (this.rebuilding) {
      return this.snapshot();
    }
    const allowed: boolean = this.phase === 'AVAILABLE' ||
      (this.phase === 'FAILED' && this.retryAvailable);
    if (!allowed) {
      return this.snapshot();
    }
    this.returnPhase = this.phase;
    this.phase = 'CONFIRMING';
    return this.snapshot();
  }

  /**
   * Cancels the independent confirmation. Zero B calls; existing failure
   * message and archive id are kept unchanged.
   */
  cancelRebuild(): RebuildUiSnapshot {
    if (this.rebuilding || this.phase !== 'CONFIRMING') {
      return this.snapshot();
    }
    this.phase = this.returnPhase;
    return this.snapshot();
  }

  /**
   * Second user step: only reachable from CONFIRMING. The busy phase is set
   * synchronously before the first await so the UI can disable repeat actions
   * immediately. Confirmed is always true; cancellation never calls B.
   */
  confirmRebuild(): Promise<RebuildUiSnapshot> {
    if (this.rebuilding || this.phase !== 'CONFIRMING') {
      return Promise.resolve(this.snapshot());
    }
    this.rebuilding = true;
    this.phase = 'REBUILDING';
    return this.performRebuild();
  }

  getSnapshot(): RebuildUiSnapshot {
    return this.snapshot();
  }

  private async performRebuild(): Promise<RebuildUiSnapshot> {
    let result: RebuildResult;
    try {
      result = await this.requestRebuildStore(true);
    } catch (error) {
      const fallback: RebuildResult = {
        status: 'UNEXPECTED_ERROR',
        message: '重建发生未预期错误，尚未确认完成；请重试读取。已写入的原始归档会保留。',
        archiveId: null,
        store: null
      };
      result = fallback;
    }
    this.rebuilding = false;
    this.lastStatus = result.status;
    if (result.archiveId !== null && result.archiveId.length > 0) {
      this.archiveId = result.archiveId;
    }
    if (result.status === 'REBUILT') {
      this.phase = 'REBUILT';
      this.failureMessage = '';
      this.successMessage = result.message;
      this.rebuiltStore = result.store;
      this.retryAvailable = false;
      return this.snapshot();
    }
    // Failure: never claim an empty library. Keep B's error and archive id and
    // ask B once for a fresh review so retry is offered only when safe.
    this.phase = 'FAILED';
    this.failureMessage = result.message;
    this.successMessage = '';
    this.rebuiltStore = null;
    this.refreshReviewAfterFailure();
    return this.snapshot();
  }

  private refreshReviewAfterFailure(): void {
    let state: RebuildState | null = null;
    try {
      state = this.readRebuildState();
    } catch (error) {
      state = null;
    }
    this.review = state;
    this.retryAvailable = state !== null && state.phase === 'READY' &&
      state.rebuildable;
  }

  private snapshot(): RebuildUiSnapshot {
    const reason: RebuildReason = this.review === null ?
      'NOT_CHECKED' : this.review.reason;
    const reviewMessage: string = this.review === null ? '' : this.review.message;
    const canOffer: boolean = !this.rebuilding &&
      (this.phase === 'AVAILABLE' ||
        (this.phase === 'FAILED' && this.retryAvailable));
    const result: RebuildUiSnapshot = {
      phase: this.phase,
      reason: reason,
      recoveryError: this.recoveryError,
      reviewMessage: reviewMessage,
      guidance: this.guidance(reason),
      failureMessage: this.failureMessage,
      archiveId: this.archiveId,
      successMessage: this.successMessage,
      lastStatus: this.lastStatus,
      canOfferRebuild: canOffer,
      canConfirm: this.phase === 'CONFIRMING' && !this.rebuilding,
      canCancel: this.phase === 'CONFIRMING' && !this.rebuilding,
      canRetryRead: !this.rebuilding,
      busy: this.phase === 'REBUILDING',
      store: this.phase === 'REBUILT' ? this.rebuiltStore : null
    };
    return result;
  }

  private guidance(reason: RebuildReason): string {
    const rebuildable: boolean = this.phase === 'AVAILABLE' ||
      (this.phase === 'FAILED' && this.retryAvailable);
    if (this.phase === 'REBUILT') {
      return '方案库已重建为空库，可以正常创建、保存和加载方案。';
    }
    if (this.phase === 'CONFIRMING' || this.phase === 'REBUILDING') {
      return '重建会先归档原始损坏文本，再把方案库恢复为空白；不会恢复原方案内容，也不会导入演示方案。';
    }
    return guidanceFor(reason, rebuildable);
  }
}
