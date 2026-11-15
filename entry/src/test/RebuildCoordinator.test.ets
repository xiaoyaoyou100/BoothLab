/**
 * M2-BOTH-CORRUPTED-RECOVERY A-side UI state tests.
 *
 * These tests exercise the production RebuildCoordinator directly. The fake
 * gateway stands in for the already-reviewed B PlanRepository API; it records
 * every rebuildStore call so the tests can prove that preparing, requesting a
 * confirmation, cancelling, blocked states and duplicate confirms never write.
 * No storage, repository or Index view logic is duplicated here.
 */

import { describe, it, expect } from '@ohos/hypium';
import { PlanStore } from '../main/ets/model/BoothModels';
import {
  RebuildPhase,
  RebuildReason,
  RebuildResult,
  RebuildState,
  RebuildStatus
} from '../main/ets/repository/RecoveryContracts';
import {
  RebuildCoordinator,
  RebuildUiSnapshot
} from '../main/ets/application/RebuildCoordinator';

function emptyStore(): PlanStore {
  const store: PlanStore = {
    schemaVersion: 1,
    plans: [],
    activePlanId: null
  };
  return store;
}

function makeState(phase: RebuildPhase, rebuildable: boolean, reason: RebuildReason,
  message: string, archiveAvailable: boolean = true): RebuildState {
  const state: RebuildState = {
    phase: phase,
    rebuildable: rebuildable,
    reason: reason,
    message: message,
    primary: 'CORRUPTED',
    backup: 'CORRUPTED',
    archiveAvailable: archiveAvailable,
    lastArchiveId: null
  };
  return state;
}

function rebuiltResult(archiveId: string): RebuildResult {
  const result: RebuildResult = {
    status: 'REBUILT',
    message: '方案库已重建为空库，原始损坏快照已归档。',
    archiveId: archiveId,
    store: emptyStore()
  };
  return result;
}

function failedResult(status: RebuildStatus, message: string,
  archiveId: string | null): RebuildResult {
  const result: RebuildResult = {
    status: status,
    message: message,
    archiveId: archiveId,
    store: null
  };
  return result;
}

/**
 * Records B-facing calls. The state returned by readState() can be swapped to
 * model a fresh review after a failure. Deferred mode holds rebuildStore open
 * so the tests can inspect the busy UI phase before completion.
 */
class FakeRebuildGateway {
  state: RebuildState;
  nextResult: RebuildResult;
  defer: boolean = false;
  rebuildCalls: number = 0;
  stateReads: number = 0;
  confirmedValues: boolean[] = [];
  private pendingResolve: ((result: RebuildResult) => void) | null = null;

  constructor(state: RebuildState, nextResult: RebuildResult) {
    this.state = state;
    this.nextResult = nextResult;
  }

  readState(): RebuildState {
    this.stateReads = this.stateReads + 1;
    return this.state;
  }

  rebuild(confirmed: boolean): Promise<RebuildResult> {
    this.rebuildCalls = this.rebuildCalls + 1;
    this.confirmedValues.push(confirmed);
    if (this.defer) {
      return new Promise<RebuildResult>(
        (resolve: (result: RebuildResult) => void): void => {
          this.pendingResolve = resolve;
        }
      );
    }
    return Promise.resolve(this.nextResult);
  }

  resolvePending(result: RebuildResult): void {
    const resolve: ((result: RebuildResult) => void) | null = this.pendingResolve;
    this.pendingResolve = null;
    this.defer = false;
    if (resolve !== null) {
      resolve(result);
    }
  }
}

function makeCoordinator(gateway: FakeRebuildGateway): RebuildCoordinator {
  return new RebuildCoordinator(
    (): RebuildState => gateway.readState(),
    (confirmed: boolean): Promise<RebuildResult> => gateway.rebuild(confirmed)
  );
}

function readyState(): RebuildState {
  return makeState('READY', true, 'BOTH_CORRUPT',
    '主快照与备份均已损坏，未覆盖任何数据。');
}

