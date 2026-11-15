import layoutTest from './Layout.test';

/**
 * Registers the M2 layout-validation test suite for local unit tests.
 * The shared List.test.ets remains the single coordinator.
 */
export default function layoutListTest() {
  layoutTest();
}
