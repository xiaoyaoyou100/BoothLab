/**
 * BoothLab M2-B dedicated recovery/rebuild contracts.
 *
 * This module is B-owned and additive. It deliberately does not change the
 * shared model/M2Contracts.ets: SnapshotStorage and PlanRepositoryPort keep
 * their existing shape, and PlanRepository keeps its existing constructor.
 * A concrete PlanRepository can be given the same PreferencesStore instance as
 * both SnapshotStorage and RecoveryArchivePort through the optional second
 * constructor argument.
 *
 * Failure model:
 * - Recovery never rewrites storage. The only destructive path is the explicit
 *   confirm=true rebuild, and only when both stored snapshots are present,
 *   unusable and free of future-schema/IO uncertainty.
 * - Archive values are raw strings under a unique archive id; writing them must
 *   never overwrite an older archive.
 */

import { OperationResult, PlanStore } from '../model/BoothModels';

/** Classification of one stored slot (primary or backup). */
export type RecoverySlotState =
  | 'UNKNOWN'
  | 'MISSING'
  | 'VALID'
  | 'CORRUPTED'
  | 'UNSUPPORTED_SCHEMA'
  | 'IO_ERROR';

/** Why a rebuild is offered, not offered, or no longer safe. */
export type RebuildReason =
  | 'NOT_CHECKED'
  | 'NO_REBUILD_NEEDED'
  | 'BOTH_CORRUPT'
  | 'FUTURE_SCHEMA'
  | 'IO_ERROR'
  | 'INCOMPLETE_DAMAGE'
  | 'ARCHIVE_UNAVAILABLE'
  | 'ALREADY_REBUILT'
  | 'STATE_UNKNOWN';

/** User-facing phase derived from the most recent reviewed recovery result. */
export type RebuildPhase =
  | 'NOT_CHECKED'
  | 'NOT_NEEDED'
  | 'READY'
  | 'IN_PROGRESS'
  | 'BLOCKED'
  | 'REBUILT';

/** Outcome of one rebuildStore(confirmed) call. */
export type RebuildStatus =
  | 'REBUILT'
  | 'CANCELLED'
  | 'NOT_REBUILDABLE'
  | 'STALE_SNAPSHOT'
  | 'ARCHIVE_FAILED'
  | 'EMPTY_WRITE_FAILED'
  | 'VERIFY_FAILED'
  | 'ALREADY_REBUILT'
  | 'UNEXPECTED_ERROR';

export interface RebuildState {
  phase: RebuildPhase;
  /** True only when an explicit confirmed rebuild is currently safe to offer. */
  rebuildable: boolean;
  reason: RebuildReason;
  message: string;
  primary: RecoverySlotState;
  backup: RecoverySlotState;
  archiveAvailable: boolean;
  /** Archive id of the most recent successful rebuild in this repository. */
  lastArchiveId: string | null;
}

export interface RebuildResult {
  status: RebuildStatus;
  message: string;
  /** Set once an archive was preserved, including later empty-write failures. */
  archiveId: string | null;
  /** Present only for a successful rebuild. */
  store: PlanStore | null;
}

/** Exact raw texts preserved under one immutable archive id. */
export interface ArchivedSnapshot {
  archiveId: string;
  primary: string;
  backup: string;
}

/**
 * Optional recovery capability that can preserve raw damaged texts and prove
 * that the rebuilt empty store reached durable storage. Implemented by
 * PreferencesStore; injected into PlanRepository as an optional second
 * constructor argument. Without it, rebuild is never offered.
 */
export interface RecoveryArchivePort {
  /**
   * Writes the exact primary/backup strings under a fresh archive id, flushes,
   * discards the cache and reads both values back. It must never overwrite an
   * existing archive id.
   */
  preserveCorruptedSnapshot(primary: string, backup: string):
    Promise<OperationResult<ArchivedSnapshot>>;
  /** Reads one archive for diagnostics/tests; never mutates storage. */
  readArchivedSnapshot(archiveId: string): Promise<OperationResult<ArchivedSnapshot>>;
  /**
   * Drops the Preferences cache and reads primary/backup from durable storage,
   * requiring exact equality with the expected rebuilt texts.
   */
  verifyRebuiltStore(expectedPrimary: string, expectedBackup: string | null):
    Promise<OperationResult<boolean>>;
}
