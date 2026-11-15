/**
 * BoothLab M2-B plan repository.
 *
 * Implementation notes:
 * - Every mutation runs through one serial promise queue.
 * - The full candidate store is validated, serialized and written BEFORE the
 *   committed in-memory store is replaced. A failed/false write returns
 *   PERSISTENCE_ERROR and leaves the committed store untouched (no fake save).
 * - Caller-supplied data is snapshotted at request time, before it enters the
 *   queue, so later caller mutations cannot alter a queued operation.
 * - listPlans/loadPlan/getStore return independent deep clones.
 * - The backup written with each new primary is the previous CONFIRMED valid
 *   primary text (or the valid backup loaded during recovery), never the new
 *   candidate itself.
 * - Recovery never overwrites storage. First launch (no primary) yields an
 *   empty store. Corrupt primary falls back to a valid backup with an explicit
 *   message. Unknown schema and double corruption surface as errors and
 *   mutations are refused until an explicit recoverStore succeeds.
 *
 * The default MemorySnapshotStorage is NOT durable; B02 will pass a durable
 * Preferences-backed SnapshotStorage without changing this repository's API.
 */

import {
  BoothPlan,
  OperationCode,
  OperationResult,
  PlanStore
} from '../model/BoothModels';
import { PlanRepositoryPort, SaveState, SnapshotStorage } from '../model/M2Contracts';
import { getTemplateById } from '../catalog/BoothTemplates';
import { MemorySnapshotStorage } from './MemorySnapshotStorage';
import {
  cloneObjects,
  clonePlan,
  cloneStore,
  errorResult,
  MAX_PLAN_NAME_LENGTH,
  okResult,
  PLAN_SCHEMA_VERSION,
  validatePlan,
  validateStore
} from './PlanValidator';
import { parseStore, serializeStore } from './PlanSerializer';
import {
  ArchivedSnapshot,
  RebuildPhase,
  RebuildReason,
  RebuildResult,
  RebuildState,
  RebuildStatus,
  RecoveryArchivePort,
  RecoverySlotState
} from './RecoveryContracts';

function createEmptyStore(): PlanStore {
  const store: PlanStore = {
    schemaVersion: PLAN_SCHEMA_VERSION,
    plans: [],
    activePlanId: null
  };
  return store;
}

/**
 * The exact primary/backup texts the user last reviewed, plus their
 * classification. rebuildStore re-reads and compares against this before any
 * destructive step, so external changes are not silently overwritten.
 */
interface ReviewedSnapshot {
  primaryText: string | null;
  backupText: string | null;
  primary: RecoverySlotState;
  backup: RecoverySlotState;
  reason: RebuildReason;
  rebuildable: boolean;
  recovered: boolean;
  message: string;
}

export class PlanRepository implements PlanRepositoryPort {
  private storage: SnapshotStorage;
  private archivePort: RecoveryArchivePort | null;
  private store: PlanStore = createEmptyStore();
  private queueTail: Promise<void> = Promise.resolve();
  private ready: boolean = false;
  private recoveryAttempted: boolean = false;
  private recoveryFailure: OperationResult<PlanStore> | null = null;
  /** Exact text most recently confirmed durable, used as the next backup. */
  private confirmedSerialized: string | null = null;
  private idCounter: number = 0;
  private revision: number = 0;
  private saveState: SaveState = 'Saved';
  /** Last reviewed recovery outcome; null until recoverStore/ensureReady runs. */
  private reviewed: ReviewedSnapshot | null = null;
  private rebuildInProgress: boolean = false;
  private rebuildCompleted: boolean = false;
  private lastArchiveId: string | null = null;

  /**
   * The existing constructor remains source-compatible. Passing the same
   * PreferencesStore as the second argument enables explicit safe rebuild.
   */
  constructor(storage: SnapshotStorage = new MemorySnapshotStorage(),
    archivePort: RecoveryArchivePort | null = null) {
    this.storage = storage;
    this.archivePort = archivePort;
  }

  // ------------------------------------------------------------------
  // Serial queue
  // ------------------------------------------------------------------

  private enqueue<T>(task: () => Promise<OperationResult<T>>): Promise<OperationResult<T>> {
    const previous: Promise<void> = this.queueTail;
    const run: Promise<OperationResult<T>> = previous.then(
      (): Promise<OperationResult<T>> => {
        return task().catch((): OperationResult<T> => {
          // A rejected storage promise is a persistence failure, never a fake
          // success. The normalized tail below keeps the queue usable.
          this.saveState = 'SaveError';
          return errorResult<T>('PERSISTENCE_ERROR', '仓库操作发生未预期错误，未修改内存状态。');
        });
      }
    );
    this.queueTail = run.then(
      (): void => {},
      (): void => {}
    );
    return run;
  }

  // ------------------------------------------------------------------
  // Recovery
  // ------------------------------------------------------------------

  private setReady(store: PlanStore, confirmedSerialized: string | null): void {
    this.store = cloneStore(store);
    this.confirmedSerialized = confirmedSerialized;
    this.ready = true;
    this.recoveryAttempted = true;
    this.recoveryFailure = null;
    this.saveState = 'Saved';
  }

  private failRecovery(code: OperationCode, message: string): OperationResult<PlanStore> {
    // A failed (re)load must never leave a previous ready=true bypassing the
    // protection: all mutations stay refused until an explicit recovery works.
    this.ready = false;
    this.recoveryAttempted = true;
    const failure: OperationResult<PlanStore> = {
      code: code,
      message: message
    };
    this.recoveryFailure = failure;
    this.saveState = 'SaveError';
    return failure;
  }

