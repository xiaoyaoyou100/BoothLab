import { describe, it, expect } from '@ohos/hypium';
import { BoothTemplate, PlacedObject, Rect } from '../main/ets/model/BoothModels';
import { getTemplateById } from '../main/ets/catalog/BoothTemplates';
import { canPlace, validateLayout } from '../main/ets/engine/LayoutValidator';

function template(): BoothTemplate {
  const value = getTemplateById('standard');
  if (value === undefined) { throw new Error('Missing template'); }
  return value;
}

function object(): PlacedObject {
  return { id: 'audit-object', catalogId: 'display_table', centerX: 300,
    centerY: 200, rotation: 0, zIndex: 1 };
}

export default function m2AuditTest() {
  describe('M2Audit', () => {
    it('nullBlockedRectangleReturnsErrorInsteadOfThrowing', 0, () => {
      const booth = template();
      booth.blockedAreas = [JSON.parse('null') as Rect];
      expect(canPlace(booth, object()).code).assertEqual('INVALID_ARGUMENT');
    });
    it('nonFiniteZIndexCannotBeReportedAsValidLayout', 0, () => {
      const item = object();
      item.zIndex = Number.NaN;
      const issues = validateLayout(template(), [item]);
      expect(issues.some((issue) => issue.code === 'INVALID_ARGUMENT')).assertTrue();
    });
    it('whitespaceObjectIdCannotBeReportedAsValidLayout', 0, () => {
      const item = object();
      item.id = '   ';
      const issues = validateLayout(template(), [item]);
      expect(issues.some((issue) => issue.code === 'INVALID_ARGUMENT')).assertTrue();
    });
  });
}
