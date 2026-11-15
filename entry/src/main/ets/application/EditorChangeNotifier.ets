/**
 * BoothLab M2-PRECOMMIT-EDGE-FIX editor change notifier.
 *
 * Production gate between EditorWorkspace refreshes and the shell's
 * SaveCoordinator. The editor reports one committed snapshot only when the
 * controller's independent session revision has advanced.
 *
 * The revision, not updatedAt, is the notification signal. updatedAt remains
 * finite persisted metadata: at or above 2^53 adding 1 can be a no-op in
 * IEEE754, so a timestamp-only gate could silently drop a real edit while the
 * repository still reported Saved. Keeping the gate in a small non-UI class
 * lets the real controller -> notifier -> SaveCoordinator -> repository path
 * be exercised by unit tests without invoking an ArkUI struct.
 *
 * The notifier never mutates a plan and never decides save state; it only
 * answers whether one refreshed committed snapshot should be reported.
 */
export class EditorChangeNotifier {
  private lastNotifiedRevision: number = -1;

  /** Establishes the baseline revision after a plan has been imported. */
  reset(revision: number): void {
    this.lastNotifiedRevision = revision;
  }

  /**
   * True when the session revision differs from the last reported revision.
   * A true answer advances the baseline, so one effective change is reported
   * once even though a refresh may run repeatedly. Invalid revisions never
   * notify; the controller only produces finite non-negative integers.
   */
  shouldNotify(revision: number): boolean {
    if (!Number.isFinite(revision) || revision < 0) {
      return false;
    }
    if (revision === this.lastNotifiedRevision) {
      return false;
    }
    this.lastNotifiedRevision = revision;
    return true;
  }
}
