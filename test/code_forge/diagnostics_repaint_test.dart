import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Diagnostics published while the document is untouched must reach the
/// renderer immediately.
///
/// The renderer only learned about diagnostics through the widget property
/// captured at build time, so a republish that changed nothing else — the
/// usual case: the edit fixed the error and the server republishes an empty
/// list — kept painting the stale squiggles until the next semantic-token or
/// suggestion update rebuilt the tree. The editor now pushes the fresh list
/// straight into the live renderer, and these tests pin that path by watching
/// the renderer's paint flag react to a notifier write alone.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Native runtime unavailable; the test below cannot run.
    }
  });

  testWidgets('a diagnostics write alone repaints the renderer', (
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
      markTestSkipped(
        'code_forge 原生库未构建（RustLib.init 失败），'
        '跳过诊断重绘回归；构建 code_forge 原生库后本测试会自动运行。',
      );
      return;
    }

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.text = 'line 1\nline 2\nline 3';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeForge(controller: controller),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    RenderBox getRenderer() =>
        tester.allRenderObjects
            .where(
              (renderObject) =>
                  renderObject.runtimeType.toString() == '_CodeFieldRenderer',
            )
            .first as RenderBox;

    final error = LspErrors(
      severity: 1,
      range: {
        'start': {'line': 0, 'character': 0},
        'end': {'line': 0, 'character': 6},
      },
      message: 'broken',
    );

    // A publish that changes no widget input must still schedule a repaint:
    // this is the write that used to leave stale squiggles on screen.
    controller.diagnosticsNotifier.value = [error];
    expect(getRenderer().debugNeedsPaint, isTrue);
    await tester.pump();
    expect(getRenderer().debugNeedsPaint, isFalse);

    // Clearing the list — the "error fixed" publish — repaints as well, so
    // the squiggle goes away the moment the server republishes.
    controller.diagnosticsNotifier.value = const [];
    expect(getRenderer().debugNeedsPaint, isTrue);
    await tester.pump();
    expect(getRenderer().debugNeedsPaint, isFalse);

    // Re-publishing the identical list instance changes nothing to paint.
    controller.diagnosticsNotifier.value = const [];
    expect(getRenderer().debugNeedsPaint, isFalse);
  });
}