  private async readPrimaryGuarded(): Promise<OperationResult<string | null>> {
    let result: OperationResult<string | null>;
    try {
      result = await this.storage.readPrimary();
    } catch (error) {
      return errorResult<string | null>('PERSISTENCE_ERROR',
        '读取主快照失败（IO 异常）。');
    }
    if (result.code !== 'OK') {
      return result;
    }
    if (result.data === undefined) {
      return errorResult<string | null>('PERSISTENCE_ERROR',
        '读取主快照成功但缺少数据。');
    }
    return result;
  }

  private async readBackupGuarded(): Promise<OperationResult<string | null>> {
    let result: OperationResult<string | null>;
    try {
      result = await this.storage.readBackup();
    } catch (error) {
      return errorResult<string | null>('PERSISTENCE_ERROR',
        '读取备份快照失败（IO 异常）。');
    }
    if (result.code !== 'OK') {
      return result;
    }
    if (result.data === undefined) {
      return errorResult<string | null>('PERSISTENCE_ERROR',
        '读取备份快照成功但缺少数据。');
    }
    return result;
  }

  private recordReview(primaryText: string | null, backupText: string | null,
    primary: RecoverySlotState, backup: RecoverySlotState, reason: RebuildReason,
    rebuildable: boolean, recovered: boolean, message: string): void {
    const review: ReviewedSnapshot = {
      primaryText: primaryText,
      backupText: backupText,
      primary: primary,
      backup: backup,
      reason: reason,
      rebuildable: rebuildable,
      recovered: recovered,
      message: message
    };
    this.reviewed = review;
  }

  private failReviewed(code: OperationCode, message: string,
    primaryText: string | null, backupText: string | null,
    primary: RecoverySlotState, backup: RecoverySlotState,
    reason: RebuildReason, rebuildable: boolean): OperationResult<PlanStore> {
    this.recordReview(primaryText, backupText, primary, backup, reason, rebuildable,
      false, message);
    return this.failRecovery(code, message);
  }

  /**
   * Recovers from a damaged/missing primary. `primaryMissing` distinguishes an
   * absent first-launch key from corrupt content; only both-missing is empty.
   * The reviewed snapshot records exactly what was seen so a later rebuild can
   * detect external changes before doing anything destructive.
   */
  private async recoverFromBackup(primaryMissing: boolean, primaryText: string | null,
    primaryState: RecoverySlotState): Promise<OperationResult<PlanStore>> {
    const backupRead: OperationResult<string | null> = await this.readBackupGuarded();
    if (backupRead.code !== 'OK') {
      let backupState: RecoverySlotState = 'IO_ERROR';
      let reason: RebuildReason = 'IO_ERROR';
      if (backupRead.code === 'UNSUPPORTED_SCHEMA') {
        backupState = 'UNSUPPORTED_SCHEMA';
        reason = 'FUTURE_SCHEMA';
      } else if (backupRead.code === 'CORRUPTED_DATA') {
        backupState = 'CORRUPTED';
        reason = 'INCOMPLETE_DAMAGE';
      }
      return this.failReviewed('PERSISTENCE_ERROR',
        '读取备份快照失败：' + backupRead.message,
        primaryText, null, primaryState, backupState, reason, false);
    }
    const backupData: string | null | undefined = backupRead.data;
    if (backupData === null) {
      if (primaryMissing) {
        const empty: PlanStore = createEmptyStore();
        this.recordReview(null, null, 'MISSING', 'MISSING', 'NO_REBUILD_NEEDED',
          false, true, '首次启动，方案库为空。');
        this.setReady(empty, null);
        return okResult<PlanStore>('首次启动，方案库为空。', cloneStore(empty));
      }
      return this.failReviewed('CORRUPTED_DATA',
        '主快照损坏且没有可用备份，未覆盖任何数据。',
        primaryText, null, primaryState, 'MISSING', 'INCOMPLETE_DAMAGE', false);
    }
    if (backupData === undefined) {
      return this.failReviewed('PERSISTENCE_ERROR', '备份快照读取结果缺少数据。',
        primaryText, null, primaryState, 'IO_ERROR', 'IO_ERROR', false);
    }

    const backupText: string = backupData;
    const backupParse: OperationResult<PlanStore> = parseStore(backupText);
    if (backupParse.code === 'UNSUPPORTED_SCHEMA') {
      return this.failReviewed('UNSUPPORTED_SCHEMA', backupParse.message,
        primaryText, backupText, primaryState, 'UNSUPPORTED_SCHEMA',
        'FUTURE_SCHEMA', false);
    }
    if (backupParse.code !== 'OK' || backupParse.data === undefined) {
      if (primaryMissing) {
        return this.failReviewed('CORRUPTED_DATA',
          '主快照缺失且备份损坏，未覆盖任何数据。',
          null, backupText, 'MISSING', 'CORRUPTED', 'INCOMPLETE_DAMAGE', false);
      }
      const bothCorrupt: boolean =
        primaryState === 'CORRUPTED' && primaryText !== null;
      const reason: RebuildReason = bothCorrupt ? 'BOTH_CORRUPT' : 'INCOMPLETE_DAMAGE';
      const message: string = bothCorrupt ?
        '主快照与备份均已损坏，未覆盖任何数据。' :
        '主快照不可用且备份损坏，未覆盖任何数据。';
      return this.failReviewed('CORRUPTED_DATA', message,
        primaryText, backupText, primaryState, 'CORRUPTED', reason, bothCorrupt);
    }

    const message: string = primaryMissing ?
      '主快照缺失，已从有效备份恢复；主快照将在下次成功保存时重写。' :
      '主快照损坏，已从有效备份恢复；主快照将在下次成功保存时重写。';
    this.recordReview(primaryText, backupText, primaryState, 'VALID',
      'NO_REBUILD_NEEDED', false, true, message);
    this.setReady(backupParse.data, backupText);
    return okResult<PlanStore>(message, cloneStore(backupParse.data));
  }

