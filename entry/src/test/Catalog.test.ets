import { describe, it, expect } from '@ohos/hypium';
import { BoothTemplate, CatalogItem, Rect, Side } from '../main/ets/model/BoothModels';
import { getTemplateById, listTemplates } from '../main/ets/catalog/BoothTemplates';
import { getCatalogItemById, listCatalogItems } from '../main/ets/catalog/ObjectCatalogData';

interface ExpectedCatalogItem {
  id: string;
  name: string;
  category: string;
  widthCm: number;
  heightCm: number;
}

const EXPECTED_CATALOG: ExpectedCatalogItem[] = [
  { id: 'reception', name: '接待台', category: '服务', widthCm: 140, heightCm: 60 },
  { id: 'display_table', name: '展示桌', category: '展示', widthCm: 120, heightCm: 60 },
  { id: 'shelf', name: '作品展架', category: '展示', widthCm: 100, heightCm: 40 },
  { id: 'interactive_screen', name: '互动屏', category: '互动', widthCm: 100, heightCm: 40 },
  { id: 'chair', name: '座椅', category: '家具', widthCm: 50, heightCm: 50 },
  { id: 'storage', name: '储物柜', category: '家具', widthCm: 90, heightCm: 50 },
  { id: 'sign', name: '导视牌', category: '导视', widthCm: 60, heightCm: 40 },
  { id: 'plant', name: '绿植', category: '装饰', widthCm: 60, heightCm: 60 },
  { id: 'plinth', name: '展品台', category: '展示', widthCm: 80, heightCm: 80 },
  { id: 'rollup', name: '易拉宝', category: '导视', widthCm: 80, heightCm: 30 }
];

function countSide(sides: Side[], side: Side): number {
  let count = 0;
  for (let i = 0; i < sides.length; i++) {
    if (sides[i] === side) {
      count++;
    }
  }
  return count;
}

function rectMatches(rect: Rect, x: number, y: number, width: number, height: number): boolean {
  return rect.x === x && rect.y === y && rect.width === width && rect.height === height;
}

function isFinitePositiveRect(rect: Rect): boolean {
  return Number.isFinite(rect.x) && Number.isFinite(rect.y) &&
    Number.isFinite(rect.width) && Number.isFinite(rect.height) &&
    rect.width > 0 && rect.height > 0;
}

function isInsideTemplate(rect: Rect, template: BoothTemplate): boolean {
  return rect.x >= 0 && rect.y >= 0 &&
    rect.x + rect.width <= template.widthCm &&
    rect.y + rect.height <= template.heightCm;
}

