/**
 * Built-in object catalog (M1-B01).
 *
 * Pure data and lookup functions only: no UI, storage, or plan state.
 * widthCm/heightCm are the unrotated footprint in centimetres. imageKey is a
 * stable reference and uses the catalog id; no image asset is required in M1.
 */

import { CatalogItem } from '../model/BoothModels';

const CATALOG_ITEMS: CatalogItem[] = [
  {
    id: 'reception',
    name: '接待台',
    category: '服务',
    widthCm: 140,
    heightCm: 60,
    imageKey: 'reception'
  },
  {
    id: 'display_table',
    name: '展示桌',
    category: '展示',
    widthCm: 120,
    heightCm: 60,
    imageKey: 'display_table'
  },
  {
    id: 'shelf',
    name: '作品展架',
    category: '展示',
    widthCm: 100,
    heightCm: 40,
    imageKey: 'shelf'
  },
  {
    id: 'interactive_screen',
    name: '互动屏',
    category: '互动',
    widthCm: 100,
    heightCm: 40,
    imageKey: 'interactive_screen'
  },
  {
    id: 'chair',
    name: '座椅',
    category: '家具',
    widthCm: 50,
    heightCm: 50,
    imageKey: 'chair'
  },
  {
    id: 'storage',
    name: '储物柜',
    category: '家具',
    widthCm: 90,
    heightCm: 50,
    imageKey: 'storage'
  },
  {
    id: 'sign',
    name: '导视牌',
    category: '导视',
    widthCm: 60,
    heightCm: 40,
    imageKey: 'sign'
  },
  {
    id: 'plant',
    name: '绿植',
    category: '装饰',
    widthCm: 60,
    heightCm: 60,
    imageKey: 'plant'
  },
  {
    id: 'plinth',
    name: '展品台',
    category: '展示',
    widthCm: 80,
    heightCm: 80,
    imageKey: 'plinth'
  },
  {
    id: 'rollup',
    name: '立式海报架',
    category: '导视',
    widthCm: 80,
    heightCm: 30,
    imageKey: 'rollup'
  }
];

function cloneCatalogItem(item: CatalogItem): CatalogItem {
  return {
    id: item.id,
    name: item.name,
    category: item.category,
    widthCm: item.widthCm,
    heightCm: item.heightCm,
    imageKey: item.imageKey
  };
}

/**
 * Returns catalog items, optionally filtered by an exact category match.
 * Omitting the category returns all items; an empty or unknown category
 * returns an empty array. Each call returns independent item copies.
 */
export function listCatalogItems(category?: string): CatalogItem[] {
  const result: CatalogItem[] = [];
  for (let i = 0; i < CATALOG_ITEMS.length; i++) {
    const item = CATALOG_ITEMS[i];
    if (category === undefined || item.category === category) {
      result.push(cloneCatalogItem(item));
    }
  }
  return result;
}

/**
 * Returns a copy of the catalog item with the given id, or undefined when no
 * item matches. There is no fallback item for unknown ids.
 */
export function getCatalogItemById(id: string): CatalogItem | undefined {
  for (let i = 0; i < CATALOG_ITEMS.length; i++) {
    if (CATALOG_ITEMS[i].id === id) {
      return cloneCatalogItem(CATALOG_ITEMS[i]);
    }
  }
  return undefined;
}
