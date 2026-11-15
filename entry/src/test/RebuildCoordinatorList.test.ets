import rebuildCoordinatorTest from './RebuildCoordinator.test';

/**
 * Registers the M2-BOTH-CORRUPTED-RECOVERY recovery-page UI state suite.
 * This is A-owned recovery UI/state coordination coverage; the B repository
 * rebuild behavior remains covered by Persistence.test.ets.
 */
export default function rebuildCoordinatorListTest() {
  rebuildCoordinatorTest();
}