  /**
   * With a valid primary, the backup is still probed. A corrupt/missing/IO
   * backup does not block the valid primary, but a future-schema backup does:
   * publishing the primary as ready would let ordinary mutations rotate the
   * previous confirmed primary into that unknown backup and destroy it.
   * Therefore a future backup makes the whole recovery fail closed.
   */
  private async probeBackupAfterPrimary(primaryText: string,
    primaryStore: PlanStore): Promise<OperationResult<PlanStore>> {
    const backupRead: OperationResult<string | null> = await this.readBackupGuarded();
    if (backupRead.code === 'UNSUPPORTED_SCHEMA') {
      return this.failReviewed('UNSUPPORTED_SCHEMA',
        '备份快照为未知未来版本，已禁止载入和所有普通写入。',
        primaryText, null, 'VALID', 'UNSUPPORTED_SCHEMA', 'FUTURE_SCHEMA', false);
    }
    if (backupRead.code !== 'OK') {
      this.recordReview(primaryText, null, 'VALID', 'IO_ERROR', 'NO_REBUILD_NEEDED',
        false, true, '方案库已从主快照恢复；备份快照读取失败。');
      return okResult<PlanStore>('备份快照读取失败，不影响主快照恢复。',
        cloneStore(primaryStore));
    }
    const backupData: string | null | undefined = backupRead.data;
    if (backupData === null) {
      this.recordReview(primaryText, null, 'VALID', 'MISSING', 'NO_REBUILD_NEEDED',
        false, true, '方案库已从主快照恢复。');
      return okResult<PlanStore>('备份缺失，不影响主快照恢复。',
        cloneStore(primaryStore));
    }
    if (backupData === undefined) {
      this.recordReview(primaryText, null, 'VALID', 'IO_ERROR', 'NO_REBUILD_NEEDED',
        false, true, '方案库已从主快照恢复；备份快照缺少数据。');
      return okResult<PlanStore>('备份快照缺少数据，不影响主快照恢复。',
        cloneStore(primaryStore));
    }
    const backupParse: OperationResult<PlanStore> = parseStore(backupData);
    if (backupParse.code === 'UNSUPPORTED_SCHEMA') {
      return this.failReviewed('UNSUPPORTED_SCHEMA',
        '备份快照为未知未来版本，已禁止载入和所有普通写入。',
        primaryText, backupData, 'VALID', 'UNSUPPORTED_SCHEMA', 'FUTURE_SCHEMA', false);
    }
    const backupState: RecoverySlotState =
      backupParse.code === 'OK' ? 'VALID' : 'CORRUPTED';
    this.recordReview(primaryText, backupData, 'VALID', backupState,
      'NO_REBUILD_NEEDED', false, true, '方案库已从主快照恢复。');
    return okResult<PlanStore>('备份快照不阻止主快照恢复。',
      cloneStore(primaryStore));
  }

  private async runRecovery(): Promise<OperationResult<PlanStore>> {
    const primaryRead: OperationResult<string | null> = await this.readPrimaryGuarded();
    if (primaryRead.code === 'CORRUPTED_DATA') {
      // Wrong stored type from the storage adapter is corrupt primary data.
      return this.recoverFromBackup(false, null, 'CORRUPTED');
    }
    if (primaryRead.code !== 'OK') {
      if (primaryRead.code === 'UNSUPPORTED_SCHEMA') {
        return this.failReviewed('UNSUPPORTED_SCHEMA', primaryRead.message,
          null, null, 'UNSUPPORTED_SCHEMA', 'UNKNOWN', 'FUTURE_SCHEMA', false);
      }
      return this.failReviewed('PERSISTENCE_ERROR',
        '读取主快照失败：' + primaryRead.message,
        null, null, 'IO_ERROR', 'UNKNOWN', 'IO_ERROR', false);
    }

    const primaryData: string | null | undefined = primaryRead.data;
    if (primaryData === null) {
      return this.recoverFromBackup(true, null, 'MISSING');
    }
    if (primaryData === undefined) {
      return this.failReviewed('PERSISTENCE_ERROR', '主快照读取结果缺少数据。',
        null, null, 'IO_ERROR', 'UNKNOWN', 'IO_ERROR', false);
    }

    const primaryText: string = primaryData;
    const primaryParse: OperationResult<PlanStore> = parseStore(primaryText);
    if (primaryParse.code === 'OK' && primaryParse.data !== undefined) {
      const primaryStore: PlanStore = primaryParse.data;
      const probe: OperationResult<PlanStore> =
        await this.probeBackupAfterPrimary(primaryText, primaryStore);
      if (probe.code !== 'OK') {
        return probe;
      }
      this.setReady(primaryStore, primaryText);
      return okResult<PlanStore>('方案库已从主快照恢复。', cloneStore(primaryStore));
    }
    if (primaryParse.code === 'UNSUPPORTED_SCHEMA') {
      // Protect newer data: do not load the backup and do not overwrite anything.
      return this.failReviewed('UNSUPPORTED_SCHEMA', primaryParse.message,
        primaryText, null, 'UNSUPPORTED_SCHEMA', 'UNKNOWN', 'FUTURE_SCHEMA', false);
    }
    return this.recoverFromBackup(false, primaryText, 'CORRUPTED');
  }

  private async runRecoveryGuarded(): Promise<OperationResult<PlanStore>> {
    try {
      return await this.runRecovery();
    } catch (error) {
      return this.failReviewed('PERSISTENCE_ERROR', '恢复方案库时发生未预期错误。',
        null, null, 'UNKNOWN', 'UNKNOWN', 'IO_ERROR', false);
    }
  }

