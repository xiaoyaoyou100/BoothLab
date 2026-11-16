import { describe, it, expect } from '@ohos/hypium';
import {
  BoothPlan,
  CatalogItem,
  LayoutIssue,
  PlacedObject,
  Viewport
} from '../main/ets/model/BoothModels';
import { SaveState } from '../main/ets/model/M2Contracts';
import { EditorController } from '../main/ets/engine/EditorController';
import { EditorChangeNotifier } from '../main/ets/application/EditorChangeNotifier';
import { createViewport } from '../main/ets/engine/GeometryEngine';
import {
  addCatalogObject,
  canAddAction,
  canBackAction,
  canCenterAction,
  canDeleteAction,
  canRedoAction,
  canRotateAction,
  canSaveAction,
  canUndoAction,
  findIssueSeverityForObject,
  findLegalAddCenter,
  formatFootprintText,
  formatIssueIdsLabel,
  formatIssueSeverityLabel,
  formatIssueTypeLabel,
  formatLayoutIssueSummary,
  formatObjectCount,
  formatRotationText,
  formatSaveButtonLabel,
  formatSaveStateLabel,
  formatSelectedCenterText,
  isPickerDisabled,
  resolveObjectVisualDraw,
  resolveObjectVisualForCatalogId
} from '../main/ets/components/editor/EditorWorkspace';

/**
 * M3-A02 editor presentation and integration tests.
 *
 * The original A01 presentation helpers remain covered. The A02 additions
 * exercise the real integration adapters actually called by EditorWorkspace:
 * one picker selection -> one existing Controller add, truthful success and
 * failure outcomes, revision-based formal notification, and the cm -> vp
 * transform with unrotated catalog extents plus one actual rotation.
 *
 * These tests do not instantiate the ArkUI component or claim touch, Canvas,
 * sheet or device behaviour; those are verified on the emulator separately.
 */

function issue(code: string, severity: string, objectIds: string[]): LayoutIssue {
  const result: LayoutIssue = {
    code: code,
    severity: severity,
    message: code + ' message',
    objectIds: objectIds
  };
  return result;
}

function openTestPlan(controller: EditorController): BoothPlan {
  const plan: BoothPlan = {
    id: 'plan-a02-probe-test',
    name: 'A02 Probe Test',
    templateId: 'standard',
    objects: [],
    createdAt: 1,
    updatedAt: 1
  };
  const imported = controller.importPlan(plan);
  if (imported.code !== 'OK' || imported.data === undefined) {
    throw new Error('Test setup failed to import the probe plan.');
  }
  return imported.data;
}

function requirePlan(controller: EditorController): BoothPlan {
  const exported = controller.exportPlan();
  if (exported.code !== 'OK' || exported.data === undefined) {
    throw new Error('Test setup failed to export a plan.');
  }
  return exported.data;
}

function requireDraw(viewport: Viewport | null, object: PlacedObject,
  catalog: CatalogItem) {
  const draw = resolveObjectVisualDraw(viewport, object, catalog);
  if (draw === null) {
    throw new Error('Test expected a drawable object visual.');
  }
  return draw;
}

