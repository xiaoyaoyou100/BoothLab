/**
 * PlanStore JSON serialization for BoothLab M2-B.
 *
 * The wire format is schemaVersion 1 and contains only persisted data:
 *   { schemaVersion, plans: [{ id, name, templateId, objects, createdAt,
 *     updatedAt }], activePlanId }
 * Every placed object is serialized with exactly id/catalogId/centerX/centerY/
 * rotation/zIndex. Session fields (preview pixels, history, viewport, selection)
 * are never written.
 *
 * Parsing is defensive: malformed JSON, JSON null, primitives, arrays, missing
 * fields and invalid plan/store contents all return CORRUPTED_DATA rather than
 * throwing. A numeric schemaVersion other than 1 returns UNSUPPORTED_SCHEMA so
 * callers can protect newer data from being overwritten.
 */

import {
  BoothPlan,
  OperationResult,
  PlanStore,
  PlacedObject,
  Rotation
} from '../model/BoothModels';
import {
  errorResult,
  okResult,
  PLAN_SCHEMA_VERSION,
  validatePlan,
  validateStore
} from './PlanValidator';

interface SerializedObject {
  id: string;
  catalogId: string;
  centerX: number;
  centerY: number;
  rotation: number;
  zIndex: number;
}

interface SerializedPlan {
  id: string;
  name: string;
  templateId: string;
  objects: SerializedObject[];
  createdAt: number;
  updatedAt: number;
}

interface SerializedStore {
  schemaVersion: number;
  plans: SerializedPlan[];
  activePlanId: string | null;
}

function asRawRecord(value: Object): Record<string, Object> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, Object>;
}

function readString(record: Record<string, Object>, key: string): string | null {
  const value: Object = record[key];
  if (typeof value === 'string') {
    return value;
  }
  return null;
}