  private async ensureReady(): Promise<OperationResult<boolean>> {
    if (this.ready) {
      return okResult<boolean>('方案库已就绪。', true);
    }
    if (this.recoveryAttempted && this.recoveryFailure !== null) {
      return errorResult<boolean>(this.recoveryFailure.code, this.recoveryFailure.message);
    }
    const recovered: OperationResult<PlanStore> = await this.runRecoveryGuarded();
    if (recovered.code === 'OK') {
      return okResult<boolean>('方案库已恢复。', true);
    }
    return errorResult<boolean>(recovered.code, recovered.message);
  }

  recoverStore(): Promise<OperationResult<PlanStore>> {
    return this.enqueue<PlanStore>(async (): Promise<OperationResult<PlanStore>> => {
      // Drop readiness BEFORE any storage access. If this reload fails after an
      // earlier successful load, ensureReady cannot bypass the failure.
      this.ready = false;
      this.recoveryAttempted = false;
      this.recoveryFailure = null;
      this.reviewed = null;
      this.rebuildCompleted = false;
      this.lastArchiveId = null;
      return this.runRecoveryGuarded();
    });
  }

  // ------------------------------------------------------------------
  // Explicit rebuild of an unrecoverable store
  // ------------------------------------------------------------------

  private makeRebuildResult(status: RebuildStatus, message: string,
    archiveId: string | null, store: PlanStore | null): RebuildResult {
    const result: RebuildResult = {
      status: status,
      message: message,
      archiveId: archiveId,
      store: store
    };
    return result;
  }

  private classifyText(text: string | null): RecoverySlotState {
    if (text === null) {
      return 'MISSING';
    }
    const parsed: OperationResult<PlanStore> = parseStore(text);
    if (parsed.code === 'OK') {
      return 'VALID';
    }
    if (parsed.code === 'UNSUPPORTED_SCHEMA') {
      return 'UNSUPPORTED_SCHEMA';
    }
    return 'CORRUPTED';
  }

  /**
   * Reclassifies a fresh primary/backup pair after an external change. The raw
   * texts become the new reviewed snapshot; the caller must review again.
   */
  private reviewFreshPair(primaryText: string | null, backupText: string | null,
    message: string): void {
    const primaryState: RecoverySlotState = this.classifyText(primaryText);
    const backupState: RecoverySlotState = this.classifyText(backupText);
    let reason: RebuildReason = 'INCOMPLETE_DAMAGE';
    let rebuildable: boolean = false;
    let recovered: boolean = false;
    if (primaryState === 'UNSUPPORTED_SCHEMA' || backupState === 'UNSUPPORTED_SCHEMA') {
      reason = 'FUTURE_SCHEMA';
    } else if (primaryState === 'VALID' || backupState === 'VALID') {
      reason = 'NO_REBUILD_NEEDED';
      recovered = true;
    } else if (primaryState === 'MISSING' && backupState === 'MISSING') {
      reason = 'NO_REBUILD_NEEDED';
      recovered = true;
    } else if (primaryState === 'CORRUPTED' && backupState === 'CORRUPTED' &&
      primaryText !== null && backupText !== null) {
      reason = 'BOTH_CORRUPT';
      rebuildable = true;
    }
    this.recordReview(primaryText, backupText, primaryState, backupState, reason,
      rebuildable, recovered, message);
  }

  /**
   * After any write/verify failure the on-disk pair may have changed partially.
   * Do not keep offering a rebuild from the old reviewed pair; a fresh
   * recoverStore must re-read and re-review first.
   */
  private invalidateReview(message: string): void {
    this.recordReview(null, null, 'UNKNOWN', 'UNKNOWN', 'STATE_UNKNOWN', false,
      false, message);
  }

  /** A read/IO failure: rebuild is blocked but not destructive. */
  private invalidateReviewAsIo(message: string): void {
    this.recordReview(null, null, 'IO_ERROR', 'IO_ERROR', 'IO_ERROR', false,
      false, message);
  }

  getRebuildState(): RebuildState {
    const archiveAvailable: boolean = this.archivePort !== null;
    const review: ReviewedSnapshot | null = this.reviewed;
    if (this.rebuildCompleted) {
      const rebuilt: RebuildState = {
        phase: 'REBUILT',
        rebuildable: false,
        reason: 'ALREADY_REBUILT',
        message: '方案库已重建为空库。',
        primary: 'VALID',
        backup: 'VALID',
        archiveAvailable: archiveAvailable,
        lastArchiveId: this.lastArchiveId
      };
      return rebuilt;
    }
    if (this.rebuildInProgress) {
      const active: RebuildState = {
        phase: 'IN_PROGRESS',
        rebuildable: false,
        reason: review === null ? 'NOT_CHECKED' : review.reason,
        message: '正在执行重建，其他写入保持串行等待。',
        primary: review === null ? 'UNKNOWN' : review.primary,
        backup: review === null ? 'UNKNOWN' : review.backup,
        archiveAvailable: archiveAvailable,
        lastArchiveId: this.lastArchiveId
      };
      return active;
    }
    if (review === null) {
      const unchecked: RebuildState = {
        phase: 'NOT_CHECKED',
        rebuildable: false,
        reason: 'NOT_CHECKED',
        message: '尚未执行恢复审查。',
        primary: 'UNKNOWN',
        backup: 'UNKNOWN',
        archiveAvailable: archiveAvailable,
        lastArchiveId: this.lastArchiveId
      };
      return unchecked;
    }

    let phase: RebuildPhase = 'BLOCKED';
    let reason: RebuildReason = review.reason;
    const canRebuild: boolean =
      review.rebuildable && !review.recovered && archiveAvailable;
    if (review.recovered) {
      phase = 'NOT_NEEDED';
    } else if (canRebuild) {
      phase = 'READY';
    } else {
      phase = 'BLOCKED';
      if (review.rebuildable && !archiveAvailable) {
        reason = 'ARCHIVE_UNAVAILABLE';
      }
    }
    const state: RebuildState = {
      phase: phase,
      rebuildable: canRebuild,
      reason: reason,
      message: review.message,
      primary: review.primary,
      backup: review.backup,
      archiveAvailable: archiveAvailable,
      lastArchiveId: this.lastArchiveId
    };
    return state;
  }