export default function m3EditorUiTest() {
  describe('M3EditorUi', () => {
    it('mapsEveryExternalSaveStateToTruthfulText', 0, () => {
      expect(formatSaveStateLabel('Dirty', false, false)).assertEqual('未保存');
      expect(formatSaveStateLabel('Saving', false, false)).assertEqual('保存中');
      expect(formatSaveStateLabel('Saved', false, false)).assertEqual('已保存');
      expect(formatSaveStateLabel('SaveError', false, false)).assertEqual('保存失败');

      const unknownState: SaveState = 'Unknown' as SaveState;
      expect(formatSaveStateLabel(unknownState, false, false)).assertEqual('未保存');
    });

    it('distinguishesRealBusyAndClosingFromStoredState', 0, () => {
      expect(formatSaveStateLabel('Dirty', true, false)).assertEqual('保存中');
      expect(formatSaveStateLabel('Dirty', true, true)).assertEqual('正在保存并返回');
      expect(formatSaveStateLabel('Saving', false, true)).assertEqual('正在保存并返回');
      expect(formatSaveStateLabel('Saved', false, true)).assertEqual('正在返回');
      // A real error is never hidden behind a transient closing label.
      expect(formatSaveStateLabel('SaveError', true, true)).assertEqual('保存失败');
    });

    it('derivesSaveButtonTextAndAvailabilityFromRealState', 0, () => {
      expect(formatSaveButtonLabel('Dirty', false, false)).assertEqual('保存');
      expect(formatSaveButtonLabel('Saved', false, false)).assertEqual('保存');
      expect(formatSaveButtonLabel('SaveError', false, false)).assertEqual('重试');
      expect(formatSaveButtonLabel('Saving', false, false)).assertEqual('保存中');
      expect(formatSaveButtonLabel('Dirty', true, false)).assertEqual('保存中');
      expect(formatSaveButtonLabel('Saved', false, true)).assertEqual('返回中');

      expect(canSaveAction(false, false, 'Dirty')).assertTrue();
      expect(canSaveAction(false, false, 'Saved')).assertTrue();
      expect(canSaveAction(false, false, 'SaveError')).assertTrue();
      expect(canSaveAction(true, false, 'Dirty')).assertFalse();
      expect(canSaveAction(false, true, 'Dirty')).assertFalse();
      expect(canSaveAction(false, false, 'Saving')).assertFalse();

      expect(canBackAction(false)).assertTrue();
      expect(canBackAction(true)).assertFalse();
    });

    it('blocksHistoryAndObjectToolsWhileDraggingOrLocked', 0, () => {
      expect(canUndoAction(true, false, false)).assertTrue();
      expect(canUndoAction(true, true, false)).assertFalse();
      expect(canUndoAction(true, false, true)).assertFalse();
      expect(canUndoAction(false, false, false)).assertFalse();

      expect(canRedoAction(true, false, false)).assertTrue();
      expect(canRedoAction(true, true, false)).assertFalse();
      expect(canRedoAction(true, false, true)).assertFalse();
      expect(canRedoAction(false, false, false)).assertFalse();

      expect(canDeleteAction(true, false, false)).assertTrue();
      expect(canDeleteAction(false, false, false)).assertFalse();
      expect(canDeleteAction(true, true, false)).assertFalse();
      expect(canDeleteAction(true, false, true)).assertFalse();

      expect(canRotateAction(true, false, false)).assertTrue();
      expect(canRotateAction(false, false, false)).assertFalse();
      expect(canRotateAction(true, true, false)).assertFalse();

      expect(canCenterAction(true, false, false)).assertTrue();
      expect(canCenterAction(false, false, false)).assertFalse();
      expect(canCenterAction(true, false, true)).assertFalse();

      expect(canAddAction(false, false)).assertTrue();
      expect(canAddAction(true, false)).assertFalse();
      expect(canAddAction(false, true)).assertFalse();
    });

    it('formatsCommittedCentreFootprintAndRotationReadably', 0, () => {
      expect(formatSelectedCenterText(300, 200)).assertEqual('中心 (300, 200) cm');
      expect(formatSelectedCenterText(12.5, 40)).assertEqual('中心 (12.5, 40) cm');
      expect(formatSelectedCenterText(NaN, 200)).assertEqual('中心坐标无效');
      expect(formatSelectedCenterText(300, Infinity)).assertEqual('中心坐标无效');

      expect(formatFootprintText(120, 60)).assertEqual('占位 120×60 cm');
      expect(formatFootprintText(60, 120)).assertEqual('占位 60×120 cm');
      expect(formatFootprintText(0, 60)).assertEqual('占位尺寸未知');
      expect(formatFootprintText(120, -1)).assertEqual('占位尺寸未知');
      expect(formatFootprintText(NaN, 60)).assertEqual('占位尺寸未知');

      expect(formatRotationText(0)).assertEqual('旋转 0°');
      expect(formatRotationText(90)).assertEqual('旋转 90°');
      expect(formatRotationText(270)).assertEqual('旋转 270°');
      expect(formatRotationText(NaN)).assertEqual('旋转 —');
    });

    it('formatsObjectAndIssueCountsWithoutInventingValues', 0, () => {
      expect(formatObjectCount(0)).assertEqual('物件 0 件');
      expect(formatObjectCount(3)).assertEqual('物件 3 件');
      expect(formatObjectCount(-1)).assertEqual('物件 0 件');
      expect(formatObjectCount(NaN)).assertEqual('物件 0 件');

      expect(formatLayoutIssueSummary(0)).assertEqual('布局正常');
      expect(formatLayoutIssueSummary(2)).assertEqual('布局提醒 2 条');
      expect(formatLayoutIssueSummary(-1)).assertEqual('布局正常');
      expect(formatLayoutIssueSummary(NaN)).assertEqual('布局正常');
    });

    it('mapsRealIssueCodesSeverityAndObjectIds', 0, () => {
      expect(formatIssueTypeLabel('OVERLAP')).assertEqual('重叠');
      expect(formatIssueTypeLabel('ENTRY_OCCUPIED')).assertEqual('预留区');
      expect(formatIssueTypeLabel('BLOCKED_AREA')).assertEqual('禁放区');
      expect(formatIssueTypeLabel('OUT_OF_BOUNDS')).assertEqual('越界');
      expect(formatIssueTypeLabel('INVALID_ARGUMENT')).assertEqual('数据异常');
      expect(formatIssueTypeLabel('SOMETHING_ELSE')).assertEqual('数据异常');

      expect(formatIssueSeverityLabel('error')).assertEqual('错误');
      expect(formatIssueSeverityLabel('warning')).assertEqual('提醒');
      expect(formatIssueSeverityLabel('other')).assertEqual('提示');

      expect(formatIssueIdsLabel([])).assertEqual('展位或数据');
      expect(formatIssueIdsLabel(['obj-1'])).assertEqual('obj-1');
      expect(formatIssueIdsLabel(['obj-1', 'obj-2'])).assertEqual('obj-1 / obj-2');
    });

    it('linksSelectionToHighestSeverityIssueWithoutMutatingIssues', 0, () => {
      const warningOnly: LayoutIssue[] = [
        issue('ENTRY_OCCUPIED', 'warning', ['obj-a']),
        issue('OVERLAP', 'warning', ['obj-a', 'obj-b']),
        issue('OUT_OF_BOUNDS', 'error', ['obj-z']),
        issue('OVERLAP', 'warning', [])
      ];

      expect(findIssueSeverityForObject(warningOnly, 'obj-a')).assertEqual('warning');
      expect(findIssueSeverityForObject(warningOnly, 'obj-b')).assertEqual('warning');
      expect(findIssueSeverityForObject(warningOnly, 'obj-z')).assertEqual('error');
      expect(findIssueSeverityForObject(warningOnly, 'missing')).assertEqual('');
      expect(findIssueSeverityForObject(warningOnly, '')).assertEqual('');

      const errorAndWarning: LayoutIssue[] = [
        issue('OVERLAP', 'warning', ['obj-a']),
        issue('BLOCKED_AREA', 'error', ['obj-a'])
      ];
      expect(findIssueSeverityForObject(errorAndWarning, 'obj-a')).assertEqual('error');

      const unknownSeverity: LayoutIssue[] = [
        issue('OVERLAP', 'notice', ['obj-a'])
      ];
      expect(findIssueSeverityForObject(unknownSeverity, 'obj-a')).assertEqual('');

      // The helper only reads issues and objectIds.
      expect(warningOnly.length).assertEqual(4);
      expect(warningOnly[1].objectIds.length).assertEqual(2);
      expect(warningOnly[1].objectIds[0]).assertEqual('obj-a');
      const ids: string[] = ['obj-1', 'obj-2'];
      formatIssueIdsLabel(ids);
      expect(ids.length).assertEqual(2);
      expect(ids[1]).assertEqual('obj-2');
    });

    // ------------------------------------------------------------------
    // A02 picker -> existing add path integration
    // ------------------------------------------------------------------

    it('addsExactlyOneObjectThroughTheExistingControllerPath', 0, () => {
      const controller: EditorController = new EditorController('standard');
      const before: BoothPlan = openTestPlan(controller);
      const revisionBefore: number = controller.getChangeRevision();
      const selectionBefore: string | null = controller.getSelectedId();

      const attempt = addCatalogObject(controller, 'reception', false);
      expect(attempt.code).assertEqual('OK');
      if (attempt.addedObject === null || attempt.catalogItem === null) {
        throw new Error('Expected one committed object.');
      }
      expect(attempt.catalogItem.id).assertEqual('reception');
      expect(attempt.addedObject.catalogId).assertEqual('reception');
      expect(attempt.addedObject.rotation).assertEqual(0);
      expect(attempt.addedObject.centerX).assertEqual(300);
      expect(attempt.addedObject.centerY).assertEqual(200);

      const after: BoothPlan = requirePlan(controller);
      expect(after.objects.length).assertEqual(before.objects.length + 1);
      expect(after.id).assertEqual(before.id);
      expect(after.name).assertEqual(before.name);
      expect(after.templateId).assertEqual(before.templateId);
      expect(controller.getChangeRevision()).assertEqual(revisionBefore + 1);
      // No extra selection, preview or drag history is created by the add.
      expect(controller.getSelectedId()).assertEqual(selectionBefore);
      expect(controller.getPreviewObject() === null).assertTrue();
      expect(controller.isDragging()).assertFalse();
      expect(controller.canUndo()).assertTrue();

      // Exactly one new object was appended to the imported empty plan.
      let receptionCount: number = 0;
      for (let i = 0; i < after.objects.length; i++) {
        if (after.objects[i].catalogId === 'reception') {
          receptionCount++;
        }
      }
      expect(receptionCount).assertEqual(1);
      expect(after.objects[0].id).assertEqual(attempt.addedObject.id);
      expect(after.objects[0].catalogId).assertEqual('reception');
      expect(after.objects[0].centerX).assertEqual(300);
      expect(after.objects[0].centerY).assertEqual(200);
      expect(after.objects[0].rotation).assertEqual(0);
    });

    it('notifiesFormalChangeOnceOnSuccessAndNeverOnFailure', 0, () => {
      const controller: EditorController = new EditorController('standard');
      openTestPlan(controller);
      const notifier: EditorChangeNotifier = new EditorChangeNotifier();
      notifier.reset(controller.getChangeRevision());
      let notifications: number = 0;
      const collect = () => {
        if (notifier.shouldNotify(controller.getChangeRevision())) {
          notifications++;
        }
      };

      collect();
      expect(notifications).assertEqual(0);

      const success = addCatalogObject(controller, 'chair', false);
      expect(success.code).assertEqual('OK');
      collect();
      expect(notifications).assertEqual(1);
      // Repeated refreshes of the same revision do not duplicate notification.
      collect();
      expect(notifications).assertEqual(1);

      const revisionAfterSuccess: number = controller.getChangeRevision();
      const countAfterSuccess: number = controller.getObjects().length;
      const failure = addCatalogObject(controller, 'not_in_catalog', false);
      expect(failure.code).assertEqual('NOT_FOUND');
      expect(failure.addedObject === null).assertTrue();
      expect(controller.getChangeRevision()).assertEqual(revisionAfterSuccess);
      expect(controller.getObjects().length).assertEqual(countAfterSuccess);
      collect();
      expect(notifications).assertEqual(1);

      // Selection alone is not a formal change and must not notify.
      controller.selectObject(null);
      collect();
      expect(notifications).assertEqual(1);
    });

    it('suppressesDisabledPickerSelectionWithoutMutation', 0, () => {
      const controller: EditorController = new EditorController('standard');
      const before: BoothPlan = openTestPlan(controller);
      const revisionBefore: number = controller.getChangeRevision();
      const attempt = addCatalogObject(controller, 'shelf', true);

      expect(attempt.code).assertEqual('INVALID_ARGUMENT');
      expect(attempt.addedObject === null).assertTrue();
      expect(attempt.message.indexOf('当前不可添加') >= 0).assertTrue();
      expect(controller.getObjects().length).assertEqual(before.objects.length);
      expect(controller.getChangeRevision()).assertEqual(revisionBefore);
      expect(controller.getSelectedId() === null).assertTrue();
      expect(controller.getPreviewObject() === null).assertTrue();

      expect(isPickerDisabled(true, false)).assertTrue();
      expect(isPickerDisabled(false, true)).assertTrue();
      expect(isPickerDisabled(true, true)).assertTrue();
      expect(isPickerDisabled(false, false)).assertFalse();
    });

    it('mapsWorldCentreAndUnrotatedExtentsAtZeroNinetyAndTwoSeventy', 0, () => {
      const viewport: Viewport = { scale: 0.5, offsetX: 10, offsetY: 20 };
      const reception: CatalogItem = {
        id: 'reception',
        name: '接待台',
        category: '服务',
        imageKey: 'reception',
        widthCm: 140,
        heightCm: 60
      };
      const base: PlacedObject = {
        id: 'obj-test',
        catalogId: 'reception',
        centerX: 300,
        centerY: 200,
        rotation: 0,
        zIndex: 1
      };

      const draw0 = requireDraw(viewport, base, reception);
      expect(draw0.centerX).assertEqual(160);
      expect(draw0.centerY).assertEqual(120);
      expect(draw0.widthVp).assertEqual(70);
      expect(draw0.heightVp).assertEqual(30);
      expect(draw0.rotation).assertEqual(0);

      const object90: PlacedObject = {
        id: 'obj-test',
        catalogId: 'reception',
        centerX: 300,
        centerY: 200,
        rotation: 90,
        zIndex: 1
      };
      const draw90 = requireDraw(viewport, object90, reception);
      expect(draw90.widthVp).assertEqual(70);
      expect(draw90.heightVp).assertEqual(30);
      expect(draw90.rotation).assertEqual(90);

      const object270: PlacedObject = {
        id: 'obj-test',
        catalogId: 'reception',
        centerX: 300,
        centerY: 200,
        rotation: 270,
        zIndex: 1
      };
      const draw270 = requireDraw(viewport, object270, reception);
      expect(draw270.widthVp).assertEqual(70);
      expect(draw270.heightVp).assertEqual(30);
      expect(draw270.rotation).assertEqual(270);

      // The helper only reads its inputs.
      expect(base.rotation).assertEqual(0);
      expect(reception.widthCm).assertEqual(140);
      expect(reception.heightCm).assertEqual(60);
    });

    it('usesTheExistingViewportScaleWithoutSwappingRotatedFootprint', 0, () => {
      const controller: EditorController = new EditorController('standard');
      const template = controller.getTemplate();
      const viewportResult = createViewport(387.69, 429.23,
        template.widthCm, template.heightCm, 24);
      if (viewportResult.code !== 'OK' || viewportResult.data === undefined) {
        throw new Error('Test viewport creation failed.');
      }
      const viewport: Viewport = viewportResult.data;
      const table: CatalogItem = {
        id: 'display_table',
        name: '展示桌',
        category: '展示',
        imageKey: 'display_table',
        widthCm: 120,
        heightCm: 60
      };
      const rotated: PlacedObject = {
        id: 'obj-rotated',
        catalogId: 'display_table',
        centerX: 300,
        centerY: 200,
        rotation: 270,
        zIndex: 1
      };
      const draw = requireDraw(viewport, rotated, table);
      const expectedWidth: number = viewport.scale * 120;
      const expectedHeight: number = viewport.scale * 60;
      expect(Math.abs(draw.widthVp - expectedWidth) < 0.0000001).assertTrue();
      expect(Math.abs(draw.heightVp - expectedHeight) < 0.0000001).assertTrue();
      expect(Math.abs(draw.centerX - (viewport.offsetX + 300 * viewport.scale)) <
        0.0000001).assertTrue();
      expect(Math.abs(draw.centerY - (viewport.offsetY + 200 * viewport.scale)) <
        0.0000001).assertTrue();
      expect(draw.rotation).assertEqual(270);
      // The unrotated 120x60 pair is never exchanged for 60x120.
      expect(draw.widthVp > draw.heightVp).assertTrue();
    });

    it('rejectsUnknownCatalogAndInvalidGeometryInsteadOfInventingSize', 0, () => {
      const controller: EditorController = new EditorController('standard');
      const beforeCount: number = controller.getObjects().length;
      const unknown = addCatalogObject(controller, 'not_in_catalog', false);
      expect(unknown.code).assertEqual('NOT_FOUND');
      expect(unknown.message.indexOf('不在目录') >= 0).assertTrue();
      expect(unknown.addedObject === null).assertTrue();
      expect(controller.getObjects().length).assertEqual(beforeCount);
      expect(controller.getCatalogItem('not_in_catalog').code).assertEqual('NOT_FOUND');

      const viewport: Viewport = { scale: 0.5, offsetX: 0, offsetY: 0 };
      const reception: CatalogItem = {
        id: 'reception',
        name: '接待台',
        category: '服务',
        imageKey: 'reception',
        widthCm: 140,
        heightCm: 60
      };
      const invalidCenter: PlacedObject = {
        id: 'obj-invalid',
        catalogId: 'reception',
        centerX: NaN,
        centerY: 200,
        rotation: 0,
        zIndex: 1
      };
      expect(resolveObjectVisualDraw(viewport, invalidCenter, reception) === null)
        .assertTrue();

      const invalidDims: CatalogItem = {
        id: 'reception',
        name: '接待台',
        category: '服务',
        imageKey: 'reception',
        widthCm: 0,
        heightCm: 60
      };
      const validObject: PlacedObject = {
        id: 'obj-valid',
        catalogId: 'reception',
        centerX: 300,
        centerY: 200,
        rotation: 0,
        zIndex: 1
      };
      expect(resolveObjectVisualDraw(viewport, validObject, invalidDims) === null)
        .assertTrue();
      expect(resolveObjectVisualDraw(null, validObject, reception) === null).assertTrue();

      // The Canvas draw path rejects an unknown catalog id through the frozen
      // controller lookup rather than inventing a size or image.
      const unknownObject: PlacedObject = {
        id: 'obj-unknown',
        catalogId: 'not_in_catalog',
        centerX: 300,
        centerY: 200,
        rotation: 0,
        zIndex: 1
      };
      expect(resolveObjectVisualForCatalogId(controller, viewport, unknownObject) === null)
        .assertTrue();

      const template = controller.getTemplate();
      const oversized: CatalogItem = {
        id: 'oversized',
        name: '超大物件',
        category: '测试',
        imageKey: 'oversized',
        widthCm: 700,
        heightCm: 60
      };
      expect(findLegalAddCenter(template, oversized) === null).assertTrue();
      const invalidSize: CatalogItem = {
        id: 'invalid',
        name: '无效尺寸',
        category: '测试',
        imageKey: 'generic',
        widthCm: -1,
        heightCm: 60
      };
      expect(findLegalAddCenter(template, invalidSize) === null).assertTrue();

      const legalCenter = findLegalAddCenter(template, reception);
      if (legalCenter === null) {
        throw new Error('Expected a legal add centre.');
      }
      expect(legalCenter.x).assertEqual(300);
      expect(legalCenter.y).assertEqual(200);
    });

    it('passesUnknownImageKeyThroughWithoutSwappingExtents', 0, () => {
      const viewport: Viewport = { scale: 0.5, offsetX: 10, offsetY: 20 };
      const mystery: CatalogItem = {
        id: 'mystery_object',
        name: '未知物件',
        category: '测试',
        imageKey: 'mystery_object',
        widthCm: 140,
        heightCm: 60
      };
      const rotated: PlacedObject = {
        id: 'obj-mystery',
        catalogId: 'mystery_object',
        centerX: 300,
        centerY: 200,
        rotation: 90,
        zIndex: 1
      };
      const draw = requireDraw(viewport, rotated, mystery);
      // The integration forwards the real imageKey; ObjectVisuals owns the
      // generic fallback and still receives the unrotated vp extents.
      expect(draw.imageKey).assertEqual('mystery_object');
      expect(draw.widthVp).assertEqual(70);
      expect(draw.heightVp).assertEqual(30);
      expect(draw.centerX).assertEqual(160);
      expect(draw.centerY).assertEqual(120);
      expect(draw.rotation).assertEqual(90);
    });

    it('failedAddKeepsPlanSelectionPreviewAndHistoryUntouched', 0, () => {
      const controller: EditorController = new EditorController('standard');
      const before: BoothPlan = openTestPlan(controller);
      const revisionBefore: number = controller.getChangeRevision();

      const unknown = addCatalogObject(controller, '', false);
      expect(unknown.code).assertEqual('NOT_FOUND');
      expect(unknown.addedObject === null).assertTrue();
      const disabled = addCatalogObject(controller, 'plant', true);
      expect(disabled.code).assertEqual('INVALID_ARGUMENT');
      expect(disabled.addedObject === null).assertTrue();

      expect(controller.getObjects().length).assertEqual(before.objects.length);
      expect(controller.getChangeRevision()).assertEqual(revisionBefore);
      expect(controller.getSelectedId() === null).assertTrue();
      expect(controller.getPreviewObject() === null).assertTrue();
      expect(controller.isDragging()).assertFalse();
      expect(controller.canUndo()).assertFalse();
      expect(controller.getLayoutIssues().length).assertEqual(0);
    });
  });
}
