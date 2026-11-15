import localUnitTest from './LocalUnit.test';
import catalogListTest from './CatalogList.test';
import editorListTest from './EditorList.test';
import reviewRegressionTest from './ReviewRegression.test';

export default function testsuite() {
  localUnitTest();
  catalogListTest();
  editorListTest();
  reviewRegressionTest();
}
