import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isBlockCommented', () {
    test('recognises a delimited block', () {
      expect(isBlockCommented('/*\na\n*/', start: '/*', end: '*/'), isTrue);
    });

    test('ignores surrounding indentation', () {
      expect(
        isBlockCommented('    /*\n    a\n    */', start: '/*', end: '*/'),
        isTrue,
      );
    });

    test('rejects a block that only opens', () {
      expect(isBlockCommented('/*\na', start: '/*', end: '*/'), isFalse);
    });

    test('rejects plain code', () {
      expect(isBlockCommented('a\nb', start: '/*', end: '*/'), isFalse);
    });

    test('a too-short block is not a comment', () {
      // "/*/" satisfies both ends at once and must not read as commented.
      expect(isBlockCommented('/*/', start: '/*', end: '*/'), isFalse);
    });

    test('an empty end delimiter only needs the start', () {
      expect(isBlockCommented('<!--\na', start: '<!--', end: ''), isTrue);
    });

    test('a blank block is not a comment', () {
      expect(isBlockCommented('   \n  ', start: '/*', end: '*/'), isFalse);
    });
  });

  group('toggleBlockComment wrapping', () {
    test('puts each delimiter on its own line', () {
      expect(
        toggleBlockComment('a\nb', start: '/*', end: '*/'),
        '/*\n    a\n    b\n*/',
      );
    });

    test('indents the body one unit past the base indent', () {
      expect(
        toggleBlockComment('  a\n  b', start: '/*', end: '*/'),
        '  /*\n      a\n      b\n  */',
      );
    });

    test('honours a tab indent unit', () {
      expect(
        toggleBlockComment('a', start: '/*', end: '*/', indentUnit: '\t'),
        '/*\n\ta\n*/',
      );
    });

    test('leaves blank lines blank', () {
      // Indenting an empty line would leave trailing whitespace behind.
      expect(
        toggleBlockComment('a\n\nb', start: '/*', end: '*/'),
        '/*\n    a\n\n    b\n*/',
      );
    });

    test('a block that opens with a blank line still uses the real base', () {
      expect(
        toggleBlockComment('\n  a', start: '/*', end: '*/'),
        '  /*\n\n      a\n  */',
      );
    });

    test('docstring delimiters wrap for Python', () {
      expect(
        toggleBlockComment('x = 1', start: '"""', end: '"""'),
        '"""\n    x = 1\n"""',
      );
    });
  });

  group('toggleBlockComment unwrapping', () {
    test('removes both delimiters and the added indent', () {
      expect(
        toggleBlockComment('/*\n    a\n    b\n*/', start: '/*', end: '*/'),
        'a\nb',
      );
    });

    test('a wrapped-then-unwrapped block comes back unchanged', () {
      for (final original in ['a\nb', '  a\n    b', 'a\n\nb', '\ta\n\t\tb']) {
        final wrapped = toggleBlockComment(original, start: '/*', end: '*/');
        expect(
          toggleBlockComment(wrapped, start: '/*', end: '*/'),
          original,
          reason: 'round-trip failed for ${original.replaceAll('\n', r'\n')}',
        );
      }
    });

    test('unwraps an indented commented block', () {
      expect(
        toggleBlockComment('  /*\n      a\n  */', start: '/*', end: '*/'),
        '  a',
      );
    });

    test('drops only the start delimiter when there is no end', () {
      expect(toggleBlockComment('<!--\n    a', start: '<!--', end: ''), 'a');
    });

    test('a body already at column 0 comes back at column 0', () {
      // Dedenting must not clamp at zero and eat real code.
      expect(toggleBlockComment('/*\na\n*/', start: '/*', end: '*/'), 'a');
    });
  });
}
