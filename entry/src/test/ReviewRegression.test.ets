import { describe, it, expect } from '@ohos/hypium';
import { EditorController } from '../main/ets/engine/EditorController';
import { createViewport, worldToScreen, screenToWorld } from '../main/ets/engine/GeometryEngine';

// Codex independent integration regressions; member review is still pending.
export default function reviewRegressionTest() {
  describe('ReviewRegression', () => {
    it('finiteOverflowDoesNotCorruptDragPreview', 0, () => {
      const controller = new EditorController();
      expect(controller.beginDrag('obj-1', { x: -Number.MAX_VALUE, y: 200 }).code).assertEqual('OK');
      expect(controller.updateDrag({ x: Number.MAX_VALUE, y: 200 }).code).assertEqual('INVALID_ARGUMENT');
      const preview = controller.getPreviewObject();
      expect(preview !== null).assertTrue();
      if (preview === null) {
        throw new Error('Active drag lost its preview.');
      }
      expect(preview.centerX).assertEqual(300);
      expect(preview.centerY).assertEqual(200);
      expect(controller.getObjects()[0].centerX).assertEqual(300);
      expect(controller.endDrag().code).assertEqual('OK');
      expect(controller.getObjects()[0].centerX).assertEqual(300);
    });

    it('screenMappedDragCommitsSameWorldCentreAtDifferentSizes', 0, () => {
      const widths: number[] = [320, 390, 780];
      const heights: number[] = [440, 600, 300];
      for (let i = 0; i < widths.length; i++) {
        const controller = new EditorController();
        const viewport = createViewport(widths[i], heights[i], 600, 400);
        expect(viewport.code).assertEqual('OK');
        if (viewport.data === undefined) {
          throw new Error('Missing viewport.');
        }
        const startScreen = worldToScreen({ x: 310, y: 190 }, viewport.data);
        const endScreen = worldToScreen({ x: 410, y: 190 }, viewport.data);
        if (startScreen.data === undefined || endScreen.data === undefined) {
          throw new Error('Missing screen coordinates.');
        }
        const start = screenToWorld(startScreen.data, viewport.data);
        const end = screenToWorld(endScreen.data, viewport.data);
        if (start.data === undefined || end.data === undefined) {
          throw new Error('Missing world coordinates.');
        }
        expect(controller.beginDrag('obj-1', start.data).code).assertEqual('OK');
        expect(controller.updateDrag(end.data).code).assertEqual('OK');
        expect(controller.getObjects()[0].centerX).assertEqual(300);
        expect(controller.endDrag().code).assertEqual('OK');
        const object = controller.getObjects()[0];
        expect(Math.abs(object.centerX - 400) < 0.000001).assertTrue();
        expect(Math.abs(object.centerY - 200) < 0.000001).assertTrue();
      }
    });
  });
}
