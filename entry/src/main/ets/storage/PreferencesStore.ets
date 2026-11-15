/**
 * Durable BoothLab M2-B snapshot storage backed by the platform Preferences
 * XML file.
 *
 * Platform access is isolated behind the exported `PreferencesIO` seam so the
 * durable-versus-cached semantics can be tested without a device context. The
 * only production implementation is `ActualPlatformPreferencesIO`; it alone
 * owns the Preferences instance, the application context and the file name.
 *
 * Write protocol (schemaVersion 1 text validated by PlanSerializer):
 *   1. if a backup is present: put(BACKUP_KEY) then flush()
 *   2. put(PRIMARY_KEY) then flush()
 * Success is reported only after the primary flush succeeds.
 *
 * The platform has no atomic multi-key transaction and flush may partially
 * commit. On any put/flush failure this adapter marks the cache as uncertain
 * before attempting to remove the in-memory Preferences instance (which may
 * hold an unconfirmed put). While the cache is uncertain, every read and write
 * is refused before put/flush. The flag is cleared only after the platform
 * confirms the cache removal AND fresh durable reads succeed; a prior write
 * failure is not treated as recovery by reading from a possibly cached
 * instance. If removal cannot be confirmed, the adapter stays blocked instead
 * of risking a later flush of the unconfirmed value. The previously confirmed
 * primary or backup is never deleted or blindly overwritten.
 *
 * @kit ArkData
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { OperationResult, PlanStore } from '../model/BoothModels';
import { SnapshotStorage } from '../model/M2Contracts';
import { errorResult, okResult } from '../repository/PlanValidator';
import { parseStore } from '../repository/PlanSerializer';
import {
  ArchivedSnapshot,
  RecoveryArchivePort
} from '../repository/RecoveryContracts';

/** Stable Preferences file name used by the application bootstrap. */
export const PREFERENCES_NAME: string = 'boothlab_plans_v1';
/** Stable key holding the latest confirmed complete schemaVersion-1 snapshot. */
export const PRIMARY_KEY: string = 'plans_primary_v1';
/** Stable key holding the previous confirmed snapshot. */
export const BACKUP_KEY: string = 'plans_backup_v1';
/**
 * Conservative per-value bound for Preferences values. Values larger than this
 * are rejected explicitly instead of being silently truncated by the platform.
 */
export const MAX_SNAPSHOT_TEXT_LENGTH: number = 8192;
/**
 * Prefix for immutable recovery archives. The complete keys are
 * `${PREFIX}${archiveId}_primary_v1` and `${PREFIX}${archiveId}_backup_v1`.
 * Archive ids are never reused; an existing key blocks the write instead of
 * being overwritten.
 */
export const RECOVERY_ARCHIVE_KEY_PREFIX: string = 'recovery_archive_v1_';

export function archivePrimaryKey(archiveId: string): string {
  return RECOVERY_ARCHIVE_KEY_PREFIX + archiveId + '_primary_v1';
}

export function archiveBackupKey(archiveId: string): string {
  return RECOVERY_ARCHIVE_KEY_PREFIX + archiveId + '_backup_v1';
}

/**
 * Minimal asynchronous Preferences seam. `read` must return null for an absent
 * key, `put` stages a value in the platform cache, `flush` commits the cache to
 * disk and `discardCache` drops the cached instance so the next read loads the
 * durable file again.
 */
export interface PreferencesIO {
  read(key: string): Promise<OperationResult<string | null>>;
  put(key: string, value: string): Promise<OperationResult<boolean>>;
  flush(): Promise<OperationResult<boolean>>;
  discardCache(): Promise<OperationResult<boolean>>;
}

function isTrueResult(result: OperationResult<boolean>): boolean {
  return result.code === 'OK' && result.data === true;
}

function failureMessage(result: OperationResult<boolean>, fallback: string): string {
  if (result.message.length > 0) {
    return result.message;
  }
  return fallback;
}

/**
 * Durable SnapshotStorage. Writes are serialized inside this class as well as
 * by PlanRepository, so a standalone caller can never overlap the two-flush
 * backend protocol. Reads wait for an in-flight write to settle.
 */
