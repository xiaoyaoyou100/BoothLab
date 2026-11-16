import localUnitTest from './LocalUnit.test';
import catalogListTest from './CatalogList.test';
import editorListTest from './EditorList.test';
import reviewRegressionTest from './ReviewRegression.test';
import planRepositoryListTest from './PlanRepositoryList.test';
import persistenceListTest from './PersistenceList.test';

import historyListTest from './HistoryList.test';
import layoutListTest from './LayoutList.test';
import m2AuditTest from './M2Audit.test';
import saveCoordinatorListTest from './SaveCoordinatorList.test';
import editorChangeTest from './EditorChange.test';
import rebuildCoordinatorListTest from './RebuildCoordinatorList.test';
import m3ObjectVisualsTest from './M3ObjectVisuals.test';
import m3PlanUiTest from './M3PlanUi.test';
import m3EditorUiTest from './M3EditorUi.test';

export default function testsuite() {
  localUnitTest();
  catalogListTest();
  editorListTest();
  reviewRegressionTest();
  planRepositoryListTest();
  persistenceListTest();
  historyListTest();
  layoutListTest();
  m2AuditTest();
  saveCoordinatorListTest();
  editorChangeTest();
  rebuildCoordinatorListTest();
  m3ObjectVisualsTest();
  m3PlanUiTest();
  m3EditorUiTest();
}