export default function catalogTest() {
  describe('CatalogTest', () => {
    it('lookupEveryCatalogIdAndIsolateReturnedItem', 0, () => {
      const items = listCatalogItems();
      for (let i = 0; i < items.length; i++) {
        const item = getCatalogItemById(items[i].id);
        expect(item !== undefined).assertTrue();
        if (item !== undefined) {
          expect(item.widthCm).assertEqual(items[i].widthCm);
          expect(item.heightCm).assertEqual(items[i].heightCm);
          item.widthCm = -1;
          const fresh = getCatalogItemById(items[i].id);
          expect(fresh !== undefined).assertTrue();
          if (fresh !== undefined) {
            expect(fresh.widthCm).assertEqual(items[i].widthCm);
          }
        }
      }
    });
    // ---------------------------------------------------------------------
    // Templates: normal cases
    // ---------------------------------------------------------------------
    it('listTemplatesReturnsStandardAndCornerInStableOrder', 0, () => {
      const templates = listTemplates();
      expect(templates.length).assertEqual(2);
      expect(templates[0].id).assertEqual('standard');
      expect(templates[0].name).assertEqual('标准型展位');
      expect(templates[1].id).assertEqual('corner');
      expect(templates[1].name).assertEqual('转角型展位');
    });

    it('standardTemplateHasExpectedWallsOpenSidesAndReservedArea', 0, () => {
      const template = getTemplateById('standard');
      expect(template !== undefined).assertTrue();
      if (template !== undefined) {
        expect(template.widthCm).assertEqual(600);
        expect(template.heightCm).assertEqual(400);
        expect(template.wallSides.length).assertEqual(3);
        expect(countSide(template.wallSides, 'left')).assertEqual(1);
        expect(countSide(template.wallSides, 'top')).assertEqual(1);
        expect(countSide(template.wallSides, 'right')).assertEqual(1);
        expect(countSide(template.wallSides, 'bottom')).assertEqual(0);
        expect(template.openSides.length).assertEqual(1);
        expect(countSide(template.openSides, 'bottom')).assertEqual(1);
        expect(template.blockedAreas.length).assertEqual(0);
        expect(template.reservedAreas.length).assertEqual(1);
        expect(rectMatches(template.reservedAreas[0], 240, 340, 120, 60)).assertTrue();
      }
    });

    it('cornerTemplateHasExpectedWallsOpenSidesAndReservedAreas', 0, () => {
      const template = getTemplateById('corner');
      expect(template !== undefined).assertTrue();
      if (template !== undefined) {
        expect(template.widthCm).assertEqual(600);
        expect(template.heightCm).assertEqual(400);
        expect(template.wallSides.length).assertEqual(2);
        expect(countSide(template.wallSides, 'left')).assertEqual(1);
        expect(countSide(template.wallSides, 'top')).assertEqual(1);
        expect(countSide(template.wallSides, 'bottom')).assertEqual(0);
        expect(countSide(template.wallSides, 'right')).assertEqual(0);
        expect(template.openSides.length).assertEqual(2);
        expect(countSide(template.openSides, 'bottom')).assertEqual(1);
        expect(countSide(template.openSides, 'right')).assertEqual(1);
        expect(template.blockedAreas.length).assertEqual(0);
        expect(template.reservedAreas.length).assertEqual(2);
        expect(rectMatches(template.reservedAreas[0], 240, 340, 120, 60)).assertTrue();
        expect(rectMatches(template.reservedAreas[1], 540, 140, 60, 120)).assertTrue();
      }
    });

    // ---------------------------------------------------------------------
    // Templates: boundary cases
    // ---------------------------------------------------------------------
    it('templateSidesPartitionBoundaryAndReservedAreasAreInBounds', 0, () => {
      const sides: Side[] = ['left', 'top', 'right', 'bottom'];
      const templates = listTemplates();
      for (let i = 0; i < templates.length; i++) {
        const template = templates[i];
        expect(template.wallSides.length + template.openSides.length).assertEqual(4);
        for (let j = 0; j < sides.length; j++) {
          const wallCount = countSide(template.wallSides, sides[j]);
          const openCount = countSide(template.openSides, sides[j]);
          expect(wallCount + openCount).assertEqual(1);
        }
        for (let j = 0; j < template.reservedAreas.length; j++) {
          const area = template.reservedAreas[j];
          expect(isFinitePositiveRect(area)).assertTrue();
          expect(isInsideTemplate(area, template)).assertTrue();
        }
        for (let j = 0; j < template.blockedAreas.length; j++) {
          const area = template.blockedAreas[j];
          expect(isFinitePositiveRect(area)).assertTrue();
          expect(isInsideTemplate(area, template)).assertTrue();
        }
      }
    });

    // ---------------------------------------------------------------------
    // Templates: error cases
    // ---------------------------------------------------------------------
    it('getTemplateByIdReturnsUndefinedForUnknownIds', 0, () => {
      expect(getTemplateById('unknown')).assertUndefined();
      expect(getTemplateById('')).assertUndefined();
      expect(getTemplateById('Standard')).assertUndefined();
      expect(getTemplateById('standard ')).assertUndefined();
      expect(getTemplateById('corner_600x400')).assertUndefined();
    });

    // ---------------------------------------------------------------------
    // Catalog: normal cases
    // ---------------------------------------------------------------------
    it('catalogContainsExactlyTenExpectedItems', 0, () => {
      const items = listCatalogItems();
      expect(EXPECTED_CATALOG.length).assertEqual(10);
      expect(items.length).assertEqual(10);
      for (let i = 0; i < EXPECTED_CATALOG.length; i++) {
        const expected = EXPECTED_CATALOG[i];
        const actual = items[i];
        expect(actual.id).assertEqual(expected.id);
        expect(actual.name).assertEqual(expected.name);
        expect(actual.category).assertEqual(expected.category);
        expect(actual.widthCm).assertEqual(expected.widthCm);
        expect(actual.heightCm).assertEqual(expected.heightCm);
        expect(actual.imageKey).assertEqual(expected.id);
      }
    });

    it('catalogItemIdsAreUniqueAndDimensionsFinitePositive', 0, () => {
      const items: CatalogItem[] = listCatalogItems();
      expect(items.length).assertEqual(10);
      for (let i = 0; i < items.length; i++) {
        expect(Number.isFinite(items[i].widthCm)).assertTrue();
        expect(Number.isFinite(items[i].heightCm)).assertTrue();
        expect(items[i].widthCm > 0).assertTrue();
        expect(items[i].heightCm > 0).assertTrue();
        for (let j = i + 1; j < items.length; j++) {
          expect(items[i].id !== items[j].id).assertTrue();
        }
      }
    });

    it('listCatalogItemsFiltersByExactCategory', 0, () => {
      const categories: string[] = ['服务', '展示', '互动', '家具', '导视', '装饰'];
      const expectedCounts: number[] = [1, 3, 1, 2, 2, 1];
      let total = 0;
      for (let i = 0; i < categories.length; i++) {
        const filtered = listCatalogItems(categories[i]);
        expect(filtered.length).assertEqual(expectedCounts[i]);
        total += filtered.length;
        for (let j = 0; j < filtered.length; j++) {
          expect(filtered[j].category).assertEqual(categories[i]);
        }
      }
      expect(total).assertEqual(10);
    });

    // ---------------------------------------------------------------------
    // Catalog: boundary and error cases
    // ---------------------------------------------------------------------
    it('listCatalogItemsHandlesUndefinedUnknownAndEmptyCategory', 0, () => {
      expect(listCatalogItems().length).assertEqual(10);
      expect(listCatalogItems(undefined).length).assertEqual(10);
      expect(listCatalogItems('').length).assertEqual(0);
      expect(listCatalogItems('不存在').length).assertEqual(0);
      expect(listCatalogItems('展示 ').length).assertEqual(0);
    });

    it('getCatalogItemByIdReturnsUndefinedForUnknownIds', 0, () => {
      expect(getCatalogItemById('unknown')).assertUndefined();
      expect(getCatalogItemById('')).assertUndefined();
      expect(getCatalogItemById('RECEPTION')).assertUndefined();
      expect(getCatalogItemById('display table')).assertUndefined();
      expect(getCatalogItemById('reception ')).assertUndefined();
    });

    // ---------------------------------------------------------------------
    // Copy isolation
    // ---------------------------------------------------------------------
    it('templateResultsAreIndependentDeepCopies', 0, () => {
      const first = listTemplates();
      const standard = first[0];
      standard.reservedAreas[0].x = -1;
      standard.reservedAreas.push({ x: 0, y: 0, width: 1, height: 1 });
      standard.wallSides.push('bottom');
      standard.blockedAreas.push({ x: 0, y: 0, width: 10, height: 10 });

      const second = listTemplates();
      expect(first !== second).assertTrue();
      expect(second[0].reservedAreas.length).assertEqual(1);
      expect(second[0].reservedAreas[0].x).assertEqual(240);
      expect(second[0].wallSides.length).assertEqual(3);
      expect(second[0].blockedAreas.length).assertEqual(0);

      const corner = getTemplateById('corner');
      if (corner !== undefined) {
        corner.reservedAreas[1].height = 1;
        corner.openSides.push('left');
      }
      const cornerAgain = getTemplateById('corner');
      expect(cornerAgain !== undefined).assertTrue();
      if (cornerAgain !== undefined) {
        expect(cornerAgain.reservedAreas[1].height).assertEqual(120);
        expect(cornerAgain.openSides.length).assertEqual(2);
      }
    });

    it('catalogResultsAreIndependentCopies', 0, () => {
      const items = listCatalogItems();
      items[0].widthCm = 999;
      items[0].name = 'mutated';
      items.push({
        id: 'mutated',
        name: 'mutated',
        category: 'mutated',
        widthCm: 1,
        heightCm: 1,
        imageKey: 'mutated'
      });

      const fresh = listCatalogItems();
      expect(fresh.length).assertEqual(10);
      expect(fresh[0].widthCm).assertEqual(140);
      expect(fresh[0].name).assertEqual('接待台');
      expect(getCatalogItemById('mutated')).assertUndefined();

      const display = listCatalogItems('展示');
      display[0].widthCm = 1;
      const displayAgain = listCatalogItems('展示');
      expect(displayAgain[0].widthCm).assertEqual(120);
    });
  });
}
