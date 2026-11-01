import 'package:code_forge/code_forge.dart';
import 'package:code_forge/code_forge/root_overlay_portal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The completion list is anchored to the caret's line: it has to open
/// entirely above or entirely below that line, never across it.
///
/// The list is laid out in the editor's own box, but the room above and below
/// the caret used to be measured against the overlay rect the editor sits in.
/// That rect reaches past the editor on every side, so the list was allowed to
/// grow taller than the space on the side it opened on, and the layout delegate
/// then slid it back into the box -- which put its top far above the caret and
/// left the caret's own line buried in the middle of the list. The popup read
/// as sitting beside the cursor and hid the code around it.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Native runtime unavailable; the test below cannot run.
    }
  });

  testWidgets('completion list clears the caret line', (tester) async {
    bool rustReady;
    try {
      final probe = CodeForgeController();
      probe.dispose();
      rustReady = true;
    } catch (_) {
      rustReady = false;
    }
    if (!rustReady) {
      markTestSkipped(
        'code_forge 原生库未构建（RustLib.init 失败），'
        '跳过补全浮窗定位回归；构建 code_forge 原生库后本测试会自动运行。',
      );
      return;
    }

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.text = List.generate(12, (i) => 'line $i').join('\n');

    const editorTop = 200.0;
    const editorSize = Size(400, 300);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                top: editorTop,
                width: editorSize.width,
                height: editorSize.height,
                // Hosting the editor in the root overlay makes the overlay
                // rect reach past the editor's box, which is the geometry the
                // popup used to be measured against.
                child: CodeForgeRootOverlayPortal(
                  targetSize: editorSize,
                  overlayChild: CodeForge(
                    controller: controller,
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Tenth line ("line 9" starts at 63): low enough in the 300px editor that
    // a 40-item list cannot fit below it and has to flip above. Moving the
    // caret after mount is what publishes its viewport position, which is the
    // anchor every popup is placed against.
    controller.selection = const TextSelection.collapsed(offset: 63);
    await tester.pump();
    await tester.pump();

    controller.suggestionsNotifier.value = List.generate(40, (i) => 'item_$i');
    await tester.pump();

    final firstItem = find.text('item_0');
    expect(firstItem, findsOneWidget);
    final popup = find
        .ancestor(of: firstItem, matching: find.byType(Card))
        .first;
    final popupRect = tester.getRect(popup);

    final editorRect = tester.getRect(find.byType(CodeForge));
    final lineHeight = controller.editorLineHeight!;
    final caretTop = editorRect.top + 9 * lineHeight;
    final caretBottom = caretTop + lineHeight;

    // The list stays inside the editor it belongs to.
    expect(popupRect.top, greaterThanOrEqualTo(editorRect.top - 0.5));
    expect(popupRect.bottom, lessThanOrEqualTo(editorRect.bottom + 0.5));
    // With no room below the caret, it opens above the caret's line.
    expect(popupRect.bottom, lessThanOrEqualTo(caretTop));
    // And it never straddles that line.
    final crossesCaretLine =
        popupRect.top < caretBottom && popupRect.bottom > caretTop;
    expect(
      crossesCaretLine,
      isFalse,
      reason:
          'completion list $popupRect covers the caret line '
          '[$caretTop, $caretBottom]',
    );
  });

  testWidgets('completion list stays below a caret near the top', (
    tester,
  ) async {
    bool rustReady;
    try {
      final probe = CodeForgeController();
      probe.dispose();
      rustReady = true;
    } catch (_) {
      rustReady = false;
    }
    if (!rustReady) {
      markTestSkipped('code_forge 原生库未构建，跳过补全浮窗定位回归。');
      return;
    }

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.text = List.generate(12, (i) => 'line $i').join('\n');

    const editorTop = 200.0;
    const editorSize = Size(400, 300);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                top: editorTop,
                width: editorSize.width,
                height: editorSize.height,
                child: CodeForgeRootOverlayPortal(
                  targetSize: editorSize,
                  overlayChild: CodeForge(
                    controller: controller,
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Caret on the second line: the room below is the larger side, so the list
    // must not flip above just because it is taller than that room.
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    await tester.pump();

    controller.suggestionsNotifier.value = List.generate(40, (i) => 'item_$i');
    await tester.pump();

    final firstItem = find.text('item_0');
    expect(firstItem, findsOneWidget);
    final popupRect = tester.getRect(
      find.ancestor(of: firstItem, matching: find.byType(Card)).first,
    );

    final editorRect = tester.getRect(find.byType(CodeForge));
    final lineHeight = controller.editorLineHeight!;
    final caretTop = editorRect.top + lineHeight;
    final caretBottom = caretTop + lineHeight;

    expect(popupRect.top, greaterThanOrEqualTo(caretBottom));
    expect(popupRect.bottom, lessThanOrEqualTo(editorRect.bottom + 0.5));
  });
}
