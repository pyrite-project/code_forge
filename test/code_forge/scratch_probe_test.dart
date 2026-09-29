import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void dump(String name, List<String> lines, {String? lang}) {
  final segs = indentGuideSegments(
    firstLine: 0, lastLine: lines.length, tabSize: 4,
    lineTextAt: (i) => (i >= 0 && i < lines.length) ? lines[i] : '',
    languageId: lang,
  );
  print('--- $name ---');
  for (final s in segs) print('  SEG col=${s.columns} ${s.startLine}..${s.endLine}');
}

void main() {
  test('probe', () {
    dump('docstring prose', [
      'class A:',
      '    def f(self):',
      '        """Summary.',
      '',
      '        Parameters',
      '            x : the value',
      '               (see below',
      '        """',
      '        return x',
    ], lang: 'python');

    dump('block comment c', [
      'int f(void) {',
      '    /* note',
      '       deeper prose here',
      '           even deeper',
      '    */',
      '    return 1;',
    ], lang: 'c');

    dump('nested docstring', [
      'class Foo:',
      '    def __init__(self, x):',
      '        self.x = x',
      '        if x:',
      '            """doc',
      '               prose',
      '            """',
      '            return 1',
      '        return 2',
    ], lang: 'python');

    dump('no language', [
      'def f(self):',
      '    """Summary (note',
      '        deeper prose',
      '    """',
      '    return 1',
    ]);
  });
}