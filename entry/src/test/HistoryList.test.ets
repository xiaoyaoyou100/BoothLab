import historyTest from './History.test';

/**
 * Registers the M2 history/formal-plan test suite for local unit tests.
 * The shared List.test.ets remains the single coordinator.
 */
export default function historyListTest() {
  historyTest();
}
