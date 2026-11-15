/**
 * BoothLab layout validator (M2-A02).
 *
 * Pure world-centimetre validation over a BoothTemplate and committed
 * PlacedObject list. This module has no controller, history, persistence or UI
 * dependency, so it can be called from the editor getter and from tests without
 * side effects.
 *
 * Issue meanings:
 * - OVERLAP: two object footprints share positive area. Edge contact is allowed.
 * - OUT_OF_BOUNDS: one object footprint leaves the booth boundary.
 * - BLOCKED_AREA: one object occupies a hard-forbidden blocked area.
 * - ENTRY_OCCUPIED: one object occupies a reserved reminder area. This is a
 *   teaching warning only; it is not a fire/safety conclusion.
 * - INVALID_ARGUMENT: malformed template/object data was found. Invalid data
 *   always produces an explicit issue instead of being silently ignored.
 *
 * Every object pair is inspected at most once and issues are deduplicated with
 * stable logical keys. Objects with malformed identifiers or geometry do not
 * take part in pair checks because their footprints cannot be trusted, but the
 * explicit INVALID_ARGUMENT issue keeps the layout from looking valid.
 */

import {
  BoothTemplate,
  CatalogItem,
  LayoutIssue,
  OperationCode,
  OperationResult,
  PlacedObject,
  Rect
} from '../model/BoothModels';
import { getCatalogItemById } from '../catalog/ObjectCatalogData';
import {
  getFootprintRect,
  isWithinBounds,
  isValidRect,
  overlapsPositive
} from './GeometryEngine';

export const LAYOUT_CODE_OVERLAP: string = 'OVERLAP';
export const LAYOUT_CODE_OUT_OF_BOUNDS: string = 'OUT_OF_BOUNDS';
export const LAYOUT_CODE_BLOCKED_AREA: string = 'BLOCKED_AREA';
export const LAYOUT_CODE_ENTRY_OCCUPIED: string = 'ENTRY_OCCUPIED';
export const LAYOUT_CODE_INVALID_ARGUMENT: string = 'INVALID_ARGUMENT';

export const LAYOUT_SEVERITY_ERROR: string = 'error';
export const LAYOUT_SEVERITY_WARNING: string = 'warning';

/** A trusted footprint together with the object id used in pair issues. */
interface ValidFootprint {
  id: string;
  rect: Rect;
}

function failure<T>(code: OperationCode, message: string): OperationResult<T> {
  const result: OperationResult<T> = {
    code: code,
    message: message
  };
  return result;
}

/**
 * Adds one issue unless the same logical issue key was already produced.
 * keySuffix distinguishes repeated checks (for example the same object against
 * several template rectangles) without changing the public objectIds payload.
 */
function addIssue(issues: LayoutIssue[], keys: string[], code: string, severity: string,
  message: string, objectIds: string[], keySuffix: string): void {
  let idKey: string = '';
  for (let i = 0; i < objectIds.length; i++) {
    idKey += objectIds[i] + ',';
  }
  const key: string = code + '|' + idKey + '|' + keySuffix;
  if (keys.indexOf(key) >= 0) {
    return;
  }
  keys.push(key);
  const ids: string[] = [];
  for (let i = 0; i < objectIds.length; i++) {
    ids.push(objectIds[i]);
  }
  const issue: LayoutIssue = {
    code: code,
    severity: severity,
    message: message,
    objectIds: ids
  };
  issues.push(issue);
}

/**
 * True when a single object may be committed on the template: its footprint is
 * valid, fully inside the booth and does not overlap any hard blocked area.
 * Reserved areas intentionally do not block placement; they are warnings from
 * validateLayout. Returns OUT_OF_BOUNDS for both boundary and blocked-area
 * violations so the controller keeps its existing hard-rejection code.
 */
