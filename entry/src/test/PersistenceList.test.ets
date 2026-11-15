import persistenceTest from './Persistence.test';

/**
 * Registers the M2-B02 durable Preferences persistence suite. All M1 and B01
 * suites remain registered by List.test.ets.
 */
export default function persistenceListTest() {
  persistenceTest();
}
