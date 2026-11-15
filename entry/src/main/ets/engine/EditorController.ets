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
 * M1 deliberately contains no history, persistence, plan CRUD, collision
 * warnings or layout-issue integration.
 */

import {
  BoothTemplate,
  CatalogItem,
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
  isValidRotation
} from './GeometryEngine';

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
      id: INSTANCE_ID_PREFIX + this.nextInstanceNumber,
      catalogId: catalog.id,
      centerX: center.x,
      centerY: center.y,
      rotation: 0,
      zIndex: this.nextZIndex()
    };
    const footprint: OperationResult<Rect> = getFootprintRect(candidate, catalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      return this.failure<PlacedObject>(footprint.code, footprint.message);
    }
    if (!isWithinBounds(footprint.data, this.template.widthCm, this.template.heightCm)) {
      return this.failure<PlacedObject>('OUT_OF_BOUNDS',
        'The object footprint would leave the booth bounds.');
    }

    this.objects.push(candidate);
    this.nextInstanceNumber++;
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
    const footprint: OperationResult<Rect> = getFootprintRect(candidate, catalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      return this.failure<PlacedObject>(footprint.code, footprint.message);
    }
    if (!isWithinBounds(footprint.data, this.template.widthCm, this.template.heightCm)) {
      return this.failure<PlacedObject>('OUT_OF_BOUNDS',
        'The object footprint would leave the booth bounds.');
    }

    this.objects[index].centerX = center.x;
    this.objects[index].centerY = center.y;
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
    const footprint: OperationResult<Rect> = getFootprintRect(candidate, catalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      return this.failure<PlacedObject>(footprint.code, footprint.message);
    }
    if (!isWithinBounds(footprint.data, this.template.widthCm, this.template.heightCm)) {
      return this.failure<PlacedObject>('OUT_OF_BOUNDS',
        'The rotated footprint would leave the booth bounds.');
    }

    this.objects[index].rotation = candidate.rotation;
    const result: OperationResult<PlacedObject> = {
      code: 'OK',
      message: 'Object rotated 90 degrees clockwise.',
      data: clonePlacedObject(this.objects[index])
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
    const footprint: OperationResult<Rect> = getFootprintRect(preview, catalog);
    if (footprint.code !== 'OK' || footprint.data === undefined) {
      this.clearDragState();
      return this.failure<PlacedObject>(footprint.code, footprint.message);
    }
    if (!isWithinBounds(footprint.data, this.template.widthCm, this.template.heightCm)) {
      this.clearDragState();
      return this.failure<PlacedObject>('OUT_OF_BOUNDS',
        'Drag ended outside the booth bounds; the last committed centre was kept.');
    }

    this.objects[index].centerX = preview.centerX;
    this.objects[index].centerY = preview.centerY;
    this.clearDragState();
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
  // Internal helpers
  // ------------------------------------------------------------------

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