export class PreferencesStore implements SnapshotStorage, RecoveryArchivePort {
  readonly durable: boolean = true;
  private io: PreferencesIO;
  private writeTail: Promise<void> = Promise.resolve();
  /**
   * True when a failed write may still be present in the platform cache and
   * cache removal has not been confirmed. Reads and writes are fail-closed in
   * this state.
   */
  private cacheUncertain: boolean = false;
  /** Monotonic part of archive ids; existence checks still guard collisions. */
  private archiveCounter: number = 0;

  /** Production construction through the platform Preferences adapter. */
  static async create(context: common.Context): Promise<OperationResult<PreferencesStore>> {
    try {
      const io: ActualPlatformPreferencesIO = new ActualPlatformPreferencesIO(context);
      const opened: OperationResult<boolean> = await io.initialize();
      if (opened.code !== 'OK') {
        return errorResult<PreferencesStore>(opened.code, opened.message);
      }
      return okResult<PreferencesStore>('Preferences 持久化存储已就绪。',
        new PreferencesStore(io));
    } catch (error) {
      return errorResult<PreferencesStore>('PERSISTENCE_ERROR',
        '初始化 Preferences 持久化存储失败。');
    }
  }

  /** Test seam: production code must use `create`; mocks inject a fake IO. */
  constructor(io: PreferencesIO) {
    this.io = io;
  }

  // ------------------------------------------------------------------
  // Reads
  // ------------------------------------------------------------------

  private async waitForWrites(): Promise<void> {
    try {
      await this.writeTail;
    } catch (error) {
      // The queue tail is normalized; this is defensive only.
    }
  }

  private async readIo(key: string): Promise<OperationResult<string | null>> {
    let result: OperationResult<string | null>;
    try {
      result = await this.io.read(key);
    } catch (error) {
      return errorResult<string | null>('PERSISTENCE_ERROR',
        '读取 Preferences 值失败（IO 异常）。');
    }
    if (result.code !== 'OK') {
      return result;
    }
    if (result.data === undefined) {
      return errorResult<string | null>('PERSISTENCE_ERROR',
        '读取 Preferences 成功但缺少数据。');
    }
    if (result.data === null) {
      return okResult<string | null>('Preferences 中不存在该值。', null);
    }
    if (typeof result.data !== 'string') {
      return errorResult<string | null>('CORRUPTED_DATA',
        'Preferences 中存储的值不是字符串，数据已损坏。');
    }
    return okResult<string | null>('Preferences 值已读取。', result.data);
  }

