import 'dart:ui' as ui;

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A selection reaching past an inlay hint must stay lit past the hint.
///
/// The hint layer erases everything from the first hint to the end of the
/// line and repaints the source text shifted right, which used to wipe the
/// selection highlight the moment a selection crossed the first hint. The
/// renderer now repaints the erased highlight behind the shifted text, and
/// the selection boxes themselves follow the hint shift.
///
/// The renderer has no geometry worth exposing, so this pins the behaviour at
/// the pixels: with an opaque distinctive selection color, the lit span on
/// the selected line must reach past the unshifted text. Before the fix it
/// stopped at the first hint (7 glyphs of 16px = 112px); now it covers the
/// shifted text too (11 glyphs plus the hint chip, well past 180px).
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Native runtime unavailable; the test below cannot run.
    }
  });

  testWidgets('selection highlight spans the inlay hint region', (
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
        '跳过内联提示选中回归；构建 code_forge 原生库后本测试会自动运行。',
      );
      return;
    }

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.text = 'self.fr = 1\nself.other = 2\n';

    // setInlayHints shows custom hints without an LSP round-trip; there is
    // no lspConfig to attach in a test.
    controller.setInlayHints([
      InlayHint(
        line: 0,
        column: 7,
        text: ': int',
        kind: InlayHintKind.type,
        paddingLeft: true,
      ),
    ]);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 11);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 800,
                height: 300,
                child: CodeForge(
                  controller: controller,
                  textStyle: const TextStyle(fontSize: 16, color: Colors.white),
                  selectionStyle: CodeSelectionStyle(
                    selectionColor: const Color(0xFF00D000),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    // Rasterization runs on real engine futures, which the test zone's fake
    // clock never drains; runAsync takes the capture out of it.
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes;
    });

    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    final width = boundary.size.width.round();

    // Collect the columns the selection color covers, row by row, over the
    // whole boundary: only the selected first line can carry it.
    int minX = bytes.length;
    int maxX = -1;
    for (var i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      if (g > 128 && r < 64 && b < 64) {
        final x = (i ~/ 4) % width;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }

    expect(maxX, greaterThanOrEqualTo(0), reason: 'selection was not painted');
    final span = maxX - minX;
    expect(
      span,
      greaterThan(180),
      reason:
          'selection highlight span was $span px; it must continue past the '
          'inlay hint (the unshifted text alone is 112 px wide)',
    );
  });
}