export function canPlace(template: BoothTemplate, object: PlacedObject): OperationResult<boolean> {
  if (template === null || template === undefined) {
    return failure<boolean>('INVALID_ARGUMENT', 'Booth template is required.');
  }
  if (typeof template.widthCm !== 'number' || !Number.isFinite(template.widthCm) ||
    template.widthCm <= 0 || typeof template.heightCm !== 'number' ||
    !Number.isFinite(template.heightCm) || template.heightCm <= 0) {
    return failure<boolean>('INVALID_ARGUMENT',
      'Booth template dimensions must be finite and positive.');
  }
  if (!Array.isArray(template.blockedAreas)) {
    return failure<boolean>('INVALID_ARGUMENT', 'Booth template blocked areas are invalid.');
  }
  for (let i = 0; i < template.blockedAreas.length; i++) {
    const area: Rect = template.blockedAreas[i];
    // Guard null/undefined before isValidRect reads its components; malformed
    // template data must be an explicit rejection, never a thrown exception.
    if (area === null || area === undefined || !isValidRect(area)) {
      return failure<boolean>('INVALID_ARGUMENT',
        'Booth template blocked area is not a valid rectangle.');
    }
  }
  if (object === null || object === undefined) {
    return failure<boolean>('INVALID_ARGUMENT', 'Placed object is required.');
  }
  // The controller uses an empty id only as the pre-allocation placeholder in
  // addObject; any whitespace-only non-empty id is malformed input.
  if (typeof object.id !== 'string' ||
    (object.id.length > 0 && object.id.trim().length === 0)) {
    return failure<boolean>('INVALID_ARGUMENT',
      'Placed object id must be a non-blank string.');
  }
  if (typeof object.centerX !== 'number' || !Number.isFinite(object.centerX) ||
    typeof object.centerY !== 'number' || !Number.isFinite(object.centerY)) {
    return failure<boolean>('INVALID_ARGUMENT', 'Placed object centre must be finite.');
  }
  if (typeof object.rotation !== 'number') {
    return failure<boolean>('INVALID_ARGUMENT',
      'Placed object rotation must be 0, 90, 180 or 270 degrees.');
  }
  if (!Number.isFinite(object.zIndex)) {
    return failure<boolean>('INVALID_ARGUMENT',
      'Placed object zIndex must be finite.');
  }
  if (typeof object.catalogId !== 'string') {
    return failure<boolean>('INVALID_ARGUMENT', 'Placed object catalog id must be a string.');
  }
  const catalog: CatalogItem | undefined = getCatalogItemById(object.catalogId);
  if (catalog === undefined) {
    return failure<boolean>('INVALID_ARGUMENT',
      'Placed object references an unknown catalog id: ' + object.catalogId);
  }
  const footprint: OperationResult<Rect> = getFootprintRect(object, catalog);
  if (footprint.code !== 'OK' || footprint.data === undefined) {
    return failure<boolean>(footprint.code, footprint.message);
  }
  if (!isWithinBounds(footprint.data, template.widthCm, template.heightCm)) {
    return failure<boolean>('OUT_OF_BOUNDS',
      'The object footprint would leave the booth bounds.');
  }
  for (let i = 0; i < template.blockedAreas.length; i++) {
    if (overlapsPositive(footprint.data, template.blockedAreas[i])) {
      return failure<boolean>('OUT_OF_BOUNDS',
        'The object footprint would occupy a blocked area.');
    }
  }
  const allowed: OperationResult<boolean> = {
    code: 'OK',
    message: 'Placement is allowed.',
    data: true
  };
  return allowed;
}

/**
 * Validates every committed object and reserved/blocked template interaction.
 * The input arrays and objects are only read, never mutated. Malformed data is
 * reported as INVALID_ARGUMENT instead of throwing.
 */
