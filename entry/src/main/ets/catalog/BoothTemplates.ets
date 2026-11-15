/**
 * Built-in booth templates (M1-B01).
 *
 * Pure data and lookup functions only: no UI, storage, or plan state.
 * Geometry follows the shared BoothModels conventions: world coordinates in
 * centimetres, origin at the top-left of the booth, x growing right and y
 * growing down. Wall sides are boundary walls, so they are never represented
 * as interior blocked areas.
 */

import { BoothTemplate, Rect, Side } from '../model/BoothModels';

const STANDARD_WALL_SIDES: Side[] = ['left', 'top', 'right'];
const STANDARD_OPEN_SIDES: Side[] = ['bottom'];
const STANDARD_RESERVED_AREAS: Rect[] = [
  { x: 240, y: 340, width: 120, height: 60 }
];

const CORNER_WALL_SIDES: Side[] = ['left', 'top'];
const CORNER_OPEN_SIDES: Side[] = ['bottom', 'right'];
const CORNER_RESERVED_AREAS: Rect[] = [
  { x: 240, y: 340, width: 120, height: 60 },
  { x: 540, y: 140, width: 60, height: 120 }
];

const TEMPLATES: BoothTemplate[] = [
  {
    id: 'standard',
    name: '标准型展位',
    widthCm: 600,
    heightCm: 400,
    blockedAreas: [],
    reservedAreas: STANDARD_RESERVED_AREAS,
    wallSides: STANDARD_WALL_SIDES,
    openSides: STANDARD_OPEN_SIDES
  },
  {
    id: 'corner',
    name: '转角型展位',
    widthCm: 600,
    heightCm: 400,
    blockedAreas: [],
    reservedAreas: CORNER_RESERVED_AREAS,
    wallSides: CORNER_WALL_SIDES,
    openSides: CORNER_OPEN_SIDES
  }
];

function cloneRect(rect: Rect): Rect {
  return {
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height
  };
}

function cloneRectList(rects: Rect[]): Rect[] {
  const copy: Rect[] = [];
  for (let i = 0; i < rects.length; i++) {
    copy.push(cloneRect(rects[i]));
  }
  return copy;
}

function cloneSideList(sides: Side[]): Side[] {
  const copy: Side[] = [];
  for (let i = 0; i < sides.length; i++) {
    copy.push(sides[i]);
  }
  return copy;
}

function cloneTemplate(template: BoothTemplate): BoothTemplate {
  return {
    id: template.id,
    name: template.name,
    widthCm: template.widthCm,
    heightCm: template.heightCm,
    blockedAreas: cloneRectList(template.blockedAreas),
    reservedAreas: cloneRectList(template.reservedAreas),
    wallSides: cloneSideList(template.wallSides),
    openSides: cloneSideList(template.openSides)
  };
}

/**
 * Returns every built-in booth template. Each call returns an independent
 * deep copy so callers may freely mutate the result.
 */
export function listTemplates(): BoothTemplate[] {
  const result: BoothTemplate[] = [];
  for (let i = 0; i < TEMPLATES.length; i++) {
    result.push(cloneTemplate(TEMPLATES[i]));
  }
  return result;
}

/**
 * Returns a deep copy of the template with the given id, or undefined when no
 * template matches. There is no fallback template for unknown ids.
 */
export function getTemplateById(id: string): BoothTemplate | undefined {
  for (let i = 0; i < TEMPLATES.length; i++) {
    if (TEMPLATES[i].id === id) {
      return cloneTemplate(TEMPLATES[i]);
    }
  }
  return undefined;
}
