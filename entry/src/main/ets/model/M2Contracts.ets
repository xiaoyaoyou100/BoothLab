import { BoothPlan, OperationResult, PlanStore } from './BoothModels';

export type SaveState = 'Dirty' | 'Saving' | 'Saved' | 'SaveError';

// Storage only accepts complete serialized committed snapshots; no UI/history data.
export interface SnapshotStorage {
  readPrimary(): Promise<OperationResult<string | null>>;
  readBackup(): Promise<OperationResult<string | null>>;
  write(primary: string, backup: string | null): Promise<OperationResult<boolean>>;
}

export interface PlanRepositoryPort {
  createPlan(name: string, templateId: string): Promise<OperationResult<BoothPlan>>;
  listPlans(): BoothPlan[];
  loadPlan(planId: string): OperationResult<BoothPlan>;
  openPlan(planId: string): Promise<OperationResult<BoothPlan>>;
  deletePlan(planId: string, confirmed: boolean): Promise<OperationResult<boolean>>;
  savePlan(plan: BoothPlan): Promise<OperationResult<BoothPlan>>;
  recoverStore(): Promise<OperationResult<PlanStore>>;
  getStore(): PlanStore;
  getSaveState(): SaveState;
  markDirty(): void;
}
