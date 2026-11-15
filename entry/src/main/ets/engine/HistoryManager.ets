/**
 * BoothLab undo/redo snapshot history (M2-A01).
 *
 * Stores complete committed PlacedObject-array snapshots. Every entry keeps a
 * deep copy of both the state before and after one effective operation, so an
 * undo/redo cycle restores ids, catalog ids, centres, rotations and zIndex
 * exactly. The history never stores selection, previews, UI state or storage
 * payloads.
 *
 * Capacity is 50 effective operations. Recording a 51st entry drops the oldest
 * one. Recording after an undo clears the redo branch.
 *
 * This module is pure state bookkeeping: no geometry, no persistence, no UI.
 */

import { PlacedObject } from '../model/BoothModels';

/** Maximum number of effective operations retained for undo. */
export const HISTORY_CAPACITY: number = 50;

/** One reversible operation. before/after are independent deep snapshots. */
export interface HistoryEntry {
  before: PlacedObject[];
  after: PlacedObject[];
}

/**
 * Deep copy of one history entry. Returned entries never share before/after
 * arrays with the internal stacks, so callers cannot mutate stored history.
 */
export function cloneHistoryEntry(entry: HistoryEntry): HistoryEntry {
  const copy: HistoryEntry = {
    before: cloneHistoryObjects(entry.before),
    after: cloneHistoryObjects(entry.after)
  };
  return copy;
}

/** Deep copy of a placed-object array; never returns shared references. */
export function cloneHistoryObjects(objects: PlacedObject[]): PlacedObject[] {
  const copies: PlacedObject[] = [];
  for (let i = 0; i < objects.length; i++) {
    const object: PlacedObject = objects[i];
    const copy: PlacedObject = {
      id: object.id,
      catalogId: object.catalogId,
      centerX: object.centerX,
      centerY: object.centerY,
      rotation: object.rotation,
      zIndex: object.zIndex
    };
    copies.push(copy);
  }
  return copies;
}

export class HistoryManager {
  private undoStack: HistoryEntry[] = [];
  private redoStack: HistoryEntry[] = [];

  /**
   * Records one effective operation. Both snapshots are cloned immediately so
   * later controller mutations cannot corrupt the history. Any redo branch is
   * discarded.
   */
  record(before: PlacedObject[], after: PlacedObject[]): void {
    const entry: HistoryEntry = {
      before: cloneHistoryObjects(before),
      after: cloneHistoryObjects(after)
    };
    this.undoStack.push(entry);
    while (this.undoStack.length > HISTORY_CAPACITY) {
      this.undoStack.shift();
    }
    this.redoStack = [];
  }

  canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  /**
   * Moves the newest undo entry to the redo branch and returns an independent
   * clone. The caller applies the clone's before snapshot and may mutate it
   * freely without corrupting the stored history. Returns null when nothing
   * can undo.
   */
  undo(): HistoryEntry | null {
    if (this.undoStack.length === 0) {
      return null;
    }
    const index: number = this.undoStack.length - 1;
    const entry: HistoryEntry = this.undoStack[index];
    this.undoStack.pop();
    this.redoStack.push(entry);
    return cloneHistoryEntry(entry);
  }

  /**
   * Moves the newest redo entry back to the undo branch and returns an
   * independent clone. The caller applies the clone's after snapshot and may
   * mutate it freely without corrupting the stored history. Returns null when
   * nothing can redo.
   */
  redo(): HistoryEntry | null {
    if (this.redoStack.length === 0) {
      return null;
    }
    const index: number = this.redoStack.length - 1;
    const entry: HistoryEntry = this.redoStack[index];
    this.redoStack.pop();
    this.undoStack.push(entry);
    while (this.undoStack.length > HISTORY_CAPACITY) {
      this.undoStack.shift();
    }
    return cloneHistoryEntry(entry);
  }

  /** Drops every entry, for example when a plan is imported. */
  clear(): void {
    this.undoStack = [];
    this.redoStack = [];
  }
}
