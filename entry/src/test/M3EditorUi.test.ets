import { describe, it, expect } from '@ohos/hypium';
import { LayoutIssue } from '../main/ets/model/BoothModels';
import { SaveState } from '../main/ets/model/M2Contracts';
import {
  canAddAction,
  canBackAction,
  canCenterAction,
  canDeleteAction,
  canRedoAction,
  canRotateAction,
  canSaveAction,
  canUndoAction,
  findIssueSeverityForObject,
  formatFootprintText,
  formatIssueIdsLabel,
  formatIssueSeverityLabel,
  formatIssueTypeLabel,
  formatLayoutIssueSummary,
  formatObjectCount,
  formatRotationText,
  formatSaveButtonLabel,
  formatSaveStateLabel,
  formatSelectedCenterText
} from '../main/ets/components/editor/EditorWorkspace';

/**
 * M3-A01 editor presentation tests.
 *
 * These tests exercise the pure helpers actually called by EditorWorkspace for
 * the externally owned save/closing state, controller-derived tool
 * availability, committed selected-object properties and layout-issue text.
 * They do not instantiate the ArkUI component or claim touch, Canvas or device
 * behaviour; those are verified on the emulator separately.
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
  });
}
