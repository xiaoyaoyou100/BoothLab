/**
 * Pure plan/store validation and cloning for BoothLab M2-B.
 *
 * The functions here do not touch storage or UI. They validate runtime values,
 * not only TypeScript declarations: data that came from JSON is checked for
 * arrays, primitive types, finite numbers, known catalog/template ids, legal
 * rotations and template geometry before it can become committed state.
 *
 * Invariants:
 * - schemaVersion is exactly 1.
 * - Plan names are trimmed UTF-16 strings of length 1..30.
 * - Plan ids are unique across the store; object ids are unique within a plan.
 * - createdAt/updatedAt are finite and updatedAt >= createdAt.
 * - Objects reference a known catalog item, have finite centre/zIndex values,
 *   a legal rotation and a footprint inside the template that does not overlap
 *   a blocked area. Object/object overlap and reserved-area overlap are allowed
 *   (they are warnings, not hard errors).
 */

import {
  BoothPlan,
  BoothTemplate,
  CatalogItem,
  OperationCode,
  OperationResult,
  PlanStore,
  PlacedObject,
  Rect
} from '../model/BoothModels';
import { getTemplateById } from '../catalog/BoothTemplates';
import { getCatalogItemById } from '../catalog/ObjectCatalogData';
import {
  getFootprintRect,
  isWithinBounds,
  isValidRotation,
  overlapsPositive
} from '../engine/GeometryEngine';

/** Persisted data-format version. Unknown versions must never be overwritten. */
export const PLAN_SCHEMA_VERSION: number = 1;
/** Maximum plan-name length in UTF-16 code units. */
export const MAX_PLAN_NAME_LENGTH: number = 30;

export function okResult<T>(message: string, data: T): OperationResult<T> {
  const result: OperationResult<T> = {
    code: 'OK',
    message: message,
    data: data
  };
  return result;
}

export function errorResult<T>(code: OperationCode, message: string): OperationResult<T> {
  const result: OperationResult<T> = {
    code: code,
    message: message
  };
  return result;
}

export function clonePlacedObject(object: PlacedObject): PlacedObject {
  const copy: PlacedObject = {
    id: object.id,
    catalogId: object.catalogId,
    centerX: object.centerX,
    centerY: object.centerY,
    rotation: object.rotation,
    zIndex: object.zIndex
  };
  return copy;
}

export function cloneObjects(objects: PlacedObject[]): PlacedObject[] {
  const copy: PlacedObject[] = [];
  for (let i = 0; i < objects.length; i++) {
    copy.push(clonePlacedObject(objects[i]));
  }
  return copy;
}

/**
 * Returns a deep copy of a plan containing only the five persisted fields and
 * the five placed-object fields. Session data such as previews is never copied.
 * The source is expected to be array-shaped; malformed objects arrays are
 * treated as empty so callers cannot crash while cloning untrusted data.
 */
export function clonePlan(plan: BoothPlan): BoothPlan {
  const sourceObjects: PlacedObject[] = Array.isArray(plan.objects) ? plan.objects : [];
  const copy: BoothPlan = {
    id: plan.id,
    name: plan.name,
    templateId: plan.templateId,
    objects: cloneObjects(sourceObjects),
    createdAt: plan.createdAt,
    updatedAt: plan.updatedAt
  };
  return copy;
}

/** Returns a deep, independent copy of a store. */
export function cloneStore(store: PlanStore): PlanStore {
  const sourcePlans: BoothPlan[] = Array.isArray(store.plans) ? store.plans : [];
  const plans: BoothPlan[] = [];
  for (let i = 0; i < sourcePlans.length; i++) {
    plans.push(clonePlan(sourcePlans[i]));
  }
  const copy: PlanStore = {
    schemaVersion: store.schemaVersion,
    plans: plans,
    activePlanId: store.activePlanId
  };
  return copy;
}

function isRuntimeObject(value: Object): boolean {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function containsString(values: string[], value: string): boolean {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === value) {
      return true;
    }
  }
  return false;
}

function validatePlanIdentity(plan: BoothPlan): OperationResult<BoothPlan> | null {
  if (!isRuntimeObject(plan)) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案必须是对象。');
  }
  if (typeof plan.id !== 'string' || plan.id.trim().length === 0) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案 id 必须是非空字符串。');
  }
  if (typeof plan.name !== 'string') {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案名称必须是字符串。');
  }
  if (plan.name !== plan.name.trim()) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案名称不能包含首尾空白。');
  }
  if (plan.name.length < 1 || plan.name.length > MAX_PLAN_NAME_LENGTH) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT',
      '展位方案名称长度必须为 1 到 ' + MAX_PLAN_NAME_LENGTH + ' 个字符。');
  }
  if (typeof plan.templateId !== 'string') {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位模板 id 必须是字符串。');
  }
  const template: BoothTemplate | undefined = getTemplateById(plan.templateId);
  if (template === undefined) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '未知的展位模板：' + plan.templateId + '。');
  }
  if (!Number.isFinite(plan.createdAt) || !Number.isFinite(plan.updatedAt)) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案时间戳必须是有限数字。');
  }
  if (plan.createdAt < 0 || plan.updatedAt < plan.createdAt) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案时间顺序无效。');
  }
  if (!Array.isArray(plan.objects)) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位方案物件列表必须是数组。');
  }
  return null;
}

