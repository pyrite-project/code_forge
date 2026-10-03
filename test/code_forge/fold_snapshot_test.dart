import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the controller's fold-snapshot API: capturing the folded state
/// for persistence and seeding it back into a fresh controller.
///
/// Constructing the controller builds a Rust-backed rope, so the suite is
/// skipped when `code_forge` native code cannot be loaded — loudly, so a
/// skipped suite is not mistaken for a green one (see typing_behavior_test).
void main() {
  late bool rust;

  setUpAll(() async {
    try {
      await RustLib.init();
      rust = true;
    } catch (error) {
      rust = false;
      // ignore: avoid_print
      print(
        '!!! fold_snapshot_test SKIPPED: code_forge native library not '
        'loadable ($error) !!!',
      );
    }
  });

  test('a fresh controller reports no folded ranges', () {
    if (!rust) return;
    final controller = CodeForgeController();

    expect(controller.foldedRanges, isEmpty);
    expect(controller.firstVisibleLine, isNull);
  });

  test('restoreFoldedRanges seeds foldedRanges', () {
    if (!rust) return;
    final controller = CodeForgeController();
    controller.restoreFoldedRanges([
      const FoldRangeSnapshot(startLine: 2, endLine: 20),
      const FoldRangeSnapshot(startLine: 30, endLine: 34),
    ]);

    final snapshots = controller.foldedRanges;
    expect(snapshots.map((s) => (s.startLine, s.endLine)).toList(), [
      (2, 20),
      (30, 34),
    ]);
  });

  test('snapshot and restore round-trip nested originally-folded children', () {
    if (!rust) return;
    // Mirrors the live engine state: folding a parent moves its already-folded
    // children into `originallyFoldedChildren` and unfolds them, so every
    // descendant below the topmost folded range is unfolded but recorded.
    final parent = FoldRange(2, 20)..isFolded = true;
    final child = FoldRange(5, 9);
    parent.addOriginallyFoldedChild(child);
    final grandchild = FoldRange(11, 15);
    child.addOriginallyFoldedChild(grandchild);

    final controller = CodeForgeController()..foldings = {2: parent};
    final snapshots = controller.foldedRanges;

    expect(snapshots.length, 1);
    expect(snapshots.single.startLine, 2);
    expect(snapshots.single.children.single.startLine, 5);
    expect(snapshots.single.children.single.children.single.endLine, 15);

    final restored = CodeForgeController()..restoreFoldedRanges(snapshots);
    final restoredParent = restored.foldings[2]!;
    expect(restoredParent.isFolded, isTrue);
    // The child is hidden inside the collapsed parent but must come back
    // collapsed when the parent is unfolded, and so must its own recorded
    // descendants one level further down.
    final restoredChild = restoredParent.originallyFoldedChildren.single;
    expect(restoredChild.startIndex, 5);
    expect(restoredChild.isFolded, isFalse);
    expect(restoredChild.originallyFoldedChildren.single.endIndex, 15);
    expect(restoredChild.originallyFoldedChildren.single.isFolded, isFalse);
  });

  test('restoreFoldedRanges replaces any previously seeded state', () {
    if (!rust) return;
    final controller = CodeForgeController()
      ..restoreFoldedRanges([const FoldRangeSnapshot(startLine: 4, endLine: 8)])
      ..restoreFoldedRanges([
        const FoldRangeSnapshot(startLine: 10, endLine: 12),
      ]);

    expect(controller.foldedRanges.map((s) => s.startLine), [10]);
  });

  test('snapshot equality covers lines and children', () {
    const a = FoldRangeSnapshot(
      startLine: 1,
      endLine: 2,
      children: [FoldRangeSnapshot(startLine: 1, endLine: 2)],
    );
    const b = FoldRangeSnapshot(
      startLine: 1,
      endLine: 2,
      children: [FoldRangeSnapshot(startLine: 1, endLine: 2)],
    );
    const differentChild = FoldRangeSnapshot(
      startLine: 1,
      endLine: 2,
      children: [FoldRangeSnapshot(startLine: 1, endLine: 3)],
    );

    expect(a, equals(b));
    expect(a, isNot(equals(differentChild)));
    expect(a.hashCode, b.hashCode);
  });
}