  /**
   * Refuses the operation while cache invalidation is unconfirmed. A recovery
   * attempt is made first; it clears the flag only on a confirmed discard plus
   * fresh durable reads.
   */
  private async ensureCacheCoherent(): Promise<OperationResult<boolean> | null> {
    if (!this.cacheUncertain) {
      return null;
    }
    const recovered: OperationResult<boolean> = await this.recoverDurableState();
    if (!isTrueResult(recovered)) {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        'Preferences 缓存状态未确认，已阻止本次读写；' + recovered.message);
    }
    return null;
  }

  async readPrimary(): Promise<OperationResult<string | null>> {
    await this.waitForWrites();
    const blocked: OperationResult<boolean> | null = await this.ensureCacheCoherent();
    if (blocked !== null) {
      return errorResult<string | null>(blocked.code, blocked.message);
    }
    return this.readIo(PRIMARY_KEY);
  }

  async readBackup(): Promise<OperationResult<string | null>> {
    await this.waitForWrites();
    const blocked: OperationResult<boolean> | null = await this.ensureCacheCoherent();
    if (blocked !== null) {
      return errorResult<string | null>(blocked.code, blocked.message);
    }
    return this.readIo(BACKUP_KEY);
  }

  // ------------------------------------------------------------------
  // Writes
  // ------------------------------------------------------------------

  /**
   * One serial queue for plan writes, archive preservation and durable rebuild
   * verification. All three can touch the same platform cache, so they must
   * never overlap.
   */
  private enqueueSerial<T>(
    task: () => Promise<OperationResult<T>>,
    onUnexpected: () => Promise<OperationResult<T>>
  ): Promise<OperationResult<T>> {
    const previous: Promise<void> = this.writeTail;
    const run: Promise<OperationResult<T>> = previous.then(
      (): Promise<OperationResult<T>> => {
        return task().catch((error: Object): Promise<OperationResult<T>> => {
          return onUnexpected();
        });
      }
    );
    this.writeTail = run.then(
      (): void => {},
      (): void => {}
    );
    return run;
  }

  private enqueueWrite(
    task: () => Promise<OperationResult<boolean>>
  ): Promise<OperationResult<boolean>> {
    return this.enqueueSerial<boolean>(task, (): Promise<OperationResult<boolean>> => {
      return this.failWrite('Preferences 写入发生未预期错误。');
    });
  }

  private validateSnapshot(text: string, label: string): OperationResult<string> | null {
    if (typeof text !== 'string' || text.length === 0) {
      return errorResult<string>('INVALID_ARGUMENT', label + '快照文本不能为空。');
    }
    if (text.length > MAX_SNAPSHOT_TEXT_LENGTH) {
      return errorResult<string>('PERSISTENCE_ERROR',
        label + '快照长度 ' + text.length.toString() + ' 超过 Preferences 单值上限 ' +
        MAX_SNAPSHOT_TEXT_LENGTH.toString() + '，未写入。');
    }
    const parsed: OperationResult<PlanStore> = parseStore(text);
    if (parsed.code !== 'OK') {
      return errorResult<string>(parsed.code, label + '快照校验失败：' + parsed.message);
    }
    return null;
  }

  private async putSafe(key: string, value: string): Promise<OperationResult<boolean>> {
    try {
      return await this.io.put(key, value);
    } catch (error) {
      return errorResult<boolean>('PERSISTENCE_ERROR', '写入 Preferences 值失败（IO 异常）。');
    }
  }

  private async flushSafe(): Promise<OperationResult<boolean>> {
    try {
      return await this.io.flush();
    } catch (error) {
      return errorResult<boolean>('PERSISTENCE_ERROR', 'Preferences flush 失败（IO 异常）。');
    }
  }

  /** Preserves the IO failure code while normalizing thrown rejections. */
  private async discardSafe(): Promise<OperationResult<boolean>> {
    try {
      return await this.io.discardCache();
    } catch (error) {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '丢弃 Preferences 内存缓存失败（IO 异常）。');
    }
  }

  /**
   * Marks the cache uncertain before attempting removal. The flag is cleared
   * only when the platform confirms cache removal and both durable reads
   * succeed. A read from a possibly cached instance is never sufficient.
   */
  private async recoverDurableState(): Promise<OperationResult<boolean>> {
    this.cacheUncertain = true;
    const discarded: OperationResult<boolean> = await this.discardSafe();
    if (!isTrueResult(discarded)) {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        'Preferences 缓存失效未确认，继续阻止读写：' +
        failureMessage(discarded, '丢弃缓存未确认成功。'));
    }
    const primaryRead: OperationResult<string | null> = await this.readIo(PRIMARY_KEY);
    if (primaryRead.code !== 'OK') {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '缓存失效后主快照读取失败，继续阻止读写：' + primaryRead.message);
    }
    const backupRead: OperationResult<string | null> = await this.readIo(BACKUP_KEY);
    if (backupRead.code !== 'OK') {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '缓存失效后备份快照读取失败，继续阻止读写：' + backupRead.message);
    }
    this.cacheUncertain = false;
    return okResult<boolean>('Preferences 缓存状态已重新确认。', true);
  }

  private async failWrite(message: string): Promise<OperationResult<boolean>> {
    await this.recoverDurableState();
    return errorResult<boolean>('PERSISTENCE_ERROR', message);
  }

  private async runWrite(primary: string, backup: string | null): Promise<OperationResult<boolean>> {
    const blocked: OperationResult<boolean> | null = await this.ensureCacheCoherent();
    if (blocked !== null) {
      return errorResult<boolean>(blocked.code, blocked.message);
    }
    const primaryProblem: OperationResult<string> | null =
      this.validateSnapshot(primary, '主');
    if (primaryProblem !== null) {
      return errorResult<boolean>(primaryProblem.code, primaryProblem.message);
    }
    if (backup !== null) {
      const backupProblem: OperationResult<string> | null =
        this.validateSnapshot(backup, '备份');
      if (backupProblem !== null) {
        return errorResult<boolean>(backupProblem.code, backupProblem.message);
      }
    }

    if (backup !== null) {
      const backupPut: OperationResult<boolean> = await this.putSafe(BACKUP_KEY, backup);
      if (!isTrueResult(backupPut)) {
        return this.failWrite(failureMessage(backupPut, '备份快照写入未确认成功。'));
      }
      const backupFlush: OperationResult<boolean> = await this.flushSafe();
      if (!isTrueResult(backupFlush)) {
        return this.failWrite(failureMessage(backupFlush, '备份快照 flush 未确认成功。'));
      }
    }

    const primaryPut: OperationResult<boolean> = await this.putSafe(PRIMARY_KEY, primary);
    if (!isTrueResult(primaryPut)) {
      return this.failWrite(failureMessage(primaryPut, '主快照写入未确认成功。'));
    }
    const primaryFlush: OperationResult<boolean> = await this.flushSafe();
    if (!isTrueResult(primaryFlush)) {
      return this.failWrite(failureMessage(primaryFlush, '主快照 flush 未确认成功。'));
    }
    return okResult<boolean>('主快照已 flush 到 Preferences。', true);
  }

  write(primary: string, backup: string | null): Promise<OperationResult<boolean>> {
    const primarySnapshot: string = typeof primary === 'string' ? primary : '';
    let backupSnapshot: string | null = null;
    if (backup !== null && typeof backup === 'string') {
      backupSnapshot = backup;
    }
    return this.enqueueWrite((): Promise<OperationResult<boolean>> => {
      return this.runWrite(primarySnapshot, backupSnapshot);
    });
  }

  // ------------------------------------------------------------------
  // RecoveryArchivePort: immutable raw-text archives
  // ------------------------------------------------------------------

  /**
   * Allocates an id whose two archive keys are both absent. A colliding id is
   * skipped, so a preserved archive can never be overwritten.
   */
  private async allocateArchiveId(): Promise<OperationResult<string>> {
    const now: number = Date.now();
    const base: number = Number.isFinite(now) && now >= 0 ? now : 0;
    for (let attempt = 0; attempt < 1000; attempt++) {
      this.archiveCounter = this.archiveCounter + 1;
      const candidate: string = 'archive-' + base.toString(36) + '-' +
        this.archiveCounter.toString(36);
      const primaryRead: OperationResult<string | null> =
        await this.readIo(archivePrimaryKey(candidate));
      if (primaryRead.code !== 'OK') {
        return errorResult<string>('PERSISTENCE_ERROR',
          '检查归档标识失败，未写入归档：' + primaryRead.message);
      }
      if (primaryRead.data !== null) {
        continue;
      }
      const backupRead: OperationResult<string | null> =
        await this.readIo(archiveBackupKey(candidate));
      if (backupRead.code !== 'OK') {
        return errorResult<string>('PERSISTENCE_ERROR',
          '检查归档标识失败，未写入归档：' + backupRead.message);
      }
      if (backupRead.data !== null) {
        continue;
      }
      return okResult<string>('归档标识已分配。', candidate);
    }
    return errorResult<string>('PERSISTENCE_ERROR',
      '无法分配不会覆盖旧归档的标识，未写入归档。');
  }

  private async failArchive(message: string): Promise<OperationResult<ArchivedSnapshot>> {
    await this.recoverDurableState();
    return errorResult<ArchivedSnapshot>('PERSISTENCE_ERROR', message);
  }

  private async runPreserve(primary: string, backup: string):
    Promise<OperationResult<ArchivedSnapshot>> {
    const blocked: OperationResult<boolean> | null = await this.ensureCacheCoherent();
    if (blocked !== null) {
      return errorResult<ArchivedSnapshot>(blocked.code, blocked.message);
    }
    if (typeof primary !== 'string' || typeof backup !== 'string') {
      return errorResult<ArchivedSnapshot>('INVALID_ARGUMENT',
        '待保全的主备快照必须是字符串。');
    }
    if (primary.length > MAX_SNAPSHOT_TEXT_LENGTH ||
      backup.length > MAX_SNAPSHOT_TEXT_LENGTH) {
      return errorResult<ArchivedSnapshot>('PERSISTENCE_ERROR',
        '损坏快照长度超过 Preferences 单值上限 ' +
        MAX_SNAPSHOT_TEXT_LENGTH.toString() + '，拒绝归档与重建。');
    }

    const idResult: OperationResult<string> = await this.allocateArchiveId();
    if (idResult.code !== 'OK' || idResult.data === undefined) {
      return errorResult<ArchivedSnapshot>(idResult.code, idResult.message);
    }
    const archiveId: string = idResult.data;
    const primaryKey: string = archivePrimaryKey(archiveId);
    const backupKey: string = archiveBackupKey(archiveId);

    const primaryPut: OperationResult<boolean> = await this.putSafe(primaryKey, primary);
    if (!isTrueResult(primaryPut)) {
      return this.failArchive(failureMessage(primaryPut, '归档主快照写入未确认成功。'));
    }
    const backupPut: OperationResult<boolean> = await this.putSafe(backupKey, backup);
    if (!isTrueResult(backupPut)) {
      return this.failArchive(failureMessage(backupPut, '归档备份快照写入未确认成功。'));
    }
    const flushed: OperationResult<boolean> = await this.flushSafe();
    if (!isTrueResult(flushed)) {
      return this.failArchive(failureMessage(flushed, '归档 flush 未确认成功。'));
    }

    // Read-back must bypass the platform cache; otherwise an unconfirmed cached
    // value could masquerade as durable.
    const discarded: OperationResult<boolean> = await this.discardSafe();
    if (!isTrueResult(discarded)) {
      return this.failArchive(failureMessage(discarded, '归档读回前丢弃缓存失败。'));
    }
    const primaryRead: OperationResult<string | null> = await this.readIo(primaryKey);
    if (primaryRead.code !== 'OK') {
      return errorResult<ArchivedSnapshot>('PERSISTENCE_ERROR',
        '归档主快照读回失败，拒绝重建：' + primaryRead.message);
    }
    const backupRead: OperationResult<string | null> = await this.readIo(backupKey);
    if (backupRead.code !== 'OK') {
      return errorResult<ArchivedSnapshot>('PERSISTENCE_ERROR',
        '归档备份快照读回失败，拒绝重建：' + backupRead.message);
    }
    if (primaryRead.data !== primary || backupRead.data !== backup) {
      return errorResult<ArchivedSnapshot>('PERSISTENCE_ERROR',
        '归档读回内容与原始主备快照不一致，拒绝重建。');
    }
    const archived: ArchivedSnapshot = {
      archiveId: archiveId,
      primary: primary,
      backup: backup
    };
    return okResult<ArchivedSnapshot>('损坏快照已原样保全并读回校验。', archived);
  }

  preserveCorruptedSnapshot(primary: string, backup: string):
    Promise<OperationResult<ArchivedSnapshot>> {
    const primarySnapshot: string = primary;
    const backupSnapshot: string = backup;
    return this.enqueueSerial<ArchivedSnapshot>(
      (): Promise<OperationResult<ArchivedSnapshot>> => {
        return this.runPreserve(primarySnapshot, backupSnapshot);
      },
      (): Promise<OperationResult<ArchivedSnapshot>> => {
        return this.failArchive('归档写入发生未预期错误。');
      }
    );
  }

  async readArchivedSnapshot(archiveId: string): Promise<OperationResult<ArchivedSnapshot>> {
    await this.waitForWrites();
    const blocked: OperationResult<boolean> | null = await this.ensureCacheCoherent();
    if (blocked !== null) {
      return errorResult<ArchivedSnapshot>(blocked.code, blocked.message);
    }
    if (typeof archiveId !== 'string' || archiveId.length === 0) {
      return errorResult<ArchivedSnapshot>('INVALID_ARGUMENT', '归档标识不能为空。');
    }
    const primaryRead: OperationResult<string | null> =
      await this.readIo(archivePrimaryKey(archiveId));
    if (primaryRead.code !== 'OK') {
      return errorResult<ArchivedSnapshot>(primaryRead.code, primaryRead.message);
    }
    const backupRead: OperationResult<string | null> =
      await this.readIo(archiveBackupKey(archiveId));
    if (backupRead.code !== 'OK') {
      return errorResult<ArchivedSnapshot>(backupRead.code, backupRead.message);
    }
    const primaryText: string | null | undefined = primaryRead.data;
    const backupText: string | null | undefined = backupRead.data;
    if (primaryText === null || primaryText === undefined ||
      backupText === null || backupText === undefined) {
      return errorResult<ArchivedSnapshot>('NOT_FOUND', '归档不存在或不完整。');
    }
    const archived: ArchivedSnapshot = {
      archiveId: archiveId,
      primary: primaryText,
      backup: backupText
    };
    return okResult<ArchivedSnapshot>('归档快照已读取。', archived);
  }

  /**
   * Confirms the rebuilt empty store is durable by discarding the cache first.
   * Any error leaves the rebuild unpublished; the caller must not claim ready.
   */
  private async runVerify(expectedPrimary: string, expectedBackup: string | null):
    Promise<OperationResult<boolean>> {
    const blocked: OperationResult<boolean> | null = await this.ensureCacheCoherent();
    if (blocked !== null) {
      return errorResult<boolean>(blocked.code, blocked.message);
    }
    if (typeof expectedPrimary !== 'string' || expectedPrimary.length === 0) {
      return errorResult<boolean>('INVALID_ARGUMENT', '待校验主快照不能为空。');
    }
    if (expectedBackup !== null && typeof expectedBackup !== 'string') {
      return errorResult<boolean>('INVALID_ARGUMENT', '待校验备份快照必须是字符串或 null。');
    }

    const discarded: OperationResult<boolean> = await this.discardSafe();
    if (!isTrueResult(discarded)) {
      return this.failWrite('重建落盘校验前丢弃缓存失败：' +
        failureMessage(discarded, '丢弃缓存未确认成功。'));
    }
    const primaryRead: OperationResult<string | null> = await this.readIo(PRIMARY_KEY);
    if (primaryRead.code !== 'OK') {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '重建主快照落盘读取失败：' + primaryRead.message);
    }
    const backupRead: OperationResult<string | null> = await this.readIo(BACKUP_KEY);
    if (backupRead.code !== 'OK') {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '重建备份快照落盘读取失败：' + backupRead.message);
    }
    if (primaryRead.data !== expectedPrimary) {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '重建主快照落盘内容与预期空库不一致，拒绝发布。');
    }
    if (expectedBackup === null) {
      if (backupRead.data !== null) {
        return errorResult<boolean>('PERSISTENCE_ERROR',
          '重建备份快照落盘内容与预期不一致，拒绝发布。');
      }
    } else if (backupRead.data !== expectedBackup) {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '重建备份快照落盘内容与预期空库不一致，拒绝发布。');
    }
    return okResult<boolean>('重建空库已确认落盘。', true);
  }

  verifyRebuiltStore(expectedPrimary: string, expectedBackup: string | null):
    Promise<OperationResult<boolean>> {
    const primarySnapshot: string = expectedPrimary;
    const backupSnapshot: string | null = expectedBackup;
    return this.enqueueSerial<boolean>(
      (): Promise<OperationResult<boolean>> => {
        return this.runVerify(primarySnapshot, backupSnapshot);
      },
      (): Promise<OperationResult<boolean>> => {
        return this.failWrite('重建落盘校验发生未预期错误。');
      }
    );
  }
}

