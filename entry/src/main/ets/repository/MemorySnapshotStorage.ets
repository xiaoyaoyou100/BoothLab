/**
 * In-memory SnapshotStorage for BoothLab M2-B01.
 *
 * This adapter exists so the repository can be complete and testable before the
 * Preferences-backed adapter is integrated. It is explicitly NOT durable:
 * primary/backup text lives only in this process and is lost when the process
 * ends. B02 will provide the durable Preferences implementation without
 * changing the SnapshotStorage interface.
 */

import { OperationResult } from '../model/BoothModels';
import { SnapshotStorage } from '../model/M2Contracts';
import { okResult } from './PlanValidator';

/** False by contract: this adapter never persists across process restarts. */
export const MEMORY_SNAPSHOT_STORAGE_DURABLE: boolean = false;
export const MEMORY_SNAPSHOT_STORAGE_NOTICE: string =
  '内存快照存储不持久：应用退出后方案数据会丢失。B02 将接入 Preferences 持久化。';

export class MemorySnapshotStorage implements SnapshotStorage {
  readonly durable: boolean = MEMORY_SNAPSHOT_STORAGE_DURABLE;
  private primary: string | null = null;
  private backup: string | null = null;

  /** Returns the explicit non-durability notice for UI/status usage. */
  durabilityNotice(): string {
    return MEMORY_SNAPSHOT_STORAGE_NOTICE;
  }

  readPrimary(): Promise<OperationResult<string | null>> {
    return Promise.resolve(okResult<string | null>('内存主快照已读取。', this.primary));
  }

  readBackup(): Promise<OperationResult<string | null>> {
    return Promise.resolve(okResult<string | null>('内存备份快照已读取。', this.backup));
  }

  write(primary: string, backup: string | null): Promise<OperationResult<boolean>> {
    if (typeof primary !== 'string' || primary.length === 0) {
      const invalid: OperationResult<boolean> = {
        code: 'INVALID_ARGUMENT',
        message: '主快照文本不能为空。'
      };
      return Promise.resolve(invalid);
    }
    this.primary = primary;
    this.backup = backup;
    return Promise.resolve(okResult<boolean>('内存快照已写入（不持久）。', true));
  }
}
