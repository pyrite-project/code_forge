import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';

void main() {
  // Inline code in a popup shares its surface with the fenced block next to
  // it: the same fill, the same hairline outline, and the same derived
  // radius, so `single backtick` code cannot read as a different kind of
  // surface than the ``` block below it.
  group('popup inline code', () {
    const markdown =
        'Plain line here.\n\n'
        'Call `EPD.blit()` to draw.\n\n'
        '```python\n'
        'blit()\n'
        '```\n';
    final outer = BorderRadius.circular(12);
    const theme = {
      'root': TextStyle(
        color: Colors.white,
        backgroundColor: Color(0xff2b2b2b),
      ),
    };
    // outer(12) - gap(8), floored at kMinNestedRadius: the same arc the
    // fenced block derives for the popup inset.
    const expectedDecoration = BoxDecoration(
      color: Color(0xff2b2b2b),
      borderRadius: BorderRadius.all(Radius.circular(4)),
      border: Border.fromBorderSide(
        BorderSide(width: 0.2, color: Colors.white),
      ),
    );

    Future<void> pumpBlock(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                // Wide enough that the prose lines stay single-line: the
                // test font draws every glyph a full em wide, so the chip
                // line needs more room than a real font would.
                width: 600,
                child: MarkdownBlock(
                  data: markdown,
                  generator: MarkdownGenerator(
                    generators: [
                      overlayInlineCodeGenerator(
                        outer: outer,
                        gap: kOverlayPadding,
                        theme: theme,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          // The real popups pass a style without an explicit
                          // height; the chip tightens its own text box, so
                          // the control comparison below stays deterministic
                          // under the test font.
                          height: 1.3,
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
                        outer: outer,
                        gap: kOverlayPadding,
                        theme: theme,
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

    Container decoratedAncestor(WidgetTester tester, Finder of) {
      return tester.widget<Container>(
        find.ancestor(
          of: of,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        ),
      );
    }

    testWidgets('renders as a chip, not a square text background', (
      tester,
    ) async {
      await pumpBlock(tester);

      expect(tester.takeException(), isNull);

      // The chip is a WidgetSpan carrying its own Text, with the backticks
      // stripped and the background on the chip itself rather than on the
      // text style.
      final chip = tester.widget<Text>(find.text('EPD.blit()'));
      expect(chip.style?.backgroundColor, isNull);
    });

    testWidgets('shares the fenced block surface', (tester) async {
      await pumpBlock(tester);

      expect(tester.takeException(), isNull);

      // The chip's surface is painted by a CustomPainter around the text,
      // not laid out by a Container — the decoration it paints must still be
      // the very one the fenced block builds.
      final chipPainter =
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((paint) => paint.painter)
              .whereType<InlineCodeChipPainter>()
              .single;
      final block = decoratedAncestor(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              // The chip's own RichText also contains 'blit()' inside
              // 'EPD.blit()', so name the fenced block by its content alone.
              widget.text.toPlainText().trim() == 'blit()',
        ),
      );

      // Identical decoration is the point: fill, outline, and the nested
      // radius all come from the same derivation for both surfaces.
      expect(block.decoration, expectedDecoration);
      expect(chipPainter.decoration, expectedDecoration);
    });

    testWidgets('does not inflate the line it sits on', (tester) async {
      await pumpBlock(tester);

      expect(tester.takeException(), isNull);

      // Two prose lines under the same config: a control paragraph and the
      // paragraph carrying the chip. The chip's layout box is its text box —
      // the painted surface adds nothing to layout — so both paragraphs come
      // out the same height.
      RenderParagraph proseLine(String prefix) {
        return tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith(prefix),
          ),
        );
      }

      final control = proseLine('Plain').size.height;
      final withChip = proseLine('Call').size.height;

      expect(
        withChip,
        lessThanOrEqualTo(control + 0.5),
        reason: 'the inline code chip must not grow its line',
      );
    });

    testWidgets('sits on the text baseline', (tester) async {
      await pumpBlock(tester);

      expect(tester.takeException(), isNull);

      // The chip's glyphs must share the surrounding text's baseline: a
      // middle-aligned box drifts with the paragraph's root style, which is
      // how the chip sank below its line.
      final proseLine = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('Call'),
        ),
      );
      final chipLine = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == 'EPD.blit()',
        ),
      );

      // Each paragraph's first-line baseline, in global coordinates: the
      // chip's box is placed so its baseline lands on the line baseline,
      // which puts the chip's glyphs on the very line the prose sits on.
      double baselineY(RenderParagraph paragraph) =>
          paragraph.localToGlobal(Offset.zero).dy +
          paragraph.computeDistanceToActualBaseline(TextBaseline.alphabetic);

      expect(
        baselineY(chipLine),
        closeTo(baselineY(proseLine), 0.5),
        reason: 'the chip must not sink below the surrounding text baseline',
      );
    });

    testWidgets('paints the code font with the theme color', (tester) async {
      await pumpBlock(tester);

      expect(tester.takeException(), isNull);

      // The theme root color wins; the fallback only covers a theme that
      // carries no color, matching what the block paints for text the
      // highlighter does not theme.
      final chip = tester.widget<Text>(find.text('EPD.blit()'));
      expect(chip.style?.fontFamily, 'monospace');
      expect(chip.style?.fontSize, 14);
      expect(chip.style?.color, Colors.white);
      // The tightened box that keeps the chip from growing its line.
      expect(chip.style?.height, kChipHeight);
    });
  });
}