/**
 * Production PreferencesIO. Owns the context, the file name and the current
 * Preferences instance. `discardCache` drops the owned reference before asking
 * the platform to remove the file from its cache. A failed removal sets a
 * separate retry obligation, so a later discard still attempts removal instead
 * of reporting success merely because the reference is already null. After a
 * confirmed removal the next operation re-opens the file with
 * `getPreferences(context, { name })` and reads durable data.
 */
export class ActualPlatformPreferencesIO implements PreferencesIO {
  private context: common.Context;
  private prefs: preferences.Preferences | null = null;
  /**
   * True after a failed `removePreferencesFromCache`. It stays independent of
   * `prefs` because the owned reference is dropped before removal is attempted:
   * a later discard must still retry the platform removal, and it must never
   * touch the old instance.
   */
  private needsDiscard: boolean = false;

  constructor(context: common.Context) {
    this.context = context;
  }

  /** Opens the XML file once so construction failures are reported by create. */
  async initialize(): Promise<OperationResult<boolean>> {
    const opened: OperationResult<preferences.Preferences> = await this.ensurePreferences();
    if (opened.code !== 'OK') {
      return errorResult<boolean>(opened.code, opened.message);
    }
    return okResult<boolean>('Preferences 文件已打开。', true);
  }

  private async ensurePreferences(): Promise<OperationResult<preferences.Preferences>> {
    if (this.prefs !== null) {
      return okResult<preferences.Preferences>('Preferences 文件已打开。', this.prefs);
    }
    try {
      // SDK 17 Options overload: name only; no newer options are used.
      const opened: preferences.Preferences =
        await preferences.getPreferences(this.context, { name: PREFERENCES_NAME });
      this.prefs = opened;
      return okResult<preferences.Preferences>('Preferences 文件已打开。', opened);
    } catch (error) {
      this.prefs = null;
      return errorResult<preferences.Preferences>('PERSISTENCE_ERROR',
        '打开 Preferences 文件 ' + PREFERENCES_NAME + ' 失败。');
    }
  }

