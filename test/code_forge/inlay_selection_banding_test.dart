import 'dart:io';
import 'dart:ui' as ui;

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/languages/python.dart';

/// Selecting a line that carries an inlay hint must tint it evenly.
///
/// The selection fill is translucent and the hint layer shifts the text after
/// each hint to the right. Both the selection pass and the hint layer's repaint
/// used to draw one rect *per text box*, each stretched by the whole shift of
/// the range. A paragraph splits into one box per font-fallback run — an italic
/// token in a font with no italic cut is enough — so those rects overlapped and
/// the fill painted the same pixels two or three times, leaving visibly darker
/// bands over the hint region.
///
/// The font is what makes the bug reachable: with the test font a line is a
/// single box and the overlap never happens. It is loaded from the host app
/// when this package is checked out inside it, and the test is skipped
/// otherwise rather than passing vacuously.
void main() {
  const selectionArgb = 0x4DE85100; // app selection tint: primary at 30%
  const selectionAlpha = 0x4D / 255;

  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Native runtime unavailable; the tests below cannot run.
    }
  });

  /// Blue-to-red ratio of a single layer of the tint over a white background.
  ///
  /// It only holds while the pixel is not stacked: glyph antialiasing darkens
  /// red and blue together, while another layer of the orange drops blue far
  /// faster than red.
  double singleLayerBRatio() {
    const cR = (selectionArgb >> 16) & 0xFF;
    const cB = selectionArgb & 0xFF;
    final r = cR * selectionAlpha + 255 * (1 - selectionAlpha);
    final b = cB * selectionAlpha + 255 * (1 - selectionAlpha);
    return b / r;
  }

  File? resolveFont() {
    for (final candidate in const [
      '../assets/fonts/JetBrainsMono-Medium.ttf',
      'assets/fonts/JetBrainsMono-Medium.ttf',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) return file;
    }
    return null;
  }

  InlayHint hint(int line, int column) => InlayHint(
    line: line,
    column: column,
    text: 'Unknown',
    kind: InlayHintKind.type,
    paddingLeft: true,
    paddingRight: true,
  );

  /// Renders [code], selects it up to [selectionEnd] and fails when any pixel
  /// carries more than one layer of the selection fill.
  Future<void> expectSelectionTintedOnce(
    WidgetTester tester, {
    required String code,
    required List<InlayHint> hints,
    required int selectionEnd,
  }) async {
    final font = resolveFont();
    if (font == null) {
      markTestSkipped('找不到宿主应用的等宽字体，跳过内联提示选中的叠色回归。');
      return;
    }
    try {
      final probe = CodeForgeController();
      probe.dispose();
    } catch (_) {
      markTestSkipped('code_forge 原生库未构建（RustLib.init 失败）。');
      return;
    }

    await (FontLoader('JetBrainsMono')..addFont(
          Future.value(
            ByteData.sublistView(Uint8List.fromList(font.readAsBytesSync())),
          ),
        ))
        .load();

    final controller = CodeForgeController();
    addTearDown(controller.dispose);
    controller.text = code;
    controller.setInlayHints(hints);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: selectionEnd,
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 800,
                height: 160,
                child: CodeForge(
                  controller: controller,
                  language: langPython,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'JetBrainsMono',
                    color: Colors.black,
                  ),
                  editorTheme: const {
                    'root': TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: Colors.black,
                      backgroundColor: Colors.white,
                    ),
                    // Italic, and the bundled face has no italic cut, so this
                    // run falls back to another font and splits the paragraph
                    // into several boxes.
                    'string': TextStyle(
                      fontFamily: 'OtherFont',
                      color: Colors.green,
                      fontStyle: FontStyle.italic,
                    ),
                  },
                  selectionStyle: CodeSelectionStyle(
                    selectionColor: const Color(selectionArgb),
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
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes;
    });
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();

    final single = singleLayerBRatio();
    var tinted = 0;
    var stacked = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      final r = bytes[i].toDouble();
      final b = bytes[i + 2].toDouble();
      // Only pixels the tint reached: bright, and still bluer than the
      // near-white hint chip.
      if (r < 240 || b <= 0) continue;
      final ratio = b / r;
      if ((ratio - single).abs() < 0.06) tinted++;
      if (ratio < single - 0.12) stacked++;
    }

    expect(tinted, greaterThan(200), reason: '选择的单层底色没有被画出来，测试前提不成立');
    expect(
      stacked,
      0,
      reason:
          '检出 $stacked 个比单层底色更深的像素：选择色被叠加了，'
          '内联提示的区域会随提示数量变深',
    );
  }

  testWidgets('a hint inside the selection is tinted once', (tester) async {
    // Three boxes: `val = `, the italic string, then the trailing spaces. The
    // hint sits in those spaces so the overlap of the stretched boxes lands on
    // blank cells instead of under glyphs, which keeps the measurement clean.
    await expectSelectionTintedOnce(
      tester,
      code: 'val = "abcd"        \nnext = 2\n',
      hints: [hint(0, 18)],
      selectionEnd: 20,
    );
  });

  testWidgets('a selection spanning two hinted lines is tinted once', (
    tester,
  ) async {
    await expectSelectionTintedOnce(
      tester,
      code: 'val = "abcd"        \nval = "efgh"        \nnext = 2\n',
      hints: [hint(0, 18), hint(1, 18)],
      selectionEnd: 41,
    );
  });
}
