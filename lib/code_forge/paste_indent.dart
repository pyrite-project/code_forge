/// Re-indents a multi-line paste so the block lands at the indentation of the
/// line it is pasted into.
///
/// Copying a nested block and pasting it one level up is the case this fixes.
/// Pasting verbatim leaves every line carrying the old nesting, so the result
/// is syntactically valid but reads as if it never moved — and the user then
/// has to select and outdent the whole thing by hand.
///
/// The rules follow the ones every mainstream editor uses:
///
/// * a single-line paste is never touched, because there is no block to align;
/// * the indentation of the *first* pasted line is stripped from every line,
///   since only that much is known to be the source's nesting rather than part
///   of the code;
/// * the lines after the first are then given [targetIndent], while the first
///   is not — it lands on the caret, which already sits at that column, so
///   adding the indent again would shift the whole block one unit too far;
/// * blank lines are left exactly as they were, so trailing whitespace from
///   the source does not accumulate.
///
/// A block that opens with a blank line has no usable base indent on line one,
/// so it is left alone rather than guessed at.
///
/// [targetIndent] is expected to be the whitespace between the start of the
/// target line and the caret. Passing it empty degrades to "dedent the copied
/// block to column zero", which is the same function with the caller
/// reporting no indentation at the destination.
String reindentPastedText(String text, {required String targetIndent}) {
  if (!text.contains('\n')) return text;
  final lines = text.split('\n');
  // From the first line, not the first line with content: a block whose opener
  // sits at column 0 and whose body is indented is the common case, and taking
  // the body's indent would flatten the nesting the user is copying.
  final firstIndent = _leadingWhitespace(lines.first);
  if (firstIndent.isEmpty && targetIndent.isEmpty) return text;

  String dedent(String line) =>
      firstIndent.isNotEmpty && line.startsWith(firstIndent)
      ? line.substring(firstIndent.length)
      : line;

  final reindented = <String>[dedent(lines.first)];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) {
      reindented.add(line);
      continue;
    }
    reindented.add('$targetIndent${dedent(line)}');
  }
  return reindented.join('\n');
}

String _leadingWhitespace(String line) {
  var end = 0;
  while (end < line.length && _isSpace(line.codeUnitAt(end))) {
    end++;
  }
  return line.substring(0, end);
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;