  private enqueueRebuild(task: () => Promise<RebuildResult>): Promise<RebuildResult> {
    const previous: Promise<void> = this.queueTail;
    const run: Promise<RebuildResult> = previous.then(
      (): Promise<RebuildResult> => {
        return task().catch((error: Object): RebuildResult => {
          this.saveState = 'SaveError';
          this.rebuildInProgress = false;
          return this.makeRebuildResult('UNEXPECTED_ERROR',
            '重建发生未预期错误，未发布空库。', null, null);
        });
      }
    );
    this.queueTail = run.then(
      (): void => {},
      (): void => {}
    );
    return run;
  }

  /**
   * Explicit, confirmed rebuild. Without confirmed=true this performs no I/O
   * and no mutation. With confirmation it re-reads the pair, compares it with
   * the reviewed texts, archives the exact raw strings, writes a validator/
   * serializer-produced schema-1 empty store to both primary and backup, then
   * proves the durable values before publishing a ready repository.
   */
  rebuildStore(confirmed: boolean): Promise<RebuildResult> {
    if (!confirmed) {
      return Promise.resolve(this.makeRebuildResult('CANCELLED',
        '未确认重建，方案库和归档均未改动。', null, null));
    }
    return this.enqueueRebuild((): Promise<RebuildResult> => {
      return this.runRebuild();
    });
  }

  private async runRebuild(): Promise<RebuildResult> {
    this.rebuildInProgress = true;
    try {
      return await this.runRebuildBody();
    } finally {
      this.rebuildInProgress = false;
    }
  }

