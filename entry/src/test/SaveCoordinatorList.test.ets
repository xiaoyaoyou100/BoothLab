import saveCoordinatorTest from './SaveCoordinator.test';

/**
 * Registers the M2-I01 SaveCoordinator truthfulness suite. All M1/M2-A/M2-B
 * suites stay registered by the shared List.test.ets coordinator.
 */
export default function saveCoordinatorListTest() {
  saveCoordinatorTest();
}