export default function rebuildCoordinatorTest() {
  describe('RebuildCoordinatorTest', () => {
    it('prepareOffersRebuildFromReadyStateWithoutCallingRebuild', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(readyState(), rebuiltResult('archive-1'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);

        const snapshot: RebuildUiSnapshot =
          coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        expect(snapshot.phase).assertEqual('AVAILABLE');
        expect(snapshot.reason).assertEqual('BOTH_CORRUPT');
        expect(snapshot.canOfferRebuild).assertTrue();
        expect(snapshot.canConfirm).assertFalse();
        expect(snapshot.busy).assertFalse();
        expect(snapshot.recoveryError.indexOf('恢复失败') >= 0).assertTrue();
        expect(snapshot.reviewMessage.length > 0).assertTrue();
        expect(gateway.rebuildCalls).assertEqual(0);
        expect(gateway.stateReads).assertEqual(1);
        expect(gateway.confirmedValues.length).assertEqual(0);
        done();
      });

    it('requestConfirmationDoesNotWriteOrCallGateway', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(readyState(), rebuiltResult('archive-1'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        const readsAfterPrepare: number = gateway.stateReads;

        const snapshot: RebuildUiSnapshot = coordinator.requestRebuild();
        expect(snapshot.phase).assertEqual('CONFIRMING');
        expect(snapshot.canConfirm).assertTrue();
        expect(snapshot.canCancel).assertTrue();
        expect(snapshot.canOfferRebuild).assertFalse();
        expect(snapshot.busy).assertFalse();
        expect(gateway.rebuildCalls).assertEqual(0);
        expect(gateway.stateReads).assertEqual(readsAfterPrepare);
        expect(gateway.confirmedValues.length).assertEqual(0);
        done();
      });

    it('cancelConfirmationMakesZeroCallsAndRestoresAvailable', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(readyState(), rebuiltResult('archive-1'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        const readsAfterPrepare: number = gateway.stateReads;
        coordinator.requestRebuild();

        const snapshot: RebuildUiSnapshot = coordinator.cancelRebuild();
        expect(snapshot.phase).assertEqual('AVAILABLE');
        expect(snapshot.canOfferRebuild).assertTrue();
        expect(snapshot.failureMessage).assertEqual('');
        expect(snapshot.archiveId).assertEqual('');
        expect(gateway.rebuildCalls).assertEqual(0);
        expect(gateway.stateReads).assertEqual(readsAfterPrepare);
        expect(gateway.confirmedValues.length).assertEqual(0);
        done();
      });

    it('confirmWithoutSecondConfirmationDoesNotExecute', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(readyState(), rebuiltResult('archive-1'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');

        const snapshot: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(snapshot.phase).assertEqual('AVAILABLE');
        expect(snapshot.busy).assertFalse();
        expect(gateway.rebuildCalls).assertEqual(0);
        expect(gateway.confirmedValues.length).assertEqual(0);
        done();
      });

    it('confirmedRebuildIsBusyAndDuplicateConfirmIsIgnoredUntilResolution', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(readyState(), rebuiltResult('archive-6'));
        gateway.defer = true;
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        coordinator.requestRebuild();

        const pending: Promise<RebuildUiSnapshot> = coordinator.confirmRebuild();
        const active: RebuildUiSnapshot = coordinator.getSnapshot();
        expect(active.phase).assertEqual('REBUILDING');
        expect(active.busy).assertTrue();
        expect(active.canConfirm).assertFalse();
        expect(active.canCancel).assertFalse();
        expect(active.canOfferRebuild).assertFalse();
        expect(active.canRetryRead).assertFalse();
        expect(gateway.rebuildCalls).assertEqual(1);

        // A second tap while B is still working must not issue another write.
        const duplicate: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(duplicate.phase).assertEqual('REBUILDING');
        expect(gateway.rebuildCalls).assertEqual(1);

        gateway.resolvePending(rebuiltResult('archive-6'));
        const finished: RebuildUiSnapshot = await pending;
        expect(finished.phase).assertEqual('REBUILT');
        expect(finished.busy).assertFalse();
        expect(gateway.rebuildCalls).assertEqual(1);
        expect(gateway.confirmedValues.length).assertEqual(1);
        expect(gateway.confirmedValues[0]).assertTrue();
        done();
      });

    it('successPublishesTheRealEmptyStoreOnlyAfterCompletion', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(readyState(), rebuiltResult('archive-7'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        coordinator.requestRebuild();

        const snapshot: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(snapshot.phase).assertEqual('REBUILT');
        expect(snapshot.busy).assertFalse();
        expect(snapshot.canOfferRebuild).assertFalse();
        expect(snapshot.canConfirm).assertFalse();
        expect(snapshot.archiveId).assertEqual('archive-7');
        expect(snapshot.lastStatus).assertEqual('REBUILT');
        expect(snapshot.successMessage.length > 0).assertTrue();
        expect(snapshot.store !== null).assertTrue();
        if (snapshot.store !== null) {
          expect(snapshot.store.plans.length).assertEqual(0);
          expect(snapshot.store.activePlanId === null).assertTrue();
        }

        // A rebuilt store never offers another rebuild.
        const afterRequest: RebuildUiSnapshot = coordinator.requestRebuild();
        expect(afterRequest.phase).assertEqual('REBUILT');
        const afterConfirm: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(afterConfirm.phase).assertEqual('REBUILT');
        expect(gateway.rebuildCalls).assertEqual(1);
        done();
      });

    it('failureKeepsErrorAndArchiveIdAndOffersRetryOnlyFromFreshReadyState', 0,
      async (done: Function) => {
        const message: string = '空库写入失败，未发布就绪状态。';
        const gateway: FakeRebuildGateway = new FakeRebuildGateway(readyState(),
          failedResult('EMPTY_WRITE_FAILED', message, 'archive-8'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        coordinator.requestRebuild();

        const failed: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(failed.phase).assertEqual('FAILED');
        expect(failed.busy).assertFalse();
        expect(failed.failureMessage).assertEqual(message);
        expect(failed.archiveId).assertEqual('archive-8');
        expect(failed.lastStatus).assertEqual('EMPTY_WRITE_FAILED');
        expect(failed.successMessage).assertEqual('');
        expect(failed.store === null).assertTrue();
        expect(failed.canRetryRead).assertTrue();
        // Fake B reports READY again after the failure, so retry requires a
        // brand-new independent confirmation.
        expect(failed.canOfferRebuild).assertTrue();

        coordinator.requestRebuild();
        expect(coordinator.getSnapshot().phase).assertEqual('CONFIRMING');
        gateway.nextResult = rebuiltResult('archive-8b');
        const retried: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(retried.phase).assertEqual('REBUILT');
        expect(retried.archiveId).assertEqual('archive-8b');
        expect(gateway.rebuildCalls).assertEqual(2);
        done();
      });

    it('failedRetryWithoutNewArchiveIdKeepsTheEarlierArchiveId', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway = new FakeRebuildGateway(readyState(),
          failedResult('EMPTY_WRITE_FAILED', '第一次空库写入失败。', 'archive-9'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        coordinator.requestRebuild();
        await coordinator.confirmRebuild();

        gateway.nextResult = failedResult('ARCHIVE_FAILED', '归档未完成。', null);
        coordinator.requestRebuild();
        const second: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(second.phase).assertEqual('FAILED');
        expect(second.failureMessage).assertEqual('归档未完成。');
        expect(second.archiveId).assertEqual('archive-9');
        expect(second.lastStatus).assertEqual('ARCHIVE_FAILED');
        expect(gateway.rebuildCalls).assertEqual(2);
        done();
      });

    it('cancelAfterFailedRetryKeepsFailureAndArchiveWithZeroCalls', 0,
      async (done: Function) => {
        const message: string = '空库落盘校验失败。';
        const gateway: FakeRebuildGateway = new FakeRebuildGateway(readyState(),
          failedResult('VERIFY_FAILED', message, 'archive-10'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        coordinator.requestRebuild();
        await coordinator.confirmRebuild();
        const callsAfterFailure: number = gateway.rebuildCalls;

        coordinator.requestRebuild();
        const cancelled: RebuildUiSnapshot = coordinator.cancelRebuild();
        expect(cancelled.phase).assertEqual('FAILED');
        expect(cancelled.failureMessage).assertEqual(message);
        expect(cancelled.archiveId).assertEqual('archive-10');
        expect(cancelled.canOfferRebuild).assertTrue();
        expect(gateway.rebuildCalls).assertEqual(callsAfterFailure);
        done();
      });

    it('futureSchemaNeverOffersRebuildOrCallsTheGateway', 0,
      async (done: Function) => {
        const future: RebuildState = makeState('BLOCKED', false, 'FUTURE_SCHEMA',
          '任一快照为未知未来版本，禁止破坏性重建。');
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(future, rebuiltResult('archive-1'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);

        const prepared: RebuildUiSnapshot =
          coordinator.prepare('方案库恢复失败：未知未来版本。');
        expect(prepared.phase).assertEqual('BLOCKED');
        expect(prepared.reason).assertEqual('FUTURE_SCHEMA');
        expect(prepared.canOfferRebuild).assertFalse();
        expect(prepared.guidance.indexOf('未来') >= 0).assertTrue();

        const requested: RebuildUiSnapshot = coordinator.requestRebuild();
        expect(requested.phase).assertEqual('BLOCKED');
        expect(requested.canOfferRebuild).assertFalse();
        const confirmed: RebuildUiSnapshot = await coordinator.confirmRebuild();
        expect(confirmed.phase).assertEqual('BLOCKED');
        expect(gateway.rebuildCalls).assertEqual(0);
        expect(gateway.confirmedValues.length).assertEqual(0);
        done();
      });

    it('ioErrorNeverOffersRebuildOrCallsTheGateway', 0,
      async (done: Function) => {
        const ioError: RebuildState = makeState('BLOCKED', false, 'IO_ERROR',
          '读取快照失败，无法确认数据状态。');
        const gateway: FakeRebuildGateway =
          new FakeRebuildGateway(ioError, rebuiltResult('archive-1'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);

        const prepared: RebuildUiSnapshot =
          coordinator.prepare('方案库恢复失败：读取失败。');
        expect(prepared.phase).assertEqual('BLOCKED');
        expect(prepared.reason).assertEqual('IO_ERROR');
        expect(prepared.canOfferRebuild).assertFalse();
        expect(prepared.guidance.indexOf('读取失败') >= 0).assertTrue();

        coordinator.requestRebuild();
        await coordinator.confirmRebuild();
        expect(gateway.rebuildCalls).assertEqual(0);
        done();
      });

    it('incompleteDamageNeverOffersRebuild', 0, async (done: Function) => {
      const incomplete: RebuildState = makeState('BLOCKED', false,
        'INCOMPLETE_DAMAGE', '主备快照并非同时存在且损坏。');
      const gateway: FakeRebuildGateway =
        new FakeRebuildGateway(incomplete, rebuiltResult('archive-1'));
      const coordinator: RebuildCoordinator = makeCoordinator(gateway);

      const prepared: RebuildUiSnapshot =
        coordinator.prepare('方案库恢复失败：主快照缺失且备份损坏。');
      expect(prepared.phase).assertEqual('BLOCKED');
      expect(prepared.canOfferRebuild).assertFalse();
      expect(prepared.guidance.indexOf('损坏不完整') >= 0).assertTrue();
      expect(gateway.rebuildCalls).assertEqual(0);
      done();
    });

    it('prepareAfterRebuildFailureRetainsErrorAndArchiveForTheRetryPage', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway = new FakeRebuildGateway(readyState(),
          failedResult('EMPTY_WRITE_FAILED', '空库写入失败。', 'archive-11'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        coordinator.requestRebuild();
        await coordinator.confirmRebuild();

        const prepared: RebuildUiSnapshot =
          coordinator.prepare('方案库恢复失败：重新读取后仍损坏。');
        expect(prepared.phase).assertEqual('AVAILABLE');
        expect(prepared.canOfferRebuild).assertTrue();
        expect(prepared.failureMessage).assertEqual('空库写入失败。');
        expect(prepared.archiveId).assertEqual('archive-11');
        expect(prepared.lastStatus).assertEqual('EMPTY_WRITE_FAILED');
        expect(prepared.recoveryError.indexOf('重新读取后仍损坏') >= 0).assertTrue();
        expect(gateway.rebuildCalls).assertEqual(1);
        done();
      });

    it('prepareAfterFailureWithFutureStateHidesTheRebuildEntry', 0,
      async (done: Function) => {
        const gateway: FakeRebuildGateway = new FakeRebuildGateway(readyState(),
          failedResult('ARCHIVE_FAILED', '归档未完成。', 'archive-12'));
        const coordinator: RebuildCoordinator = makeCoordinator(gateway);
        coordinator.prepare('方案库恢复失败：主快照与备份均已损坏。');
        coordinator.requestRebuild();
        await coordinator.confirmRebuild();

        gateway.state = makeState('BLOCKED', false, 'FUTURE_SCHEMA',
          '重新审查发现未来版本。');
        const prepared: RebuildUiSnapshot =
          coordinator.prepare('方案库恢复失败：重新读取发现未来版本。');
        expect(prepared.phase).assertEqual('BLOCKED');
        expect(prepared.reason).assertEqual('FUTURE_SCHEMA');
        expect(prepared.canOfferRebuild).assertFalse();
        expect(prepared.guidance.indexOf('未来') >= 0).assertTrue();
        // The previous failure detail is kept, but no rebuild action exists.
        expect(prepared.failureMessage).assertEqual('归档未完成。');
        expect(prepared.archiveId).assertEqual('archive-12');
        const requested: RebuildUiSnapshot = coordinator.requestRebuild();
        expect(requested.phase).assertEqual('BLOCKED');
        expect(gateway.rebuildCalls).assertEqual(1);
        done();
      });
  });
}
