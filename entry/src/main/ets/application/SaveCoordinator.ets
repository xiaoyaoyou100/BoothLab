/**
 * BoothLab M2-I01 UI-save coordinator.
 *
 * Owns the editor's committed draft for one open plan and makes the save state
 * truthful while asynchronous writes overlap with local edits:
 *
 * - bind(plan) starts a new editing session from an already durable snapshot
 *   (create/open persisted it) and invalidates any older completion.
 * - update(plan) accepts only a snapshot of the same plan identity, stores an
 *   independent clone and marks the repository dirty.
 * - save() captures an immutable snapshot plus the current revision and session
 *   token at request time. A completion can report Saved only when no newer
 *   edit and no re-bind happened in the meantime; otherwise the state stays
 *   Dirty (or the stale completion is ignored entirely for a new session).
 *
 * This class performs no UI work, never touches history/preview/selection and
 * never persists extra fields: only the formal BoothPlan is handed to the
 * repository. The repository itself already serializes writes, so overlapping
 * save() calls remain safe.
 */

import { BoothPlan, OperationResult } from '../model/BoothModels';
import { PlanRepositoryPort, SaveState } from '../model/M2Contracts';
import {
  clonePlan,
  errorResult,
  okResult,
  validatePlan
} from '../repository/PlanValidator';

export class SaveCoordinator {
  private repository: PlanRepositoryPort;
  /** Latest committed editor snapshot; null until bind succeeds. */
  private draft: BoothPlan | null = null;
  private state: SaveState = 'Saved';
  /** Incremented by every effective update; reset by bind. */
  private revision: number = 0;
  /** Incremented by bind so older completions can never pollute a new plan. */
  private sessionToken: number = 0;
  /** Save requests in flight for the current session. */
  private inFlight: number = 0;

  constructor(repository: PlanRepositoryPort) {
    this.repository = repository;
  }

  /**
   * Starts a new editing session. The supplied plan is already durable through
   * createPlan/openPlan, so the truthful initial state is Saved. Any pending
   * save from the previous session is ignored when it completes.
   */
  bind(plan: BoothPlan): void {
    this.sessionToken = this.sessionToken + 1;
    this.revision = 0;
    this.inFlight = 0;
    const validated: OperationResult<BoothPlan> = validatePlan(plan);
    if (validated.code !== 'OK' || validated.data === undefined) {
      this.draft = null;
      this.state = 'SaveError';
      return;
    }
    this.draft = clonePlan(validated.data);
    this.state = 'Saved';
  }

  /**
   * Records one effective committed edit. The immutable identity fields of the
   * open plan may not change; the returned clone contains only persisted plan
   * fields, so preview/history/selection state can never enter the draft.
   */
  update(plan: BoothPlan): OperationResult<boolean> {
    const current: BoothPlan | null = this.draft;
    if (current === null) {
      return errorResult<boolean>('INVALID_ARGUMENT', '尚未绑定展位方案，无法记录编辑。');
    }
    if (plan === null || plan === undefined || typeof plan !== 'object' ||
      Array.isArray(plan)) {
      return errorResult<boolean>('INVALID_ARGUMENT', '展位方案必须是对象。');
    }
    if (plan.id !== current.id) {
      return errorResult<boolean>('INVALID_ARGUMENT', '编辑快照不属于当前展位方案。');
    }
    if (plan.templateId !== current.templateId) {
      return errorResult<boolean>('INVALID_ARGUMENT', '编辑不能修改展位方案的模板。');
    }
    if (plan.createdAt !== current.createdAt) {
      return errorResult<boolean>('INVALID_ARGUMENT', '编辑不能修改展位方案的创建时间。');
    }

    const validated: OperationResult<BoothPlan> = validatePlan(plan);
    if (validated.code !== 'OK' || validated.data === undefined) {
      return errorResult<boolean>(validated.code, validated.message);
    }
    this.draft = clonePlan(validated.data);
    this.revision = this.revision + 1;
    this.repository.markDirty();
    this.state = 'Dirty';
    return okResult<boolean>('编辑已记录，等待保存。', true);
  }

  /** Independent copy of the latest committed draft, or null before bind. */
  getDraft(): BoothPlan | null {
    const current: BoothPlan | null = this.draft;
    if (current === null) {
      return null;
    }
    return clonePlan(current);
  }

  getState(): SaveState {
    return this.state;
  }

  /** True while at least one save request for the current session is pending. */
  isSaving(): boolean {
    return this.inFlight > 0;
  }

  /**
   * Persists the current draft. The snapshot, revision and session token are
   * captured synchronously before the first await, so edits made while the
   * write is in flight can never be reported as saved by this completion.
   * Multiple overlapping calls are safe: the repository serializes writes.
   */
  save(): Promise<OperationResult<BoothPlan>> {
    const requestToken: number = this.sessionToken;
    const requestRevision: number = this.revision;
    const current: BoothPlan | null = this.draft;
    if (current === null) {
      return Promise.resolve(
        errorResult<BoothPlan>('INVALID_ARGUMENT', '尚未绑定展位方案，无法保存。')
      );
    }
    const snapshot: BoothPlan = clonePlan(current);
    this.inFlight = this.inFlight + 1;
    this.state = 'Saving';

    let request: Promise<OperationResult<BoothPlan>>;
    try {
      request = this.repository.savePlan(snapshot);
    } catch (error) {
      // A repository that throws synchronously must not leave a stuck Saving.
      this.decrementInFlight();
      this.state = 'SaveError';
      return Promise.resolve(
        errorResult<BoothPlan>('PERSISTENCE_ERROR', '保存展位方案时发生未预期错误。')
      );
    }

    return request.then(
      (result: OperationResult<BoothPlan>): OperationResult<BoothPlan> => {
        if (requestToken === this.sessionToken) {
          this.decrementInFlight();
          if (result.code !== 'OK' || result.data === undefined) {
            this.state = 'SaveError';
          } else if (requestRevision === this.revision) {
            this.state = 'Saved';
          } else {
            // A newer local edit was recorded while this write awaited.
            this.state = 'Dirty';
          }
        }
        return result;
      },
      (error: Object): OperationResult<BoothPlan> => {
        if (requestToken === this.sessionToken) {
          this.decrementInFlight();
          this.state = 'SaveError';
        }
        return errorResult<BoothPlan>('PERSISTENCE_ERROR', '保存展位方案时发生未预期错误。');
      }
    );
  }

  private decrementInFlight(): void {
    if (this.inFlight > 0) {
      this.inFlight = this.inFlight - 1;
    }
  }
}
