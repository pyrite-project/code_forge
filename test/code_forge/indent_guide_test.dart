import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('indentGuideSegments', () {
    String at(List<String> lines, int i) =>
        (i >= 0 && i < lines.length) ? lines[i] : '';

    List<IndentGuideSegment> segments(
      List<String> lines, {
      int firstLine = 0,
      int lastLine = -1,
      int tabSize = 4,
      String? languageId,
    }) => indentGuideSegments(
      firstLine: firstLine,
      lastLine: lastLine < 0 ? lines.length : lastLine,
      tabSize: tabSize,
      lineTextAt: (i) => at(lines, i),
      languageId: languageId,
    );

    Set<int> columnsOf(
      List<String> lines, {
      int tabSize = 4,
      String? languageId,
    }) => segments(
      lines,
      tabSize: tabSize,
      languageId: languageId,
    ).map((s) => s.columns).toSet();
    // produce two guides, because the deepest level is never drawn.
    test('drops the deepest level and keeps every other one', () {
      const lines = [
        'class A {',
        '  bool operator ==(Object other) =>',
        '    other is MultilineStringRange &&',
        '    other.start == start &&',
        '};',
      ];

      // Levels present are 0, 2 and 4 columns; column 4 is the deepest, so the
      // guides are at column 0 and column 2 - one level before the text each
      // marks.
      expect(columnsOf(lines, tabSize: 2), {0, 2});
    });

    test('draws a guide one level before the indentation it marks', () {
      const lines = ['def f():', '    if x:', '        a = 1', '        b = 2'];

      // Bodies sit at column 4 and column 8, column 8 being the deepest, so the
      // guides are at column 0 and column 4.
      expect(columnsOf(lines), {0, 4});
    });

    test('draws no guide for the deepest level', () {
      const lines = ['def f():', '    a = 1', '    b = 2'];

      // Column 4 is the deepest indentation present and nothing is indented
      // past it, so only the column 0 guide survives.
      expect(columnsOf(lines), {0});
    });

    test('draws a single guide for a flat block', () {
      const lines = ['def f():', '    return 1'];

      expect(columnsOf(lines), {0});
    });

    // A statement wrapped over several physical lines. Its continuation is
    // indented far deeper than anything the block contains, so treating the
    // raw indentation of every line as a level invents guides down the middle
    // of the code.
    test('is not dragged by a wrapped signature', () {
      const lines = [
        'def get_sub_buffer(self, fb: FrameBuffer, x: int, y: int,',
        '                   w: int, h: int) -> bytearray:',
        '    """doc"""',
        '    return sub_buffer',
      ];

      // The continuation is at column 19 and the body at column 4, but the
      // statement starts at column 0, so the only level is column 4 and the
      // only guide is at column 0.
      expect(columnsOf(lines), {0});
    });

    test('is not dragged by a backslash continuation', () {
      const lines = [
        'def f():',
        '    total = one + \\',
        '              two',
        '    return total',
      ];

      // The continued line sits at column 14; it belongs to the statement
      // starting at column 4 and adds no level.
      expect(columnsOf(lines), {0});
    });

    test('is not dragged by a bracketed continuation', () {
      const lines = ['def f():', '    call(a,', '         b)', '    return 1'];

      expect(columnsOf(lines), {0});
    });

    test('ignores brackets inside string literals', () {
      const lines = ['def f():', '    s = "(((" ', '    return s'];

      expect(columnsOf(lines), {0});
    });

    test('keeps the deeper level of a nested block', () {
      const lines = ['def f():', '    if x:', '        a = 1', '    b = 2'];

      // Column 8 is present but not the deepest level of the file overall
      // only because column 4 is; here column 8 is deepest, so guides are at 0
      // and 4.
      expect(columnsOf(lines), {0, 4});
    });

    test('breaks a run where a line dedents out of it', () {
      const lines = [
        'class A:',
        '    def f(self):',
        '        a = 1',
        '        b = 2',
        '    def g(self):',
        '        c = 3',
        '        d = 4',
      ];

      final result = segments(lines);
      final atFour = result.where((s) => s.columns == 4).toList();

      // Column 4 marks both method bodies, so the run is split in two. The
      // exclusive end is the line that dedented back out to column 4 itself.
      expect(atFour.length, 2);
      expect(atFour[0].startLine, 2);
      expect(atFour[0].endLine, 4);
      expect(atFour[1].startLine, 5);
      expect(atFour[1].endLine, 7);
    });

    test('cuts the guide at a line with no characters at all', () {
      const lines = [
        'class A:',
        '    def f(self):',
        '        a = 1',
        '',
        '        b = 2',
      ];

      final result = segments(lines);
      final atFour = result.where((s) => s.columns == 4).toList();

      // The empty line shows nothing on screen, so no guide is painted over
      // it: the run is cut in two around it instead of spanning it.
      expect(atFour.length, 2);
      expect(atFour[0].startLine, 2);
      expect(atFour[0].endLine, 3);
      expect(atFour[1].startLine, 4);
      expect(atFour[1].endLine, 5);
    });

    test('treats a CRLF leftover line as empty', () {
      const lines = [
        'class A:',
        '    def f(self):',
        '        a = 1',
        '\r',
        '        b = 2',
      ];

      // A line terminator artifact carries no content either, so it cuts the
      // run just like a truly empty line does.
      final atFour = segments(lines).where((s) => s.columns == 4).toList();

      expect(atFour.length, 2);
    });

    test('continues a run through a whitespace-only line', () {
      const lines = [
        'class A:',
        '    def f(self):',
        '        a = 1',
        '    ',
        '        b = 2',
      ];

      final result = segments(lines);
      final atFour = result.where((s) => s.columns == 4).toList();

      // The line keeps its indentation on screen, so the run passes through
      // it and still ends on the line after the last indented one.
      expect(atFour.length, 1);
      expect(atFour.single.startLine, 2);
      expect(atFour.single.endLine, 5);
    });
    test('does not draw a guide for blank lines at the top level', () {
      const lines = ['', '', 'a = 1', ''];

      // Nothing is indented, so there is no level to draw a guide for.
      expect(segments(lines), isEmpty);
    });

    test('scans from an offset without inventing levels', () {
      const lines = ['def f():', '    if x:', '        a = 1', '        b = 2'];

      // Scanning from line 2, the levels present are 8 and 8, so the deepest is
      // the only one and nothing is drawn.
      final result = segments(lines, firstLine: 2);

      expect(result, isEmpty);
    });

    test('expands tabs to the next tab stop', () {
      const lines = ['def f():', '\tif x:', '\t\ta = 1'];

      expect(columnsOf(lines), {0, 4});
    });

    test('handles a first line that is already indented', () {
      const lines = ['    a = 1', '    b = 2', '    if x:', '        c = 3'];

      // Levels are 4 and 8; column 8 is deepest, so the guide is at column 4.
      expect(columnsOf(lines), {4});
    });

    test('returns nothing for an empty range', () {
      expect(segments(const ['a = 1'], firstLine: 1, lastLine: 1), isEmpty);
      expect(segments(const ['a = 1'], firstLine: 3, lastLine: 2), isEmpty);
    });

    // Prose is laid out for reading, not for nesting. A docstring or a block
    // comment can be indented far deeper than the code around it, and a level
    // hung off that indentation would appear out of nowhere in the middle of a
    // sentence - and stop again at the next wrapped line.
    test('draws no guide for the indentation of docstring prose', () {
      const lines = [
        'class A:',
        '    def f(self):',
        '        """Summary.',
        '',
        '        Parameters',
        '            x : the value',
        '               (see below',
        '        """',
        '        return x',
      ];

      // The prose sits at column 8, 12 and 15, but it belongs to the statement
      // at column 4, so no level above 4 survives - the deepest level, 8, is
      // return x's own. The prose still counts as covered ground for the runs
      // at those levels, so the column 4 guide reaches from the docstring down
      // past return x.
      expect(columnsOf(lines, languageId: 'python'), {0, 4});
    });

    test('draws no guide for the indentation of a block comment', () {
      const lines = [
        'int f(void) {',
        '    /* note',
        '       deeper prose here',
        '           even deeper',
        '    */',
        '    return 1;',
      ];

      // The comment's own indents (7 and 11) invent no level, but the comment
      // lines are indented past column 0, so the enclosing guide starts at the
      // comment's first line rather than below the whole block.
      final result = segments(lines, languageId: 'c');

      expect(result.length, 1);
      expect(result.single.startLine, 1);
      expect(result.single.endLine, 6);
      expect(result.single.columns, 0);
    });

    test('keeps guides running past the prose of a docstring', () {
      const lines = [
        'class Foo:',
        '    def __init__(self, x):',
        '        self.x = x',
        '        if x:',
        '            """doc',
        '               prose',
        '            """',
        '            return 1',
        '        return 2',
      ];

      final result = segments(lines, languageId: 'python');
      final atFour = result.where((s) => s.columns == 4).toList();
      final atEight = result.where((s) => s.columns == 8).toList();

      // Column 4 marks everything inside __init__, docstring included, so it
      // is one unbroken run rather than one that starts after the docstring.
      expect(atFour.length, 1);
      expect(atFour.single.startLine, 2);
      expect(atFour.single.endLine, 9);
      // Column 8 marks the body of the if, and the run reaches up to the
      // docstring's first line, which is indented past column 8 too.
      expect(atEight.length, 1);
      expect(atEight.single.startLine, 4);
      expect(atEight.single.endLine, 8);
    });

    // A single-line docstring is the first line of the body it opens, so the
    // enclosing guide has to start on the docstring line itself instead of
    // one line below it.
    test('starts the enclosing guide at a single-line docstring', () {
      const lines = [
        '@staticmethod',
        'def rotate(matrix) -> list[list[Any]]:',
        '    """将矩阵逆时针旋转90度"""',
        '    return list(map(list, zip(*matrix)))[::-1]',
      ];

      final result = segments(lines, languageId: 'python');
      final atZero = result.where((s) => s.columns == 0).toList();

      expect(atZero.length, 1);
      expect(atZero.single.startLine, 2);
      expect(atZero.single.endLine, 4);
    });

    test(
      'keeps the enclosing guide over docstring lines but not an empty one',
      () {
        const lines = [
          'def f():',
          '    """Summary.',
          '',
          '    Body line.',
          '    """',
          '    return 1',
        ];

        final result = segments(lines, languageId: 'python');
        final atZero = result.where((s) => s.columns == 0).toList();

        // The run opens at the docstring's first line, is cut by the empty
        // line inside it, and resumes at the wrapped body down to below the
        // closing delimiter.
        expect(atZero.length, 2);
        expect(atZero[0].startLine, 1);
        expect(atZero[0].endLine, 2);
        expect(atZero[1].startLine, 3);
        expect(atZero[1].endLine, 6);
      },
    );

    test('ignores prose indentation without a known language', () {
      const lines = [
        'def f(self):',
        '    """Summary (note',
        '        deeper prose',
        '    """',
        '    return 1',
      ];

      // With no language the spec matches nothing, so the prose is read as
      // ordinary code: its deeper indentation belongs to no statement above
      // and adds a level (8) that is the deepest present, so it is dropped.
      // What remains are the real nesting levels 0 and 4.
      expect(columnsOf(lines), {0, 4});
    });
  });

  group('indentColumnsOf', () {
    test('counts spaces and expands tabs', () {
      expect(indentColumnsOf('', 4), 0);
      expect(indentColumnsOf('    a', 4), 4);
      expect(indentColumnsOf('\ta', 4), 4);
      expect(indentColumnsOf('\t\ta', 4), 8);
      expect(indentColumnsOf(' \t a', 4), 5);
      expect(indentColumnsOf('a b', 4), 0);
    });
  });
}