  async read(key: string): Promise<OperationResult<string | null>> {
    const opened: OperationResult<preferences.Preferences> = await this.ensurePreferences();
    if (opened.code !== 'OK' || opened.data === undefined) {
      return errorResult<string | null>(opened.code, opened.message);
    }
    const prefs: preferences.Preferences = opened.data;
    try {
      const exists: boolean = await prefs.has(key);
      if (!exists) {
        return okResult<string | null>('Preferences 中不存在该键。', null);
      }
      const value: preferences.ValueType = await prefs.get(key, '');
      if (typeof value !== 'string') {
        return errorResult<string | null>('CORRUPTED_DATA',
          'Preferences 键 ' + key + ' 的值不是字符串，数据已损坏。');
      }
      return okResult<string | null>('Preferences 值已读取。', value);
    } catch (error) {
      return errorResult<string | null>('PERSISTENCE_ERROR',
        '读取 Preferences 键 ' + key + ' 失败。');
    }
  }

  async put(key: string, value: string): Promise<OperationResult<boolean>> {
    const opened: OperationResult<preferences.Preferences> = await this.ensurePreferences();
    if (opened.code !== 'OK' || opened.data === undefined) {
      return errorResult<boolean>(opened.code, opened.message);
    }
    try {
      await opened.data.put(key, value);
      return okResult<boolean>('Preferences 值已写入缓存。', true);
    } catch (error) {
      return errorResult<boolean>('PERSISTENCE_ERROR',
        '写入 Preferences 键 ' + key + ' 失败。');
    }
  }

