/**
 * BoothLab editor controller (M1-A01).
 *
 * Owns the committed placed-object list for one editor session. It uses the
 * frozen catalog modules for template/catalog lookups and delegates all
 * geometry to GeometryEngine.
 *
 * State rules:
 * - Committed objects change only on addObject, moveObject, rotateObject and a
 *   successful endDrag.
 * - beginDrag/updateDrag only create and move a preview clone; committed
 *   objects are untouched until endDrag.
 * - A drag that ends outside the booth is rejected with OUT_OF_BOUNDS and the
 *   previous committed centre is kept.
 * - Public getters return copies, never internal mutable references.
 *
 * M2-A01 adds a 50-operation undo/redo snapshot history and a formal BoothPlan
 * import/export path while keeping the M1 demo constructor and geometry
 * behaviour unchanged. M2-A02 adds a pure layout-issue getter and rejects
 * blocked-area placements for add/move/rotate/endDrag. Persistence and plan
 * repositories remain outside this file.
 */

import {
  BoothPlan,
  BoothTemplate,
  CatalogItem,
  LayoutIssue,
  OperationCode,
  OperationResult,
  PlacedObject,
  Point,
  Rect,
  Rotation,
  Side
} from '../model/BoothModels';
import { getCatalogItemById, listCatalogItems } from '../catalog/ObjectCatalogData';
import { getTemplateById } from '../catalog/BoothTemplates';
import {
  getFootprintRect,
  hitTestObjects,
  isWithinBounds,
  isValidRotation,
  overlapsPositive
} from './GeometryEngine';
import { canPlace, validateLayout } from './LayoutValidator';
import { cloneHistoryObjects, HistoryEntry, HistoryManager } from './HistoryManager';

const INITIAL_TEMPLATE_ID: string = 'standard';
const INITIAL_CATALOG_ID: string = 'display_table';
const INSTANCE_ID_PREFIX: string = 'obj-';

function isFiniteNumber(value: number): boolean {
  return Number.isFinite(value);
}

function isFinitePoint(point: Point): boolean {
  return isFiniteNumber(point.x) && isFiniteNumber(point.y);
}

