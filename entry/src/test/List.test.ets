import localUnitTest from './LocalUnit.test';
import catalogListTest from './CatalogList.test';

export default function testsuite() {
  localUnitTest();
  catalogListTest();
}