export function validateLayout(template: BoothTemplate, objects: PlacedObject[]): LayoutIssue[] {
  const issues: LayoutIssue[] = [];
  const keys: string[] = [];

  if (template === null || template === undefined) {
    addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
      '展位模板数据为空，无法检查布局。', [], 'template-null');
    return issues;
  }

  let dimensionsValid: boolean = true;
  if (typeof template.widthCm !== 'number' || !Number.isFinite(template.widthCm) ||
    template.widthCm <= 0 || typeof template.heightCm !== 'number' ||
    !Number.isFinite(template.heightCm) || template.heightCm <= 0) {
    dimensionsValid = false;
    addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
      '展位模板宽高无效（必须为有限正数），无法可靠检查边界。', [], 'template-size');
  }

  const blockedAreas: Rect[] = [];
  if (!Array.isArray(template.blockedAreas)) {
    addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
      '展位模板禁放区数据无效。', [], 'template-blocked-list');
  } else {
    for (let i = 0; i < template.blockedAreas.length; i++) {
      const area: Rect = template.blockedAreas[i];
      if (area === null || area === undefined || !isValidRect(area)) {
        addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
          '展位模板第 ' + (i + 1) + ' 个禁放区矩形无效，已跳过该区域。', [],
          'template-blocked-' + i);
      } else {
        blockedAreas.push(area);
      }
    }
  }

  const reservedAreas: Rect[] = [];
  if (!Array.isArray(template.reservedAreas)) {
    addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
      '展位模板预留区数据无效。', [], 'template-reserved-list');
  } else {
    for (let i = 0; i < template.reservedAreas.length; i++) {
      const area: Rect = template.reservedAreas[i];
      if (area === null || area === undefined || !isValidRect(area)) {
        addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
          '展位模板第 ' + (i + 1) + ' 个预留区矩形无效，已跳过该区域。', [],
          'template-reserved-' + i);
      } else {
        reservedAreas.push(area);
      }
    }
  }

  if (!Array.isArray(objects)) {
    addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
      '物件列表数据无效，无法进行布局校验。', [], 'objects-list');
    return issues;
  }

  const seenIds: string[] = [];
  const validFootprints: ValidFootprint[] = [];

  for (let i = 0; i < objects.length; i++) {
    const raw: PlacedObject = objects[i];
    if (raw === null || raw === undefined) {
      addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
        '第 ' + (i + 1) + ' 个物件数据为空，已跳过。', [], 'object-null-' + i);
      continue;
    }
    if (typeof raw.id !== 'string' || raw.id.trim().length === 0) {
      addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
        '第 ' + (i + 1) + ' 个物件缺少有效编号，已跳过。', [], 'object-id-' + i);
      continue;
    }
    if (seenIds.indexOf(raw.id) >= 0) {
      addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
        '物件编号「' + raw.id + '」重复，请先修正编号。', [raw.id], 'duplicate-id');
      continue;
    }
    seenIds.push(raw.id);

    if (!Number.isFinite(raw.zIndex)) {
      addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
        '物件「' + raw.id + '」的 zIndex 无效（必须为有限数）。', [raw.id], 'zindex');
      continue;
    }

    if (typeof raw.catalogId !== 'string') {
      addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
        '物件「' + raw.id + '」目录编号无效。', [raw.id], 'catalog-type');
      continue;
    }
    const catalog: CatalogItem | undefined = getCatalogItemById(raw.catalogId);
    if (catalog === undefined) {
      addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
        '物件「' + raw.id + '」引用了未知目录项「' + raw.catalogId + '」。', [raw.id],
        'catalog-missing');
      continue;
    }

    const footprint: OperationResult<Rect> = getFootprintRect(raw, catalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      addIssue(issues, keys, LAYOUT_CODE_INVALID_ARGUMENT, LAYOUT_SEVERITY_ERROR,
        '物件「' + raw.id + '」的坐标或旋转无效：' + footprint.message, [raw.id],
        'footprint');
      continue;
    }

    if (dimensionsValid &&
      !isWithinBounds(footprint.data, template.widthCm, template.heightCm)) {
      addIssue(issues, keys, LAYOUT_CODE_OUT_OF_BOUNDS, LAYOUT_SEVERITY_ERROR,
        '物件「' + raw.id + '」超出展位边界，请移回展位内。', [raw.id], 'bounds');
    }

    let blockedHit: boolean = false;
    for (let j = 0; j < blockedAreas.length; j++) {
      if (overlapsPositive(footprint.data, blockedAreas[j])) {
        blockedHit = true;
        break;
      }
    }
    if (blockedHit) {
      addIssue(issues, keys, LAYOUT_CODE_BLOCKED_AREA, LAYOUT_SEVERITY_ERROR,
        '物件「' + raw.id + '」位于禁放区，必须移出该区域。', [raw.id], 'blocked');
    }

    let reservedHit: boolean = false;
    for (let j = 0; j < reservedAreas.length; j++) {
      if (overlapsPositive(footprint.data, reservedAreas[j])) {
        reservedHit = true;
        break;
      }
    }
    if (reservedHit) {
      addIssue(issues, keys, LAYOUT_CODE_ENTRY_OCCUPIED, LAYOUT_SEVERITY_WARNING,
        '物件「' + raw.id + '」占用提示性预留区，请确认该区域是否需保持空置。',
        [raw.id], 'reserved');
    }

    const valid: ValidFootprint = {
      id: raw.id,
      rect: footprint.data
    };
    validFootprints.push(valid);
  }

  // Every unordered pair is examined exactly once. Edge contact is not a
  // positive-area overlap, so it produces no issue.
  for (let i = 0; i < validFootprints.length; i++) {
    for (let j = i + 1; j < validFootprints.length; j++) {
      const first: ValidFootprint = validFootprints[i];
      const second: ValidFootprint = validFootprints[j];
      if (overlapsPositive(first.rect, second.rect)) {
        addIssue(issues, keys, LAYOUT_CODE_OVERLAP, LAYOUT_SEVERITY_WARNING,
          '物件「' + first.id + '」与「' + second.id + '」占位重叠，请调整间距。',
          [first.id, second.id], 'pair');
      }
    }
  }

  return issues;
}