  async flush(): Promise<OperationResult<boolean>> {
    const opened: OperationResult<preferences.Preferences> = await this.ensurePreferences();
    if (opened.code !== 'OK' || opened.data === undefined) {
      return errorResult<boolean>(opened.code, opened.message);
    }
    try {
      await opened.data.flush();
      return okResult<boolean>('Preferences 缓存已 flush。', true);
    } catch (error) {
      return errorResult<boolean>('PERSISTENCE_ERROR', 'Preferences flush 失败。');
    }
  }

  async discardCache(): Promise<OperationResult<boolean>> {
    const hadInstance: boolean = this.prefs !== null;
    // Drop the owned reference before removal so a failed/partially applied
    // removal can never be followed by a write through the stale instance.
    this.prefs = null;
    if (!hadInstance && !this.needsDiscard) {
      return okResult<boolean>('Preferences 缓存未打开，无需丢弃。', true);
    }
    try {
      await preferences.removePreferencesFromCache(this.context, { name: PREFERENCES_NAME });
      this.needsDiscard = false;
      return okResult<boolean>('Preferences 内存缓存已丢弃。', true);
    } catch (error) {
      // Keep the removal obligation even though `prefs` is already null, so a
      // later discard retries the platform removal instead of returning OK.
      this.needsDiscard = true;
      return errorResult<boolean>('PERSISTENCE_ERROR', '丢弃 Preferences 内存缓存失败。');
    }
  }
}