  private async runRebuildBody(): Promise<RebuildResult> {
    if (this.rebuildCompleted) {
      return this.makeRebuildResult('ALREADY_REBUILT',
        '本次会话已完成重建，不再重复写入。', null, cloneStore(this.store));
    }
    const port: RecoveryArchivePort | null = this.archivePort;
    if (port === null) {
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '未配置恢复归档能力，拒绝破坏性重建。', null, null);
    }
    const review: ReviewedSnapshot | null = this.reviewed;
    if (review === null) {
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '尚未执行恢复审查，拒绝重建。', null, null);
    }
    if (!review.recovered && !review.rebuildable) {
      return this.makeRebuildResult('NOT_REBUILDABLE', review.message, null, null);
    }
    if (review.recovered || review.primaryText === null || review.backupText === null) {
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '当前不属于“主备双损坏”场景，拒绝重建。', null, null);
    }

    // TOCTOU guard 1: re-read and require the exact reviewed texts.
    const primaryRead: OperationResult<string | null> = await this.readPrimaryGuarded();
    const primaryValue: string | null | undefined = primaryRead.data;
    if (primaryRead.code !== 'OK' || primaryValue === undefined) {
      this.invalidateReviewAsIo('重建前重新读取主快照失败，已阻止重建。');
      this.saveState = 'SaveError';
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '重建前重新读取主快照失败，已阻止重建。', null, null);
    }
    const backupRead: OperationResult<string | null> = await this.readBackupGuarded();
    const backupValue: string | null | undefined = backupRead.data;
    if (backupRead.code !== 'OK' || backupValue === undefined) {
      this.invalidateReviewAsIo('重建前重新读取备份快照失败，已阻止重建。');
      this.saveState = 'SaveError';
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '重建前重新读取备份快照失败，已阻止重建。', null, null);
    }
    const primaryText: string | null = primaryValue;
    const backupText: string | null = backupValue;
    if (primaryText !== review.primaryText || backupText !== review.backupText) {
      this.reviewFreshPair(primaryText, backupText,
        '主备快照在审查后已变化，请重新审查后再确认。');
      return this.makeRebuildResult('STALE_SNAPSHOT',
        '主备快照在审查后已变化，未写入任何数据。', null, null);
    }
    if (primaryText === null || backupText === null) {
      this.reviewFreshPair(primaryText, backupText,
        '主备快照不完整，请重新审查。');
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '主备快照不完整，拒绝重建。', null, null);
    }

    const primaryParse: OperationResult<PlanStore> = parseStore(primaryText);
    const backupParse: OperationResult<PlanStore> = parseStore(backupText);
    if (primaryParse.code === 'UNSUPPORTED_SCHEMA' ||
      backupParse.code === 'UNSUPPORTED_SCHEMA') {
      this.reviewFreshPair(primaryText, backupText,
        '检测到未知未来版本，禁止破坏性重建。');
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '任一快照为未知未来版本，禁止破坏性重建。', null, null);
    }
    if (primaryParse.code !== 'CORRUPTED_DATA' ||
      backupParse.code !== 'CORRUPTED_DATA') {
      this.reviewFreshPair(primaryText, backupText,
        '主备快照不再同时损坏，请重新审查。');
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '主备快照不再同时损坏，拒绝重建。', null, null);
    }

    // Preserve the exact texts before any destructive write.
    const preserved: OperationResult<ArchivedSnapshot> =
      await port.preserveCorruptedSnapshot(primaryText, backupText);
    const archivedValue: ArchivedSnapshot | undefined = preserved.data;
    if (preserved.code !== 'OK' || archivedValue === undefined) {
      this.saveState = 'SaveError';
      return this.makeRebuildResult('ARCHIVE_FAILED',
        '损坏快照归档失败，未写入空库：' + preserved.message, null, null);
    }
    const archiveId: string = archivedValue.archiveId;

    const empty: PlanStore = createEmptyStore();
    const emptyValidation: OperationResult<PlanStore> = validateStore(empty);
    const emptyStoreValue: PlanStore | undefined = emptyValidation.data;
    if (emptyValidation.code !== 'OK' || emptyStoreValue === undefined) {
      this.invalidateReview('空库校验失败，已阻止重建。');
      this.saveState = 'SaveError';
      return this.makeRebuildResult('EMPTY_WRITE_FAILED',
        '空库校验失败，未写入。', archiveId, null);
    }
    const emptyStore: PlanStore = emptyStoreValue;
    const emptySerialized: OperationResult<string> = serializeStore(emptyStore);
    const emptyTextValue: string | undefined = emptySerialized.data;
    if (emptySerialized.code !== 'OK' || emptyTextValue === undefined) {
      this.invalidateReview('空库序列化失败，已阻止重建。');
      this.saveState = 'SaveError';
      return this.makeRebuildResult('EMPTY_WRITE_FAILED',
        '空库序列化失败，未写入。', archiveId, null);
    }
    const emptyText: string = emptyTextValue;

    // TOCTOU guard 2: nothing may have changed between archive and overwrite.
    const primaryAgain: OperationResult<string | null> = await this.readPrimaryGuarded();
    const backupAgain: OperationResult<string | null> = await this.readBackupGuarded();
    const primaryAgainValue: string | null | undefined = primaryAgain.data;
    const backupAgainValue: string | null | undefined = backupAgain.data;
    if (primaryAgain.code !== 'OK' || primaryAgainValue === undefined ||
      backupAgain.code !== 'OK' || backupAgainValue === undefined) {
      this.invalidateReviewAsIo('归档后复核主备快照失败，拒绝写入空库。');
      this.saveState = 'SaveError';
      return this.makeRebuildResult('NOT_REBUILDABLE',
        '归档后复核主备快照失败，拒绝写入空库。', archiveId, null);
    }
    if (primaryAgainValue !== primaryText || backupAgainValue !== backupText) {
      this.reviewFreshPair(primaryAgainValue, backupAgainValue,
        '归档后主备快照再次变化，拒绝写入空库。');
      return this.makeRebuildResult('STALE_SNAPSHOT',
        '归档后主备快照再次变化，未写入空库。', archiveId, null);
    }

    // Both keys receive the same valid schema-1 empty store. The backup is
    // written first by PreferencesStore, so a primary flush failure leaves a
    // recoverable empty backup (documented partial-key semantics).
    const written: OperationResult<boolean> =
      await this.storage.write(emptyText, emptyText);
    if (written.code !== 'OK' || written.data !== true) {
      const detail: string = written.message.length > 0 ?
        written.message : '空库写入未确认成功。';
      this.invalidateReview('空库写入失败，未发布就绪状态：' + detail);
      this.saveState = 'SaveError';
      return this.makeRebuildResult('EMPTY_WRITE_FAILED',
        '空库写入失败，未发布就绪状态：' + detail, archiveId, null);
    }

    const verified: OperationResult<boolean> =
      await port.verifyRebuiltStore(emptyText, emptyText);
    if (verified.code !== 'OK' || verified.data !== true) {
      const detail: string = verified.message.length > 0 ?
        verified.message : '空库落盘校验未确认成功。';
      this.invalidateReview('空库落盘校验失败，未发布就绪状态：' + detail);
      this.saveState = 'SaveError';
      return this.makeRebuildResult('VERIFY_FAILED',
        '空库落盘校验失败，未发布就绪状态：' + detail, archiveId, null);
    }

    this.store = cloneStore(emptyStore);
    this.confirmedSerialized = emptyText;
    this.ready = true;
    this.recoveryAttempted = true;
    this.recoveryFailure = null;
    this.saveState = 'Saved';
    this.rebuildCompleted = true;
    this.lastArchiveId = archiveId;
    this.recordReview(emptyText, emptyText, 'VALID', 'VALID', 'ALREADY_REBUILT',
      false, true, '方案库已重建为空库，原始损坏快照已归档。');
    return this.makeRebuildResult('REBUILT',
      '方案库已重建为空库，原始损坏快照已归档。', archiveId,
      cloneStore(emptyStore));
  }

  // ------------------------------------------------------------------
  // Persistence and publication
  // ------------------------------------------------------------------

  private async persistCandidate(candidate: PlanStore): Promise<OperationResult<string>> {
    const validation: OperationResult<PlanStore> = validateStore(candidate);
    if (validation.code !== 'OK' || validation.data === undefined) {
      return errorResult<string>(validation.code, validation.message);
    }
    const serialized: OperationResult<string> = serializeStore(validation.data);
    if (serialized.code !== 'OK' || serialized.data === undefined) {
      return errorResult<string>(serialized.code, serialized.message);
    }

    const nextPrimary: string = serialized.data;
    const previousConfirmed: string | null = this.confirmedSerialized;
    const writeResult: OperationResult<boolean> =
      await this.storage.write(nextPrimary, previousConfirmed);
    if (writeResult.code !== 'OK' || writeResult.data !== true) {
      const detail: string = writeResult.message.length > 0 ?
        writeResult.message : '快照写入未确认成功。';
      return errorResult<string>('PERSISTENCE_ERROR', detail);
    }
    return okResult<string>('快照已写入。', nextPrimary);
  }

  private publish(candidate: PlanStore, serializedPrimary: string, startRevision: number): void {
    this.store = cloneStore(candidate);
    this.confirmedSerialized = serializedPrimary;
    if (this.revision === startRevision) {
      this.saveState = 'Saved';
    } else {
      // A newer local edit happened while this write was in flight.
      this.saveState = 'Dirty';
    }
  }

  private noteFailure(): void {
    this.saveState = 'SaveError';
  }

  // ------------------------------------------------------------------
  // Lookup helpers
  // ------------------------------------------------------------------

  private findPlanIndex(planId: string): number {
    for (let i = 0; i < this.store.plans.length; i++) {
      if (this.store.plans[i].id === planId) {
        return i;
      }
    }
    return -1;
  }

  private findPlan(planId: string): BoothPlan | null {
    const index: number = this.findPlanIndex(planId);
    if (index < 0) {
      return null;
    }
    return this.store.plans[index];
  }

  private containsPlan(store: PlanStore, planId: string): boolean {
    for (let i = 0; i < store.plans.length; i++) {
      if (store.plans[i].id === planId) {
        return true;
      }
    }
    return false;
  }

  private generatePlanId(store: PlanStore): string {
    const now: number = Date.now();
    const base: number = Number.isFinite(now) && now >= 0 ? now : 0;
    let candidate: string = '';
    do {
      this.idCounter = this.idCounter + 1;
      candidate = 'plan-' + base.toString(36) + '-' + this.idCounter.toString(36);
    } while (this.containsPlan(store, candidate));
    return candidate;
  }

  // ------------------------------------------------------------------
  // PlanRepositoryPort: mutations
  // ------------------------------------------------------------------

  createPlan(name: string, templateId: string): Promise<OperationResult<BoothPlan>> {
    const nameSnapshot: string = typeof name === 'string' ? name : '';
    const templateSnapshot: string = typeof templateId === 'string' ? templateId : '';
    // Capture the revision at request time: a later markDirty (queued or while
    // the write is in flight) must prevent this completion from reporting Saved.
    const startRevision: number = this.revision;
    return this.enqueue<BoothPlan>(async (): Promise<OperationResult<BoothPlan>> => {
      const readyResult: OperationResult<boolean> = await this.ensureReady();
      if (readyResult.code !== 'OK') {
        return errorResult<BoothPlan>(readyResult.code, readyResult.message);
      }

      const trimmedName: string = nameSnapshot.trim();
      if (trimmedName.length < 1 || trimmedName.length > MAX_PLAN_NAME_LENGTH) {
        return errorResult<BoothPlan>('INVALID_ARGUMENT',
          '展位方案名称去除首尾空白后长度必须为 1 到 ' + MAX_PLAN_NAME_LENGTH + ' 个字符。');
      }
      if (getTemplateById(templateSnapshot) === undefined) {
        return errorResult<BoothPlan>('INVALID_ARGUMENT', '未知的展位模板：' + templateSnapshot + '。');
      }

      const now: number = Date.now();
      if (!Number.isFinite(now)) {
        return errorResult<BoothPlan>('INVALID_ARGUMENT', '系统时间无效，无法创建方案。');
      }
      const plan: BoothPlan = {
        id: this.generatePlanId(this.store),
        name: trimmedName,
        templateId: templateSnapshot,
        objects: [],
        createdAt: now,
        updatedAt: now
      };

      const candidate: PlanStore = cloneStore(this.store);
      candidate.plans.push(plan);

      this.saveState = 'Saving';
      const persisted: OperationResult<string> = await this.persistCandidate(candidate);
      if (persisted.code !== 'OK' || persisted.data === undefined) {
        this.noteFailure();
        return errorResult<BoothPlan>(persisted.code, persisted.message);
      }
      this.publish(candidate, persisted.data, startRevision);
      return okResult<BoothPlan>('展位方案已创建。', clonePlan(plan));
    });
  }

  openPlan(planId: string): Promise<OperationResult<BoothPlan>> {
    const planIdSnapshot: string = typeof planId === 'string' ? planId : '';
    const startRevision: number = this.revision;
    return this.enqueue<BoothPlan>(async (): Promise<OperationResult<BoothPlan>> => {
      const readyResult: OperationResult<boolean> = await this.ensureReady();
      if (readyResult.code !== 'OK') {
        return errorResult<BoothPlan>(readyResult.code, readyResult.message);
      }
      const target: BoothPlan | null = this.findPlan(planIdSnapshot);
      if (target === null) {
        return errorResult<BoothPlan>('NOT_FOUND', '未找到要打开的展位方案。');
      }

      const candidate: PlanStore = cloneStore(this.store);
      candidate.activePlanId = planIdSnapshot;

      this.saveState = 'Saving';
      const persisted: OperationResult<string> = await this.persistCandidate(candidate);
      if (persisted.code !== 'OK' || persisted.data === undefined) {
        this.noteFailure();
        return errorResult<BoothPlan>(persisted.code, persisted.message);
      }
      this.publish(candidate, persisted.data, startRevision);
      return okResult<BoothPlan>('已打开展位方案。', clonePlan(target));
    });
  }

  deletePlan(planId: string, confirmed: boolean): Promise<OperationResult<boolean>> {
    if (!confirmed) {
      return Promise.resolve(
        okResult<boolean>('未确认删除，方案库保持不变。', false)
      );
    }
    const planIdSnapshot: string = typeof planId === 'string' ? planId : '';
    const startRevision: number = this.revision;
    return this.enqueue<boolean>(async (): Promise<OperationResult<boolean>> => {
      const readyResult: OperationResult<boolean> = await this.ensureReady();
      if (readyResult.code !== 'OK') {
        return errorResult<boolean>(readyResult.code, readyResult.message);
      }
      const index: number = this.findPlanIndex(planIdSnapshot);
      if (index < 0) {
        return errorResult<boolean>('NOT_FOUND', '未找到要删除的展位方案。');
      }

      const candidate: PlanStore = cloneStore(this.store);
      const remaining: BoothPlan[] = [];
      for (let i = 0; i < candidate.plans.length; i++) {
        if (i !== index) {
          remaining.push(candidate.plans[i]);
        }
      }
      candidate.plans = remaining;
      if (candidate.activePlanId === planIdSnapshot) {
        candidate.activePlanId = null;
      }

      this.saveState = 'Saving';
      const persisted: OperationResult<string> = await this.persistCandidate(candidate);
      if (persisted.code !== 'OK' || persisted.data === undefined) {
        this.noteFailure();
        return errorResult<boolean>(persisted.code, persisted.message);
      }
      this.publish(candidate, persisted.data, startRevision);
      return okResult<boolean>('展位方案已删除。', true);
    });
  }

  savePlan(plan: BoothPlan): Promise<OperationResult<BoothPlan>> {
    if (plan === null || typeof plan !== 'object' || Array.isArray(plan)) {
      return Promise.resolve(
        errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案必须是对象。')
      );
    }
    // Validate and deep-copy immediately: this is the enqueue-time snapshot.
    const incomingValidation: OperationResult<BoothPlan> = validatePlan(plan);
    if (incomingValidation.code !== 'OK' || incomingValidation.data === undefined) {
      return Promise.resolve(
        errorResult<BoothPlan>(incomingValidation.code, incomingValidation.message)
      );
    }
    const snapshot: BoothPlan = incomingValidation.data;
    const startRevision: number = this.revision;

    return this.enqueue<BoothPlan>(async (): Promise<OperationResult<BoothPlan>> => {
      const readyResult: OperationResult<boolean> = await this.ensureReady();
      if (readyResult.code !== 'OK') {
        return errorResult<BoothPlan>(readyResult.code, readyResult.message);
      }
      const index: number = this.findPlanIndex(snapshot.id);
      if (index < 0) {
        return errorResult<BoothPlan>('NOT_FOUND', '未找到要保存的展位方案。');
      }
      const existing: BoothPlan = this.store.plans[index];

      // Identity metadata is immutable. Reject instead of silently merging so a
      // stale/foreign snapshot can never masquerade as a valid save.
      if (snapshot.templateId !== existing.templateId) {
        return errorResult<BoothPlan>('INVALID_ARGUMENT',
          '保存时不能修改展位方案的模板。');
      }
      if (snapshot.createdAt !== existing.createdAt) {
        return errorResult<BoothPlan>('INVALID_ARGUMENT',
          '保存时不能修改展位方案的创建时间。');
      }
      if (snapshot.updatedAt < existing.updatedAt) {
        return errorResult<BoothPlan>('INVALID_ARGUMENT',
          '保存的更新时间早于已有版本，已拒绝旧快照覆盖新数据。');
      }

      // Only name, objects and updatedAt come from the caller.
      const merged: BoothPlan = {
        id: existing.id,
        name: snapshot.name,
        templateId: existing.templateId,
        objects: cloneObjects(snapshot.objects),
        createdAt: existing.createdAt,
        updatedAt: snapshot.updatedAt
      };
      const mergedValidation: OperationResult<BoothPlan> = validatePlan(merged);
      if (mergedValidation.code !== 'OK' || mergedValidation.data === undefined) {
        return errorResult<BoothPlan>(mergedValidation.code, mergedValidation.message);
      }

      const candidate: PlanStore = cloneStore(this.store);
      candidate.plans[index] = mergedValidation.data;

      this.saveState = 'Saving';
      const persisted: OperationResult<string> = await this.persistCandidate(candidate);
      if (persisted.code !== 'OK' || persisted.data === undefined) {
        this.noteFailure();
        return errorResult<BoothPlan>(persisted.code, persisted.message);
      }
      this.publish(candidate, persisted.data, startRevision);
      return okResult<BoothPlan>('展位方案已保存。', clonePlan(mergedValidation.data));
    });
  }

  // ------------------------------------------------------------------
  // PlanRepositoryPort: reads and SaveState
  // ------------------------------------------------------------------

  listPlans(): BoothPlan[] {
    const plans: BoothPlan[] = [];
    for (let i = 0; i < this.store.plans.length; i++) {
      plans.push(clonePlan(this.store.plans[i]));
    }
    plans.sort((a: BoothPlan, b: BoothPlan): number => {
      if (a.updatedAt !== b.updatedAt) {
        return b.updatedAt - a.updatedAt;
      }
      if (a.createdAt !== b.createdAt) {
        return b.createdAt - a.createdAt;
      }
      if (a.id < b.id) {
        return -1;
      }
      if (a.id > b.id) {
        return 1;
      }
      return 0;
    });
    return plans;
  }

  loadPlan(planId: string): OperationResult<BoothPlan> {
    const plan: BoothPlan | null = this.findPlan(planId);
    if (plan === null) {
      return errorResult<BoothPlan>('NOT_FOUND', '未找到指定的展位方案。');
    }
    return okResult<BoothPlan>('展位方案已读取。', clonePlan(plan));
  }

  getStore(): PlanStore {
    return cloneStore(this.store);
  }

  getSaveState(): SaveState {
    return this.saveState;
  }

  markDirty(): void {
    this.revision = this.revision + 1;
    this.saveState = 'Dirty';
  }
}