function readFiniteNumber(record: Record<string, Object>, key: string): number | null {
  const value: Object = record[key];
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function readArray(record: Record<string, Object>, key: string): Object[] | null {
  const value: Object = record[key];
  if (!Array.isArray(value)) {
    return null;
  }
  return value as Object[];
}

function readRotation(value: number): Rotation | null {
  if (value === 0) {
    return 0;
  }
  if (value === 90) {
    return 90;
  }
  if (value === 180) {
    return 180;
  }
  if (value === 270) {
    return 270;
  }
  return null;
}

function parseObjectValue(value: Object): OperationResult<PlacedObject> {
  const record: Record<string, Object> | null = asRawRecord(value);
  if (record === null) {
    return errorResult<PlacedObject>('CORRUPTED_DATA', '物件数据必须是对象。');
  }
  const id: string | null = readString(record, 'id');
  const catalogId: string | null = readString(record, 'catalogId');
  const centerX: number | null = readFiniteNumber(record, 'centerX');
  const centerY: number | null = readFiniteNumber(record, 'centerY');
  const rotationNumber: number | null = readFiniteNumber(record, 'rotation');
  const zIndex: number | null = readFiniteNumber(record, 'zIndex');
  if (id === null || catalogId === null || centerX === null || centerY === null ||
    rotationNumber === null || zIndex === null) {
    return errorResult<PlacedObject>('CORRUPTED_DATA', '物件数据字段缺失或类型错误。');
  }
  const rotation: Rotation | null = readRotation(rotationNumber);
  if (rotation === null) {
    return errorResult<PlacedObject>('CORRUPTED_DATA', '物件旋转角度无效。');
  }
  const object: PlacedObject = {
    id: id,
    catalogId: catalogId,
    centerX: centerX,
    centerY: centerY,
    rotation: rotation,
    zIndex: zIndex
  };
  return okResult<PlacedObject>('物件数据解析成功。', object);
}

function parsePlanValue(value: Object): OperationResult<BoothPlan> {
  const record: Record<string, Object> | null = asRawRecord(value);
  if (record === null) {
    return errorResult<BoothPlan>('CORRUPTED_DATA', '展位方案数据必须是对象。');
  }
  const id: string | null = readString(record, 'id');
  const name: string | null = readString(record, 'name');
  const templateId: string | null = readString(record, 'templateId');
  const createdAt: number | null = readFiniteNumber(record, 'createdAt');
  const updatedAt: number | null = readFiniteNumber(record, 'updatedAt');
  const rawObjects: Object[] | null = readArray(record, 'objects');
  if (id === null || name === null || templateId === null ||
    createdAt === null || updatedAt === null || rawObjects === null) {
    return errorResult<BoothPlan>('CORRUPTED_DATA', '展位方案数据字段缺失或类型错误。');
  }

  const objects: PlacedObject[] = [];
  for (let i = 0; i < rawObjects.length; i++) {
    const objectResult: OperationResult<PlacedObject> = parseObjectValue(rawObjects[i]);
    if (objectResult.code !== 'OK' || objectResult.data === undefined) {
      return errorResult<BoothPlan>('CORRUPTED_DATA', objectResult.message);
    }
    objects.push(objectResult.data);
  }

  const plan: BoothPlan = {
    id: id,
    name: name,
    templateId: templateId,
    objects: objects,
    createdAt: createdAt,
    updatedAt: updatedAt
  };
  const validation: OperationResult<BoothPlan> = validatePlan(plan);
  if (validation.code !== 'OK' || validation.data === undefined) {
    return errorResult<BoothPlan>('CORRUPTED_DATA', validation.message);
  }
  return okResult<BoothPlan>('展位方案数据解析成功。', validation.data);
}

/**
 * Serializes a validated store to compact JSON. Invalid stores are rejected
 * with the validator's code (INVALID_ARGUMENT / OUT_OF_BOUNDS /
 * UNSUPPORTED_SCHEMA) and no text is produced.
 */
export function serializeStore(store: PlanStore): OperationResult<string> {
  const validation: OperationResult<PlanStore> = validateStore(store);
  if (validation.code !== 'OK' || validation.data === undefined) {
    return errorResult<string>(validation.code, validation.message);
  }
  const validStore: PlanStore = validation.data;

  const plans: SerializedPlan[] = [];
  for (let i = 0; i < validStore.plans.length; i++) {
    const plan: BoothPlan = validStore.plans[i];
    const objects: SerializedObject[] = [];
    for (let j = 0; j < plan.objects.length; j++) {
      const object: PlacedObject = plan.objects[j];
      const serializedObject: SerializedObject = {
        id: object.id,
        catalogId: object.catalogId,
        centerX: object.centerX,
        centerY: object.centerY,
        rotation: object.rotation,
        zIndex: object.zIndex
      };
      objects.push(serializedObject);
    }
    const serializedPlan: SerializedPlan = {
      id: plan.id,
      name: plan.name,
      templateId: plan.templateId,
      objects: objects,
      createdAt: plan.createdAt,
      updatedAt: plan.updatedAt
    };
    plans.push(serializedPlan);
  }

  const serializedStore: SerializedStore = {
    schemaVersion: PLAN_SCHEMA_VERSION,
    plans: plans,
    activePlanId: validStore.activePlanId
  };

  try {
    const text: string = JSON.stringify(serializedStore);
    if (typeof text !== 'string' || text.length === 0) {
      return errorResult<string>('PERSISTENCE_ERROR', '方案库序列化结果为空。');
    }
    return okResult<string>('方案库序列化成功。', text);
  } catch (error) {
    return errorResult<string>('PERSISTENCE_ERROR', '方案库序列化失败。');
  }
}

/**
 * Parses and validates store JSON. Never throws for malformed input.
 * Unknown numeric schema versions are UNSUPPORTED_SCHEMA; everything else that
 * is not a valid schemaVersion-1 store is CORRUPTED_DATA.
 */
export function parseStore(text: string): OperationResult<PlanStore> {
  if (typeof text !== 'string') {
    return errorResult<PlanStore>('CORRUPTED_DATA', '方案库文本必须是字符串。');
  }
  const trimmed: string = text.trim();
  if (trimmed.length === 0 || trimmed === 'null') {
    return errorResult<PlanStore>('CORRUPTED_DATA', '方案库文本为空或为 null。');
  }

  let parsed: Object;
  try {
    parsed = JSON.parse(trimmed) as Object;
  } catch (error) {
    return errorResult<PlanStore>('CORRUPTED_DATA', '方案库 JSON 无法解析。');
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return errorResult<PlanStore>('CORRUPTED_DATA', '方案库根节点必须是对象。');
  }

  const record: Record<string, Object> | null = asRawRecord(parsed);
  if (record === null) {
    return errorResult<PlanStore>('CORRUPTED_DATA', '方案库根节点必须是对象。');
  }

  const schemaValue: Object = record['schemaVersion'];
  if (typeof schemaValue !== 'number') {
    return errorResult<PlanStore>('CORRUPTED_DATA', '方案库缺少有效的 schemaVersion。');
  }
  if (schemaValue !== PLAN_SCHEMA_VERSION) {
    return errorResult<PlanStore>('UNSUPPORTED_SCHEMA',
      '不支持的方案库版本：' + schemaValue.toString() + '。');
  }

  const rawPlans: Object[] | null = readArray(record, 'plans');
  if (rawPlans === null) {
    return errorResult<PlanStore>('CORRUPTED_DATA', '方案库 plans 必须是数组。');
  }

  const plans: BoothPlan[] = [];
  for (let i = 0; i < rawPlans.length; i++) {
    const planResult: OperationResult<BoothPlan> = parsePlanValue(rawPlans[i]);
    if (planResult.code !== 'OK' || planResult.data === undefined) {
      return errorResult<PlanStore>('CORRUPTED_DATA', planResult.message);
    }
    plans.push(planResult.data);
  }

  const activeRaw: Object = record['activePlanId'];
  let activePlanId: string | null = null;
  if (activeRaw === null) {
    activePlanId = null;
  } else if (typeof activeRaw === 'string') {
    activePlanId = activeRaw;
  } else {
    return errorResult<PlanStore>('CORRUPTED_DATA', 'activePlanId 必须是字符串或 null。');
  }

  const store: PlanStore = {
    schemaVersion: PLAN_SCHEMA_VERSION,
    plans: plans,
    activePlanId: activePlanId
  };
  const validation: OperationResult<PlanStore> = validateStore(store);
  if (validation.code !== 'OK' || validation.data === undefined) {
    return errorResult<PlanStore>('CORRUPTED_DATA', validation.message);
  }
  return okResult<PlanStore>('方案库解析成功。', validation.data);
}
