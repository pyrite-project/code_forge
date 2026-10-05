import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reindentPastedText', () {
    test('a single line is never touched', () {
      expect(
        reindentPastedText('        x = 1', targetIndent: ''),
        '        x = 1',
      );
      expect(
        reindentPastedText('        x = 1', targetIndent: '    '),
        '        x = 1',
      );
    });

    test('pasting a nested block one level up dedents it', () {
      expect(
        reindentPastedText(
          '    if x:\n        y = 1\n        z = 2',
          targetIndent: '',
        ),
        'if x:\n    y = 1\n    z = 2',
      );
    });

    test('a block pasted at its own indent is left alone', () {
      expect(
        reindentPastedText('if x:\n    a\n    b', targetIndent: ''),
        'if x:\n    a\n    b',
      );
    });

    test('a flat block pasted into an indented position is indented', () {
      expect(
        reindentPastedText('if x:\na\nb', targetIndent: '        '),
        'if x:\n        a\n        b',
      );
    });

    test(
      'the first line loses the source indent but gains no target indent',
      () {
        // It lands on the caret, which already sits at the target column.
        expect(
          reindentPastedText('    a\n    b', targetIndent: '  '),
          'a\n  b',
        );
      },
    );

    test('relative nesting inside the block survives', () {
      expect(
        reindentPastedText('def f():\n    a\n        b', targetIndent: ''),
        'def f():\n    a\n        b',
      );
    });

    test('relative nesting survives a dedent', () {
      expect(
        reindentPastedText('def f():\n    a\n        b', targetIndent: '  '),
        'def f():\n      a\n          b',
      );
    });

    test('blank lines stay exactly as they were', () {
      expect(reindentPastedText('    a\n\n    b', targetIndent: ''), 'a\n\nb');
    });

    test('a whitespace-only line is not given the target indent', () {
      expect(reindentPastedText('  a\n  \n  b', targetIndent: ''), 'a\n  \nb');
    });

    test('a line shallower than the first keeps its text', () {
      expect(reindentPastedText('    a\nb', targetIndent: ''), 'a\nb');
    });

    test('an unindented first line does not strip anything', () {
      expect(reindentPastedText('a\n    b', targetIndent: ''), 'a\n    b');
    });

    test('text past the first line indent is preserved verbatim', () {
      expect(reindentPastedText('\t\ta\n\t\t\tb', targetIndent: ''), 'a\n\tb');
    });

    test('tabs and spaces are both treated as indentation', () {
      expect(reindentPastedText('\ta\n\tb', targetIndent: '  '), 'a\n  b');
    });

    test('a trailing newline does not gain trailing indentation', () {
      expect(reindentPastedText('  a\n', targetIndent: ''), 'a\n');
    });

    test('a block that opens with a blank line is left alone', () {
      // Line one carries no indent, so there is nothing trustworthy to strip;
      // guessing from line two would flatten the nesting the user copied.
      expect(
        reindentPastedText('\n    a\n    b', targetIndent: ''),
        '\n    a\n    b',
      );
    });
  });
}