function clonePlacedObject(object: PlacedObject): PlacedObject {
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

function clonePlacedObjects(objects: PlacedObject[]): PlacedObject[] {
  const copies: PlacedObject[] = [];
  for (let i = 0; i < objects.length; i++) {
    copies.push(clonePlacedObject(objects[i]));
  }
  return copies;
}

function cloneSideList(sides: Side[]): Side[] {
  const copies: Side[] = [];
  for (let i = 0; i < sides.length; i++) {
    copies.push(sides[i]);
  }
  return copies;
}

function cloneTemplate(template: BoothTemplate): BoothTemplate {
  const blocked: Rect[] = [];
  for (let i = 0; i < template.blockedAreas.length; i++) {
    const area: Rect = template.blockedAreas[i];
    blocked.push({ x: area.x, y: area.y, width: area.width, height: area.height });
  }
  const reserved: Rect[] = [];
  for (let i = 0; i < template.reservedAreas.length; i++) {
    const area: Rect = template.reservedAreas[i];
    reserved.push({ x: area.x, y: area.y, width: area.width, height: area.height });
  }
  const copy: BoothTemplate = {
    id: template.id,
    name: template.name,
    widthCm: template.widthCm,
    heightCm: template.heightCm,
    blockedAreas: blocked,
    reservedAreas: reserved,
    wallSides: cloneSideList(template.wallSides),
    openSides: cloneSideList(template.openSides)
  };
  return copy;
}

/**
 * Fully validated, isolated payload produced by importPlan validation. State is
 * only assigned after the whole payload passes, so a rejected plan cannot
 * partially mutate the controller.
 */
interface ValidatedPlanData {
  id: string;
  name: string;
  template: BoothTemplate;
  objects: PlacedObject[];
  createdAt: number;
  updatedAt: number;
}

const PLAN_NAME_MAX_LENGTH: number = 30;
/** Largest instance counter we may safely increment by one without precision loss. */
const MAX_SAFE_INSTANCE_NUMBER: number = 9007199254740991;
/** Numeric suffixes longer than this are not used to seed the allocator. */
const MAX_SEEDABLE_ID_SUFFIX_LENGTH: number = 15;

function nextRotation(rotation: Rotation): Rotation {
  if (rotation === 0) {
    return 90;
  }
  if (rotation === 90) {
    return 180;
  }
  if (rotation === 180) {
    return 270;
  }
  return 0;
}

export class EditorController {
  private template: BoothTemplate;
  private objects: PlacedObject[] = [];
  private selectedId: string | null = null;
  private preview: PlacedObject | null = null;
  private dragging: boolean = false;
  private dragOffsetX: number = 0;
  private dragOffsetY: number = 0;
  private nextInstanceNumber: number = 1;
  private history: HistoryManager = new HistoryManager();
  private planId: string | null = null;
  private planName: string = '';
  private planCreatedAt: number = 0;
  private planUpdatedAt: number = 0;
  /**
   * Monotonic revision of effective committed changes in this session. It is
   * the change-notification signal; updatedAt is only persisted metadata and
   * may be unable to advance at very large finite values.
   */
  private changeRevision: number = 0;

  /**
   * Creates a session for an existing template and seeds the M1 sample object:
   * a display_table at the template centre, rotation 0.
   * Unknown or invalid templates throw: there is no arbitrary fallback.
   */
  constructor(templateId: string = INITIAL_TEMPLATE_ID) {
    const template: BoothTemplate | undefined = getTemplateById(templateId);
    if (template === undefined) {
      throw new Error('Unknown booth template: ' + templateId);
    }
    if (!Number.isFinite(template.widthCm) || template.widthCm <= 0 ||
      !Number.isFinite(template.heightCm) || template.heightCm <= 0) {
      throw new Error('Booth template dimensions must be finite and positive.');
    }
    this.template = template;

    const initialCatalog: CatalogItem | undefined = getCatalogItemById(INITIAL_CATALOG_ID);
    if (initialCatalog === undefined) {
      throw new Error('Initial catalog item is missing: ' + INITIAL_CATALOG_ID);
    }
    const initial: PlacedObject = {
      id: INSTANCE_ID_PREFIX + this.nextInstanceNumber,
      catalogId: initialCatalog.id,
      centerX: this.template.widthCm / 2,
      centerY: this.template.heightCm / 2,
      rotation: 0,
      zIndex: 1
    };
    const footprint: OperationResult<Rect> = getFootprintRect(initial, initialCatalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      throw new Error('Initial object footprint is invalid: ' + footprint.message);
    }
    if (!isWithinBounds(footprint.data, this.template.widthCm, this.template.heightCm)) {
      throw new Error('Initial object is outside the booth bounds.');
    }
    this.objects.push(initial);
    this.nextInstanceNumber++;
  }

  // ------------------------------------------------------------------
  // Read-only snapshots
  // ------------------------------------------------------------------

  /** Returns a deep copy of the template used by this session. */
  getTemplate(): BoothTemplate {
    return cloneTemplate(this.template);
  }

  /** Returns deep copies of all committed objects. */
  getObjects(): PlacedObject[] {
    return clonePlacedObjects(this.objects);
  }

  /**
   * Computes layout issues from the current committed objects on every call.
   * Preview/selection state is never inspected, so the result cannot be stale
   * with respect to committed state. This getter changes nothing.
   */
  getLayoutIssues(): LayoutIssue[] {
    return validateLayout(this.template, this.objects);
  }

  getSelectedId(): string | null {
    return this.selectedId;
  }

  /** Returns a copy of the selected committed object, or null. */
  getSelectedObject(): PlacedObject | null {
    const selectedId: string | null = this.selectedId;
    if (selectedId === null) {
      return null;
    }
    const index: number = this.findObjectIndex(selectedId);
    if (index < 0) {
      return null;
    }
    return clonePlacedObject(this.objects[index]);
  }

  /** Returns a copy of the active drag preview, or null. Never committed. */
  getPreviewObject(): PlacedObject | null {
    const preview: PlacedObject | null = this.preview;
    if (preview === null) {
      return null;
    }
    return clonePlacedObject(preview);
  }

  isDragging(): boolean {
    return this.dragging;
  }

  /** Id of the currently imported formal plan, or null for the M1 demo. */
  getPlanId(): string | null {
    return this.planId;
  }

  /**
   * Monotonic revision for the current editing session. It advances exactly
   * once per effective committed operation (add/move/rotate/remove/endDrag,
   * undo, redo) and is reset by importPlan. A fresh import does not advance it.
   */
  getChangeRevision(): number {
    return this.changeRevision;
  }

  /** True when at least one effective operation can be undone. */
  canUndo(): boolean {
    return this.history.canUndo();
  }

  /** True when a previously undone operation can be redone. */
  canRedo(): boolean {
    return this.history.canRedo();
  }

  /** Looks up a catalog item through the frozen catalog module. */
  getCatalogItem(catalogId: string): OperationResult<CatalogItem> {
    if (catalogId === '') {
      return this.failure<CatalogItem>('NOT_FOUND', 'Catalog id is required.');
    }
    const item: CatalogItem | undefined = getCatalogItemById(catalogId);
    if (item === undefined) {
      return this.failure<CatalogItem>('NOT_FOUND', 'Unknown catalog id: ' + catalogId);
    }
    const result: OperationResult<CatalogItem> = {
      code: 'OK',
      message: 'Catalog item found.',
      data: item
    };
    return result;
  }

  /** Computes the current footprint of a committed/preview candidate copy. */
  getFootprint(object: PlacedObject): OperationResult<Rect> {
    const catalog: CatalogItem | undefined = getCatalogItemById(object.catalogId);
    if (catalog === undefined) {
      return this.failure<Rect>('NOT_FOUND', 'Object references an unknown catalog id.');
    }
    return getFootprintRect(object, catalog);
  }

  /** Topmost object under a world point. OK with null data means empty space. */
  hitTest(worldPoint: Point): OperationResult<string | null> {
    if (!isFinitePoint(worldPoint)) {
      return this.failure<string | null>('INVALID_ARGUMENT', 'World point must be finite.');
    }
    const catalogs: CatalogItem[] = listCatalogItems();
    return hitTestObjects(this.objects, catalogs, worldPoint);
  }

  // ------------------------------------------------------------------
  // Selection
  // ------------------------------------------------------------------

  /**
   * Selects one object or clears selection with null.
   * An unknown/empty id clears selection and returns NOT_FOUND.
   */
  selectObject(id: string | null): OperationResult<PlacedObject | null> {
    if (this.dragging) {
      return this.failure<PlacedObject | null>('INVALID_ARGUMENT',
        'Selection cannot change during a drag.');
    }
    if (id === null) {
      this.selectedId = null;
      const cleared: OperationResult<PlacedObject | null> = {
        code: 'OK',
        message: 'Selection cleared.',
        data: null
      };
      return cleared;
    }
    const index: number = this.findObjectIndex(id);
    if (index < 0) {
      this.selectedId = null;
      return this.failure<PlacedObject | null>('NOT_FOUND',
        'No placed object with id: ' + id + '. Selection cleared.');
    }
    this.selectedId = this.objects[index].id;
    const result: OperationResult<PlacedObject | null> = {
      code: 'OK',
      message: 'Object selected.',
      data: clonePlacedObject(this.objects[index])
    };
    return result;
  }

  // ------------------------------------------------------------------
  // Committed operations
  // ------------------------------------------------------------------

  /**
   * Adds a catalog object at a world centre. The object is committed only when
   * the catalog exists, the centre is finite and the full footprint is inside
   * the booth. Failed attempts do not consume an instance id.
   */
  addObject(catalogId: string, center: Point): OperationResult<PlacedObject> {
    if (this.dragging) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT',
        'Objects cannot be added during a drag.');
    }
    const catalog: CatalogItem | undefined = getCatalogItemById(catalogId);
    if (catalog === undefined) {
      return this.failure<PlacedObject>('NOT_FOUND', 'Unknown catalog id: ' + catalogId);
    }
    if (!isFinitePoint(center)) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'Centre coordinates must be finite.');
    }

    const candidate: PlacedObject = {
      id: '',
      catalogId: catalog.id,
      centerX: center.x,
      centerY: center.y,
      rotation: 0,
      zIndex: this.nextZIndex()
    };
    const placement: OperationResult<boolean> = canPlace(this.template, candidate);
    if (placement.code !== 'OK' || placement.data !== true) {
      return this.failure<PlacedObject>(placement.code, placement.message);
    }

    const before: PlacedObject[] = clonePlacedObjects(this.objects);
    candidate.id = this.allocateInstanceId();
    this.objects.push(candidate);
    this.recordEffectiveChange(before);
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Object added.',
      data: clonePlacedObject(candidate)
    };
    return result;
  }

  /** Moves a committed object to an absolute finite centre inside the booth. */
  moveObject(id: string, center: Point): OperationResult<PlacedObject> {
    if (this.dragging) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT',
        'Committed objects cannot move during a drag.');
    }
    const index: number = this.findObjectIndex(id);
    if (index < 0) {
      return this.failure<PlacedObject>('NOT_FOUND', 'No placed object with id: ' + id);
    }
    if (!isFinitePoint(center)) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'Centre coordinates must be finite.');
    }

    const candidate: PlacedObject = clonePlacedObject(this.objects[index]);
    candidate.centerX = center.x;
    candidate.centerY = center.y;
    const catalog: CatalogItem | undefined = getCatalogItemById(candidate.catalogId);
    if (catalog === undefined) {
      return this.failure<PlacedObject>('NOT_FOUND', 'Object references an unknown catalog id.');
    }
    const placement: OperationResult<boolean> = canPlace(this.template, candidate);
    if (placement.code !== 'OK' || placement.data !== true) {
      return this.failure<PlacedObject>(placement.code, placement.message);
    }

    if (this.objects[index].centerX === center.x && this.objects[index].centerY === center.y) {
      const unchanged: OperationResult<PlacedObject> = {
        code: 'OK',
        message: 'Object already at the requested centre; no history entry recorded.',
        data: clonePlacedObject(this.objects[index])
      };
      return unchanged;
    }

    const before: PlacedObject[] = clonePlacedObjects(this.objects);
    this.objects[index].centerX = center.x;
    this.objects[index].centerY = center.y;
    this.recordEffectiveChange(before);
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Object moved.',
      data: clonePlacedObject(this.objects[index])
    };
    return result;
  }

  /**
   * Rotates a committed object clockwise by exactly 90 degrees. If the rotated
   * footprint leaves the booth the previous rotation is preserved.
   */
  rotateObject(id: string): OperationResult<PlacedObject> {
    if (this.dragging) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT',
        'Objects cannot rotate during a drag.');
    }
    const index: number = this.findObjectIndex(id);
    if (index < 0) {
      return this.failure<PlacedObject>('NOT_FOUND', 'No placed object with id: ' + id);
    }
    const current: PlacedObject = this.objects[index];
    if (!isValidRotation(current.rotation)) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT',
        'Stored rotation is not 0, 90, 180 or 270 degrees.');
    }

    const candidate: PlacedObject = clonePlacedObject(current);
    candidate.rotation = nextRotation(current.rotation);
    const catalog: CatalogItem | undefined = getCatalogItemById(candidate.catalogId);
    if (catalog === undefined) {
      return this.failure<PlacedObject>('NOT_FOUND', 'Object references an unknown catalog id.');
    }
    const placement: OperationResult<boolean> = canPlace(this.template, candidate);
    if (placement.code !== 'OK' || placement.data !== true) {
      return this.failure<PlacedObject>(placement.code, placement.message);
    }

    const before: PlacedObject[] = clonePlacedObjects(this.objects);
    this.objects[index].rotation = candidate.rotation;
    this.recordEffectiveChange(before);
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Object rotated 90 degrees clockwise.',
      data: clonePlacedObject(this.objects[index])
    };
    return result;
  }

  /**
   * Removes a committed object. A missing id is NOT_FOUND and does not touch
   * history. The returned payload is a copy of the removed object, so undo can
   * restore the exact id/catalog/centre/rotation/zIndex snapshot.
   */
  removeObject(id: string): OperationResult<PlacedObject> {
    if (this.dragging) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT',
        'Objects cannot be removed during a drag.');
    }
    const index: number = this.findObjectIndex(id);
    if (index < 0) {
      return this.failure<PlacedObject>('NOT_FOUND', 'No placed object with id: ' + id);
    }
    const before: PlacedObject[] = clonePlacedObjects(this.objects);
    const removed: PlacedObject = clonePlacedObject(this.objects[index]);
    this.objects.splice(index, 1);
    if (this.selectedId === id) {
      this.selectedId = null;
    }
    this.recordEffectiveChange(before);
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Object removed.',
      data: removed
    };
    return result;
  }

  // ------------------------------------------------------------------
  // Drag lifecycle: preview only until endDrag
  // ------------------------------------------------------------------

  /**
   * Starts a preview drag. The pointer-to-centre offset is stored so the object
   * does not jump when the gesture starts away from its exact centre.
   */
  beginDrag(id: string, worldPoint: Point): OperationResult<PlacedObject> {
    if (this.dragging) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'A drag is already active.');
    }
    const index: number = this.findObjectIndex(id);
    if (index < 0) {
      return this.failure<PlacedObject>('NOT_FOUND', 'No placed object with id: ' + id);
    }
    if (!isFinitePoint(worldPoint)) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'Drag point must be finite.');
    }
    const object: PlacedObject = this.objects[index];
    if (!isValidRotation(object.rotation)) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT',
        'Stored rotation is not 0, 90, 180 or 270 degrees.');
    }
    const catalog: CatalogItem | undefined = getCatalogItemById(object.catalogId);
    if (catalog === undefined) {
      return this.failure<PlacedObject>('NOT_FOUND', 'Object references an unknown catalog id.');
    }
    const footprint: OperationResult<Rect> = getFootprintRect(object, catalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      return this.failure<PlacedObject>(footprint.code, footprint.message);
    }

    this.selectedId = object.id;
    this.dragOffsetX = object.centerX - worldPoint.x;
    this.dragOffsetY = object.centerY - worldPoint.y;
    const preview: PlacedObject = clonePlacedObject(object);
    this.preview = preview;
    this.dragging = true;
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Drag preview started.',
      data: clonePlacedObject(preview)
    };
    return result;
  }

  /**
   * Moves only the preview. The preview is allowed outside the booth so the UI
   * can show the current pointer position; committing is decided by endDrag.
   */
  updateDrag(worldPoint: Point): OperationResult<PlacedObject> {
    if (!this.dragging) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'No active drag preview.');
    }
    const preview: PlacedObject | null = this.preview;
    if (preview === null) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'No active drag preview.');
    }
    if (!isFinitePoint(worldPoint)) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'Drag point must be finite.');
    }
    const nextCenterX: number = worldPoint.x + this.dragOffsetX;
    const nextCenterY: number = worldPoint.y + this.dragOffsetY;
    if (!isFiniteNumber(nextCenterX) || !isFiniteNumber(nextCenterY)) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'Preview centre is not finite.');
    }
    preview.centerX = nextCenterX;
    preview.centerY = nextCenterY;
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Drag preview updated.',
      data: clonePlacedObject(preview)
    };
    return result;
  }

  /**
   * Ends the drag once. Commits the preview centre if the footprint is fully
   * inside the booth; otherwise clears the preview, keeps the last committed
   * centre and returns OUT_OF_BOUNDS. The caller should push the final UP point
   * through updateDrag first.
   */
  endDrag(): OperationResult<PlacedObject> {
    if (!this.dragging) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'No active drag to end.');
    }
    const preview: PlacedObject | null = this.preview;
    if (preview === null) {
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'No active drag to end.');
    }
    const index: number = this.findObjectIndex(preview.id);
    if (index < 0) {
      this.clearDragState();
      return this.failure<PlacedObject>('NOT_FOUND', 'Dragged object no longer exists.');
    }
    if (!isFiniteNumber(preview.centerX) || !isFiniteNumber(preview.centerY)) {
      this.clearDragState();
      return this.failure<PlacedObject>('INVALID_ARGUMENT', 'Preview centre is not finite.');
    }
    const catalog: CatalogItem | undefined = getCatalogItemById(preview.catalogId);
    if (catalog === undefined) {
      this.clearDragState();
      return this.failure<PlacedObject>('NOT_FOUND', 'Object references an unknown catalog id.');
    }
    const placement: OperationResult<boolean> = canPlace(this.template, preview);
    if (placement.code !== 'OK' || placement.data !== true) {
      this.clearDragState();
      return this.failure<PlacedObject>(placement.code,
        placement.code === 'OUT_OF_BOUNDS' ?
          'Drag ended outside the allowed placement; the last committed centre was kept.' :
          placement.message);
    }

    const changed: boolean = this.objects[index].centerX !== preview.centerX ||
      this.objects[index].centerY !== preview.centerY;
    const before: PlacedObject[] = changed ? clonePlacedObjects(this.objects) : [];
    this.objects[index].centerX = preview.centerX;
    this.objects[index].centerY = preview.centerY;
    this.clearDragState();
    if (changed) {
      this.recordEffectiveChange(before);
    }
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Drag committed.',
      data: clonePlacedObject(this.objects[index])
    };
    return result;
  }

  /** Abandons the preview. Committed objects were never modified. */
  cancelDrag(): OperationResult<boolean> {
    if (!this.dragging) {
      return this.failure<boolean>('INVALID_ARGUMENT', 'No active drag to cancel.');
    }
    this.clearDragState();
    const result: OperationResult<boolean> = {
      code: 'OK',
      message: 'Drag cancelled; committed state unchanged.',
      data: true
    };
    return result;
  }

  // ------------------------------------------------------------------
  // Undo / redo
  // ------------------------------------------------------------------

  /**
   * Restores the complete object array saved before the newest effective
   * operation. Returns NO_HISTORY without changing state when unavailable.
   * Undo/redo are rejected while a drag preview is active.
   */
  undo(): OperationResult<PlacedObject[]> {
    if (this.dragging) {
      return this.failure<PlacedObject[]>('INVALID_ARGUMENT',
        'Undo is not available during a drag.');
    }
    const entry: HistoryEntry | null = this.history.undo();
    if (entry === null) {
      return this.failure<PlacedObject[]>('NO_HISTORY', 'Nothing to undo.');
    }
    this.objects = cloneHistoryObjects(entry.before);
    this.reconcileSelection();
    this.touchFormalPlanUpdatedAt();
    this.changeRevision = this.changeRevision + 1;
    const result: OperationResult<PlacedObject[]> = {
      code: 'OK',
      message: 'Undo applied.',
      data: clonePlacedObjects(this.objects)
    };
    return result;
  }

  /** Re-applies the after snapshot of the newest undone operation. */
  redo(): OperationResult<PlacedObject[]> {
    if (this.dragging) {
      return this.failure<PlacedObject[]>('INVALID_ARGUMENT',
        'Redo is not available during a drag.');
    }
    const entry: HistoryEntry | null = this.history.redo();
    if (entry === null) {
      return this.failure<PlacedObject[]>('NO_HISTORY', 'Nothing to redo.');
    }
    this.objects = cloneHistoryObjects(entry.after);
    this.reconcileSelection();
    this.touchFormalPlanUpdatedAt();
    this.changeRevision = this.changeRevision + 1;
    const result: OperationResult<PlacedObject[]> = {
      code: 'OK',
      message: 'Redo applied.',
      data: clonePlacedObjects(this.objects)
    };
    return result;
  }

  // ------------------------------------------------------------------
  // Formal BoothPlan import / export
  // ------------------------------------------------------------------

  /**
   * Replaces the whole formal-plan state with a validated plan. Validation and
   * cloning complete before any state is touched, so a rejected import leaves
   * the current plan, objects, selection, drag and history exactly intact.
   * On success the imported objects are the only committed objects (no demo
   * seed table) and selection/drag/history are cleared.
   */
  importPlan(plan: BoothPlan): OperationResult<BoothPlan> {
    const validated: OperationResult<ValidatedPlanData> = this.validatePlan(plan);
    if (validated.code !== 'OK' || validated.data === undefined) {
      return this.failure<BoothPlan>(validated.code, validated.message);
    }
    const data: ValidatedPlanData = validated.data;

    this.template = data.template;
    this.objects = clonePlacedObjects(data.objects);
    this.planId = data.id;
    this.planName = data.name;
    this.planCreatedAt = data.createdAt;
    this.planUpdatedAt = data.updatedAt;
    this.selectedId = null;
    this.clearDragState();
    this.history.clear();
    this.changeRevision = 0;
    this.ensureAllocatorPastExisting();
    return this.exportPlan();
  }

  /**
   * Returns an independent committed snapshot of the formal plan. Demo
   * controllers (constructor-only M1 sessions) have no plan id and return
   * INVALID_ARGUMENT. Reading never changes updatedAt.
   */
  exportPlan(): OperationResult<BoothPlan> {
    const id: string | null = this.planId;
    if (id === null) {
      return this.failure<BoothPlan>('INVALID_ARGUMENT',
        'No formal plan is open; import a plan before exporting.');
    }
    const plan: BoothPlan = {
      id: id,
      name: this.planName,
      templateId: this.template.id,
      objects: clonePlacedObjects(this.objects),
      createdAt: this.planCreatedAt,
      updatedAt: this.planUpdatedAt
    };
    const result: OperationResult<BoothPlan> = {
      code: 'OK',
      message: 'Formal plan exported.',
      data: plan
    };
    return result;
  }

  // ------------------------------------------------------------------
  // Internal helpers
  // ------------------------------------------------------------------

  /**
   * Records exactly one effective operation and advances the formal plan
   * timestamp. Callers must pass a deep copy of the pre-operation objects.
   */
  private recordEffectiveChange(before: PlacedObject[]): void {
    this.history.record(before, this.objects);
    this.touchFormalPlanUpdatedAt();
    this.changeRevision = this.changeRevision + 1;
  }

  /**
   * updatedAt is persisted metadata only; change notification uses
   * changeRevision. It changes only on effective committed operations, undo
   * and redo. Demo sessions have no formal plan and keep their placeholder
   * timestamps. The value stays finite and never decreases. At or above 2^53
   * adding 1 may be a no-op in IEEE754, so an unchanged finite value here is
   * preserved rather than replaced.
   */
  private touchFormalPlanUpdatedAt(): void {
    if (this.planId === null) {
      return;
    }
    const now: number = Date.now();
    if (Number.isFinite(now) && now > this.planUpdatedAt) {
      this.planUpdatedAt = now;
      return;
    }
    const next: number = this.planUpdatedAt + 1;
    if (Number.isFinite(next)) {
      this.planUpdatedAt = next;
    }
  }

  /** Keeps selection only when the restored object still exists. */
  private reconcileSelection(): void {
    const selectedId: string | null = this.selectedId;
    if (selectedId !== null && this.findObjectIndex(selectedId) < 0) {
      this.selectedId = null;
    }
  }

  /**
   * Allocates a monotonically increasing instance id, skipping any id already
   * present (including ids restored by undo or imported from a plan). The
   * allocator is never rolled back from history snapshots.
   */
  private allocateInstanceId(): string {
    let candidate: string = INSTANCE_ID_PREFIX + this.nextInstanceNumber;
    while (this.findObjectIndex(candidate) >= 0) {
      this.nextInstanceNumber++;
      candidate = INSTANCE_ID_PREFIX + this.nextInstanceNumber;
    }
    this.nextInstanceNumber++;
    return candidate;
  }

  /**
   * Advances the allocator past small, safe numeric obj-N ids after a
   * successful import. Arbitrary imported ids are always accepted; ids whose
   * numeric suffix is too long to increment without precision loss are simply
   * not used as allocator seeds. allocateInstanceId still collision-checks the
   * real object list, so a skipped seed cannot cause a duplicate id.
   */
  private ensureAllocatorPastExisting(): void {
    for (let i = 0; i < this.objects.length; i++) {
      const id: string = this.objects[i].id;
      if (id.indexOf(INSTANCE_ID_PREFIX) !== 0) {
        continue;
      }
      const suffix: string = id.substring(INSTANCE_ID_PREFIX.length);
      if (suffix.length === 0 || suffix.length > MAX_SEEDABLE_ID_SUFFIX_LENGTH) {
        continue;
      }
      let allDigits: boolean = true;
      for (let j = 0; j < suffix.length; j++) {
        const code: number = suffix.charCodeAt(j);
        if (code < 48 || code > 57) {
          allDigits = false;
          break;
        }
      }
      if (!allDigits) {
        continue;
      }
      const value: number = Number(suffix);
      if (Number.isInteger(value) && value >= 0 &&
        value < MAX_SAFE_INSTANCE_NUMBER && value >= this.nextInstanceNumber) {
        this.nextInstanceNumber = value + 1;
      }
    }
  }

  /**
   * Validates a runtime BoothPlan without trusting any field. All object and
   * template lookups are performed on isolated copies; nothing is assigned to
   * controller state until the whole payload is known to be valid.
   */
  private validatePlan(plan: BoothPlan): OperationResult<ValidatedPlanData> {
    if (plan === null || plan === undefined) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT', 'Plan is required.');
    }
    if (typeof plan.id !== 'string') {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT', 'Plan id must be a string.');
    }
    // Frozen BoothPlan ids are any non-empty string: no arbitrary length cap.
    const planId: string = plan.id;
    if (planId.length < 1) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan id must be a non-empty string.');
    }
    if (typeof plan.name !== 'string') {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT', 'Plan name must be a string.');
    }
    // Names are canonical: trimmed and stored without leading/trailing spaces.
    const planName: string = plan.name.trim();
    if (planName.length < 1 || planName.length > PLAN_NAME_MAX_LENGTH) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan name must be 1 to 30 characters after trimming.');
    }
    if (typeof plan.templateId !== 'string') {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan template id must be a string.');
    }
    const template: BoothTemplate | undefined = getTemplateById(plan.templateId);
    if (template === undefined) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Unknown booth template: ' + plan.templateId);
    }
    if (typeof plan.createdAt !== 'number' || !Number.isFinite(plan.createdAt) ||
      plan.createdAt < 0) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan createdAt must be a finite non-negative timestamp.');
    }
    if (typeof plan.updatedAt !== 'number' || !Number.isFinite(plan.updatedAt) ||
      plan.updatedAt < 0) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan updatedAt must be a finite non-negative timestamp.');
    }
    if (plan.updatedAt < plan.createdAt) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan updatedAt cannot be earlier than createdAt.');
    }
    if (!Array.isArray(plan.objects)) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan objects must be an array.');
    }
    if (plan.objects.length > 0 && plan.objects[0] === null) {
      return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
        'Plan objects cannot contain null entries.');
    }

    const copies: PlacedObject[] = [];
    const seenIds: string[] = [];
    for (let i = 0; i < plan.objects.length; i++) {
      const raw: PlacedObject = plan.objects[i];
      if (raw === null || raw === undefined) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Plan objects cannot contain null entries.');
      }
      // Object ids are any non-empty string; no length cap is imposed here.
      if (typeof raw.id !== 'string' || raw.id.length === 0) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Every placed object needs a non-empty string id.');
      }
      if (seenIds.indexOf(raw.id) >= 0) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Placed object ids must be unique: ' + raw.id);
      }
      if (typeof raw.catalogId !== 'string' ||
        getCatalogItemById(raw.catalogId) === undefined) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Placed object references an unknown catalog id: ' + raw.catalogId);
      }
      if (!Number.isFinite(raw.centerX) || !Number.isFinite(raw.centerY)) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Placed object centre must be finite.');
      }
      if (!isValidRotation(raw.rotation)) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Placed object rotation must be 0, 90, 180 or 270 degrees.');
      }
      if (!Number.isFinite(raw.zIndex)) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Placed object zIndex must be finite.');
      }

      const catalog: CatalogItem | undefined = getCatalogItemById(raw.catalogId);
      if (catalog === undefined) {
        return this.failure<ValidatedPlanData>('INVALID_ARGUMENT',
          'Placed object references an unknown catalog id: ' + raw.catalogId);
      }
      const candidate: PlacedObject = {
        id: raw.id,
        catalogId: raw.catalogId,
        centerX: raw.centerX,
        centerY: raw.centerY,
        rotation: raw.rotation,
        zIndex: raw.zIndex
      };
      const footprint: OperationResult<Rect> = getFootprintRect(candidate, catalog);
      if (footprint.code !== 'OK' || footprint.data === undefined) {
        return this.failure<ValidatedPlanData>(footprint.code, footprint.message);
      }
      if (!isWithinBounds(footprint.data, template.widthCm, template.heightCm)) {
        return this.failure<ValidatedPlanData>('OUT_OF_BOUNDS',
          'Placed object ' + raw.id + ' leaves the booth bounds.');
      }
      for (let j = 0; j < template.blockedAreas.length; j++) {
        if (overlapsPositive(footprint.data, template.blockedAreas[j])) {
          return this.failure<ValidatedPlanData>('OUT_OF_BOUNDS',
            'Placed object ' + raw.id + ' overlaps a blocked area.');
        }
      }
      seenIds.push(raw.id);
      copies.push(candidate);
    }

    const validated: ValidatedPlanData = {
      id: planId,
      name: planName,
      template: template,
      objects: copies,
      createdAt: plan.createdAt,
      updatedAt: plan.updatedAt
    };
    const result: OperationResult<ValidatedPlanData> = {
      code: 'OK',
      message: 'Plan validated.',
      data: validated
    };
    return result;
  }

  private failure<T>(code: OperationCode, message: string): OperationResult<T> {
    const result: OperationResult<T> = {
      code: code,
      message: message
    };
    return result;
  }

  private findObjectIndex(id: string): number {
    for (let i = 0; i < this.objects.length; i++) {
      if (this.objects[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private nextZIndex(): number {
    let maximum: number = 0;
    for (let i = 0; i < this.objects.length; i++) {
      const value: number = this.objects[i].zIndex;
      if (Number.isFinite(value) && value > maximum) {
        maximum = value;
      }
    }
    return maximum + 1;
  }

  private clearDragState(): void {
    this.preview = null;
    this.dragging = false;
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
  }
}
