/// Whether [block] is already a [start]/[end] comment.
///
/// Surrounding whitespace is ignored, because a commented-out block is
/// almost always indented to match the code it sits in and the user is asking
/// "is this commented?" not "does this string begin with the delimiter?".
/// Anything else is reported as not commented: a false negative leaves the
/// user able to press the key again, while a false positive makes the toggle
/// silently strip a delimiter that is part of the code.
bool isBlockCommented(
  String block, {
  required String start,
  required String end,
}) {
  final trimmed = block.trim();
  if (trimmed.length < start.length + end.length) return false;
  if (!trimmed.startsWith(start)) return false;
  if (end.isEmpty) return true;
  return trimmed.endsWith(end);
}

/// Wraps or unwraps [block] in a [start]/[end] comment.
///
/// Wrapping indents the body one [indentUnit] further than the line the block
/// already sits at, and puts each delimiter on its own line. That keeps the
/// commented-out code visibly subordinate to the statement it replaced — the
/// alternative, a single-line `<!-- a\nb -->`, leaves the second line looking
/// like live code at column 0.
///
/// Unwrapping removes the delimiters and the one level of indentation they
/// introduced, so toggling twice returns the original text rather than a
/// slightly different one. That round-trip property is the whole reason to
/// compute the base indent here instead of letting the caller strip by hand.
///
/// Lines that are blank inside the block are left blank: indenting them would
/// leave trailing whitespace behind, which most editors flag in review.
String toggleBlockComment(
  String block, {
  required String start,
  required String end,
  String indentUnit = '    ',
}) {
  if (isBlockCommented(block, start: start, end: end)) {
    return _unwrapBlock(block, start: start, end: end, indentUnit: indentUnit);
  }
  return _wrapBlock(block, start: start, end: end, indentUnit: indentUnit);
}

String _wrapBlock(
  String block, {
  required String start,
  required String end,
  required String indentUnit,
}) {
  final lines = block.split('\n');
  // The base indent comes from the first line that has content; a block that
  // opens with a blank line would otherwise pin itself to column 0.
  final baseIndent = lines
      .map(_leadingIndent)
      .firstWhere((i) => i.isNotEmpty, orElse: () => '');

  final body = lines
      .map((line) {
        if (line.trim().isEmpty) return '';
        // Each line already carries the base indent, so it is stripped before the
        // base is put back on. Without that, a block indented two levels would gain
        // a level per toggle instead of coming back where it started.
        final content = baseIndent.isNotEmpty && line.startsWith(baseIndent)
            ? line.substring(baseIndent.length)
            : line;
        return '$baseIndent$indentUnit$content';
      })
      .join('\n');

  return '$baseIndent$start\n$body\n$baseIndent$end';
}

String _unwrapBlock(
  String block, {
  required String start,
  required String end,
  required String indentUnit,
}) {
  final lines = block.split('\n').toList();

  // Where the wrapper put its own indent: the block's base indent, which the
  // opening delimiter shares because the wrapper aligns both with it.
  final baseIndent = _leadingIndent(lines.first);

  // Which lines the wrapper owns. A delimiter that was generated sits alone on
  // its line, so removing it leaves an empty line that must go too — otherwise
  // unwrapping `/*\na\n*/` yields a stray pair of blank lines around the code.
  var bodyStart = 0;
  var bodyEnd = lines.length;

  final firstTrimmed = lines.first.trimLeft();
  if (firstTrimmed.startsWith(start)) {
    lines[0] = firstTrimmed.substring(start.length);
    if (lines[0].trim().isEmpty) bodyStart = 1;
  }
  if (end.isNotEmpty && bodyEnd > bodyStart) {
    final lastTrimmed = lines[bodyEnd - 1].trimRight();
    if (lastTrimmed.endsWith(end)) {
      lines[bodyEnd - 1] = lastTrimmed.substring(
        0,
        lastTrimmed.length - end.length,
      );
      if (lines[bodyEnd - 1].trim().isEmpty) bodyEnd -= 1;
    }
  }

  final body = <String>[
    for (var i = bodyStart; i < bodyEnd; i++)
      if (lines[i].trim().isEmpty)
        ''
      else
        _dedentOneUnit(
          lines[i],
          baseIndent: baseIndent,
          indentUnit: indentUnit,
        ),
  ];
  if (body.isEmpty) return '';
  final result = body.join('\n');
  // `/* a */` puts the delimiters on the same line as the code, and the space
  // between them is the wrapper's, not the author's. A block whose delimiters
  // sat on their own lines keeps whatever indentation it had.
  if (bodyStart == 0 && bodyEnd == lines.length && body.length == 1) {
    return result.trim();
  }
  return result;
}

/// Removes the one [indentUnit] that [_wrapBlock] added to [line].
///
/// The unit sits directly after [baseIndent], so that is where it is cut out:
/// measuring from the front would eat a tab when the unit is spaces, and
/// measuring from the end would eat the unit's last character along with a tab
/// that followed it. A body the wrapper never indented is left exactly as it
/// is — that check on the cut segment is what tells the two apart.
String _dedentOneUnit(
  String line, {
  required String baseIndent,
  required String indentUnit,
}) {
  final start = baseIndent.length;
  final cut = start + indentUnit.length;
  if (cut > line.length) return line;
  if (line.substring(start, cut).trim().isNotEmpty) return line;
  return line.substring(0, start) + line.substring(cut);
}

String _leadingIndent(String line) {
  var end = 0;
  while (end < line.length && _isSpace(line.codeUnitAt(end))) {
    end++;
  }
  return line.substring(0, end);
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;