function validatePlanObjects(plan: BoothPlan): OperationResult<BoothPlan> | null {
  const template: BoothTemplate | undefined = getTemplateById(plan.templateId);
  if (template === undefined) {
    return errorResult<BoothPlan>('INVALID_ARGUMENT', '未知的展位模板：' + plan.templateId + '。');
  }

  const objectIds: string[] = [];
  for (let i = 0; i < plan.objects.length; i++) {
    const object: PlacedObject = plan.objects[i];
    if (!isRuntimeObject(object)) {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位物件必须是对象。');
    }
    if (typeof object.id !== 'string' || object.id.trim().length === 0) {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位物件 id 必须是非空字符串。');
    }
    if (containsString(objectIds, object.id)) {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '同一展位方案内物件 id 必须唯一。');
    }
    objectIds.push(object.id);

    if (typeof object.catalogId !== 'string') {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位物件的 catalogId 必须是字符串。');
    }
    const catalog: CatalogItem | undefined = getCatalogItemById(object.catalogId);
    if (catalog === undefined) {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '未知的目录物件：' + object.catalogId + '。');
    }
    if (!Number.isFinite(object.centerX) || !Number.isFinite(object.centerY)) {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位物件中心坐标必须是有限数字。');
    }
    if (!Number.isFinite(object.zIndex)) {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位物件 zIndex 必须是有限数字。');
    }
    if (!isValidRotation(object.rotation)) {
      return errorResult<BoothPlan>('INVALID_ARGUMENT', '展位物件旋转角度必须是 0、90、180 或 270。');
    }

    const footprintResult: OperationResult<Rect> = getFootprintRect(object, catalog);
    if (footprintResult.code !== 'OK' || footprintResult.data === undefined) {
      return errorResult<BoothPlan>(footprintResult.code, footprintResult.message);
    }
    const footprint: Rect = footprintResult.data;
    if (!isWithinBounds(footprint, template.widthCm, template.heightCm)) {
      return errorResult<BoothPlan>('OUT_OF_BOUNDS', '物件占位超出展位边界。');
    }
    for (let b = 0; b < template.blockedAreas.length; b++) {
      if (overlapsPositive(footprint, template.blockedAreas[b])) {
        return errorResult<BoothPlan>('OUT_OF_BOUNDS', '物件占位与展位禁放区域重叠。');
      }
    }
    // Reserved areas and object/object overlap are warnings only and remain savable.
  }
  return null;
}

/**
 * Validates a runtime plan value and returns an independent clone on success.
 * The clone contains only persisted fields; extra session fields are dropped.
 */
export function validatePlan(plan: BoothPlan): OperationResult<BoothPlan> {
  const identityError: OperationResult<BoothPlan> | null = validatePlanIdentity(plan);
  if (identityError !== null) {
    return identityError;
  }
  const objectError: OperationResult<BoothPlan> | null = validatePlanObjects(plan);
  if (objectError !== null) {
    return objectError;
  }
  return okResult<BoothPlan>('展位方案有效。', clonePlan(plan));
}

/**
 * Validates a runtime store value and returns an independent clone on success.
 * Unknown schema versions are reported as UNSUPPORTED_SCHEMA, never repaired
 * or silently downgraded. activePlanId must be null or reference an existing plan.
 */
export function validateStore(store: PlanStore): OperationResult<PlanStore> {
  if (!isRuntimeObject(store)) {
    return errorResult<PlanStore>('INVALID_ARGUMENT', '方案库必须是对象。');
  }
  if (typeof store.schemaVersion !== 'number') {
    return errorResult<PlanStore>('CORRUPTED_DATA', 'schemaVersion 必须是数字。');
  }
  if (store.schemaVersion !== PLAN_SCHEMA_VERSION) {
    return errorResult<PlanStore>('UNSUPPORTED_SCHEMA',
      '不支持的方案库版本：' + store.schemaVersion.toString() + '。');
  }
  if (!Array.isArray(store.plans)) {
    return errorResult<PlanStore>('INVALID_ARGUMENT', '方案库 plans 必须是数组。');
  }
  if (store.activePlanId !== null && typeof store.activePlanId !== 'string') {
    return errorResult<PlanStore>('INVALID_ARGUMENT', 'activePlanId 必须是字符串或 null。');
  }

  const planIds: string[] = [];
  for (let i = 0; i < store.plans.length; i++) {
    const plan: BoothPlan = store.plans[i];
    const planResult: OperationResult<BoothPlan> = validatePlan(plan);
    if (planResult.code !== 'OK' || planResult.data === undefined) {
      return errorResult<PlanStore>(planResult.code, planResult.message);
    }
    if (containsString(planIds, plan.id)) {
      return errorResult<PlanStore>('INVALID_ARGUMENT', '方案库内展位方案 id 必须唯一。');
    }
    planIds.push(plan.id);
  }

  if (store.activePlanId !== null) {
    if (store.activePlanId.length === 0) {
      return errorResult<PlanStore>('INVALID_ARGUMENT', 'activePlanId 不能是空字符串。');
    }
    let activeFound: boolean = false;
    for (let i = 0; i < planIds.length; i++) {
      if (planIds[i] === store.activePlanId) {
        activeFound = true;
        break;
      }
    }
    if (!activeFound) {
      return errorResult<PlanStore>('INVALID_ARGUMENT', 'activePlanId 必须引用方案库中已有的方案。');
    }
  }

  return okResult<PlanStore>('方案库有效。', cloneStore(store));
}
