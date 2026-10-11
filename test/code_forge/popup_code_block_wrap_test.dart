import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';

void main() {
  // The hover and documentation popups cap their own width, so a fenced code
  // block inside them is laid out against that cap: long lines have to fold
  // onto the next line instead of running off the popup edge.
  group('popup code block', () {
    const markdown =
        '```python\n'
        'result = compute_display_part_base_buffer(new_data_register, '
        'old_data_register, unchanged_tolerance, refresh_deadline)\n'
        '```\n';

    Future<void> pumpBlock(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: MarkdownBlock(
                  data: markdown,
                  config: MarkdownConfig.darkConfig.copy(
                    configs: [
                      overlayCodeBlockConfig(
                        outer: BorderRadius.circular(12),
                        gap: kOverlayPadding,
                        theme: const {
                          'root': TextStyle(
                            color: Colors.white,
                            backgroundColor: Color(0xff2b2b2b),
                          ),
                        },
                        textStyle: const TextStyle(fontSize: 14),
                        styleNotMatched: const TextStyle(color: Colors.white),
                        language: 'python',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('wraps long lines instead of clipping them', (tester) async {
      await pumpBlock(tester);

      expect(tester.takeException(), isNull);

      // The code block reaches the tree as a WidgetSpan inside the block
      // paragraph, so the outer RichText only reports one placeholder box.
      // Measure the inner paragraph that actually carries the code text.
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('compute_display_part_base'),
        ),
      );
      final plain = paragraph.text.toPlainText();
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length),
      );
      final lineTops = boxes.map((box) => box.top.round()).toSet();

      expect(lineTops.length, greaterThan(1));
      expect(paragraph.size.width, lessThanOrEqualTo(300));
    });
  });
}
