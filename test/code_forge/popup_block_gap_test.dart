import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';

void main() {
  // Every block in a popup's markdown — prose, rule, fenced code block —
  // sits the same distance from its neighbors. The block content mirrors
  // what a Python language server actually sends for a hover: a signature
  // fence, a rule, then prose.
  group('popup block gap', () {
    const markdown =
        '```python\n'
        '(class) _SrcFB() -> _SrcFB\n'
        '```\n'
        '---\n'
        'Prose one `chip` here.\n\n'
        'Prose two after a blank line.\n';

    Future<void> pumpBlock(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                // Wide enough that the prose lines stay single-line: the
                // test font draws every glyph a full em wide.
                width: 600,
                child: MarkdownBlock(
                  data: markdown,
                  selectable: false,
                  generator: MarkdownGenerator(
                    linesMargin: EdgeInsets.only(top: kCodeBlockGap),
                    richTextBuilder: _probeRichText,
                    generators: [
                      SpanNodeGeneratorWithTag(
                        tag: MarkdownTag.hr.name,
                        generator: (_, _, _) =>
                            _ProbeDividerNode(const Color(0x80808080)),
                      ),
                      overlayInlineCodeGenerator(
                        outer: BorderRadius.circular(12),
                        gap: kOverlayPadding,
                        theme: const {
                          'root': TextStyle(
                            color: Colors.white,
                            backgroundColor: Color(0xff2b2b2b),
                          ),
                        },
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                        fallbackColor: Colors.grey[400],
                      ),
                    ],
                  ),
                  config: MarkdownConfig.darkConfig.copy(
                    configs: [
                      PConfig(
                        textStyle: const TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: Colors.white,
                        ),
                      ),
                      overlayCodeBlockConfig(
                        outer: BorderRadius.circular(12),
                        gap: kOverlayPadding,
                        theme: const {
                          'root': TextStyle(
                            color: Colors.white,
                            backgroundColor: Color(0xff2b2b2b),
                          ),
                        },
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
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

    testWidgets('every block boundary is kCodeBlockGap apart', (tester) async {
      await pumpBlock(tester);

      expect(tester.takeException(), isNull);

      // The fence and the rule both reach the tree as placeholder-only
      // paragraphs. The surfaces the reader sees sit *inside* them: the
      // block's decorated container and the rule's 1px line.
      final placeholders =
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is RichText && widget.text.toPlainText() == '\uFFFC',
              )
              .evaluate()
              .map((element) => element.widget as RichText)
              .toList()
            ..sort((a, b) {
              final topA = tester.getRect(find.byWidget(a)).top;
              final topB = tester.getRect(find.byWidget(b)).top;
              return topA.compareTo(topB);
            });
      expect(placeholders.length, 2);

      final fenceCard = tester.getRect(
        find.descendant(
          of: find.byWidget(placeholders.first),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        ),
      );
      final rule = tester.getRect(
        find.descendant(
          of: find.byWidget(placeholders.last),
          matching: find.byWidgetPredicate(
            // The rule is a bare filled Container: a color and nothing else.
            (widget) =>
                widget is Container &&
                widget.color != null &&
                widget.child == null,
          ),
        ),
      );
      final proseOne = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('Prose one'),
        ),
      );
      final proseTwo = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('Prose two'),
        ),
      );

      double gap(Rect upper, Rect lower) => lower.top - upper.bottom;
      final gaps = [
        gap(fenceCard, rule),
        gap(rule, proseOne),
        gap(proseOne, proseTwo),
      ];

      for (final gapValue in gaps) {
        expect(
          gapValue,
          closeTo(kCodeBlockGap, 0.5),
          reason: 'every markdown block boundary must be kCodeBlockGap apart',
        );
      }
    });
  });
}

/// Mirror of `code_area.dart`'s `_popupRichText`, which is private: the same
/// tiny root style that keeps placeholder-only paragraphs (the rule, the
/// code block wrapper) from inheriting the ambient Material line height.
Widget _probeRichText(InlineSpan span) =>
    Text.rich(span, style: const TextStyle(fontSize: 1, height: 1));

/// Stand-in for the hover popup's `_HoverDividerNode`, which is private to
/// `code_area.dart`: a rule renders as a 1px line inside a placeholder-only
/// paragraph either way.
class _ProbeDividerNode extends SpanNode {
  _ProbeDividerNode(this.color);

  final Color color;

  @override
  InlineSpan build() => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Container(height: 1, color: color),
  );
}
