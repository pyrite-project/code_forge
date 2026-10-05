import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../LSP/lsp.dart';
import 'multiline_string.dart';

/// Net number of brackets a line leaves open, ignoring brackets that appear
/// inside string literals.
///
/// Only used to tell a statement that continues onto the next line from one
/// that starts there, so it is deliberately simple rather than a full lexer:
/// escaped characters are skipped and quotes are tracked well enough to keep a
/// bracket inside a string from being counted.
///
/// Braces are not counted. In the languages this editor highlights, a brace
/// left open at the end of a line is a block header - "class A {", "} else {"
/// - and treating it as a continuation would make every statement below it
/// look like part of one enormous statement. Parentheses and square brackets
/// carry no such meaning, so they are what actually carry a line over.
int _openBracketDelta(String line) {
  int delta = 0;
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];

    if (quote != null) {
      if (ch == r'\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
      continue;
    }

    if (ch == '\'' || ch == '"') {
      quote = ch;
      continue;
    }

    if (ch == '(' || ch == '[') {
      delta++;
    } else if (ch == ')' || ch == ']') {
      delta--;
    }
  }
  return delta;
}

/// Whether a statement starting on [line] is still unfinished when it ends, so
/// the next line continues it rather than starting a new one.
///
/// [masked] is [line] with the parts that sit inside a multi-line string or
/// block comment blanked out, so a bracket or a backslash in a docstring is
/// not mistaken for structure.
///
/// A line that ends with a backslash, or that leaves a parenthesis or square
/// bracket open, continues. A line that closes everything it opens does not: a
/// block header such as "class A {" also ends its line, and reading it as a
/// continuation would drag every line below it to the header's indentation.
bool _continuesStatement(String line, String masked) {
  if (_endsWithLineContinuation(masked)) return true;
  return _openBracketDelta(masked) > 0;
}

/// Replaces every stretch of [line] that lies inside a multi-line string or
/// block comment with spaces, keeping the length and the leading indentation
/// intact so offsets and [indentColumnsOf] still mean the same thing.
///
/// A docstring is prose. Reading its brackets as structure makes a line such
/// as `"""Summary (see below` look like an unclosed call, which then drags
/// every following line into one invented statement. Blanking the prose lets
/// the guide logic see only the code around it.
///
/// The opening delimiter is masked together with the prose it starts. The
/// tracker reports a range that begins *after* the delimiter, so the line that
/// opens a docstring would otherwise keep its quotes as apparent code and be
/// read as a statement of its own - inventing an indentation level for the
/// prose and hanging a guide off a sentence.
String _maskMultiline(
  String line,
  List<MultilineStringRange> ranges,
  MultilineStringSpec spec,
) {
  if (ranges.isEmpty) return line;

  final units = List<int>.of(line.codeUnits, growable: true);
  for (final range in ranges) {
    // An opener that this line starts sits immediately before the reported
    // range, so it is masked too; otherwise the line that opens a multi-line
    // construct would still look like code.
    var start = range.start < 0 ? 0 : range.start;
    for (var open = 0; open < spec.openers.length; open++) {
      final opener = spec.openers[open];
      if (start < opener.length) continue;
      if (line.startsWith(opener, start - opener.length)) {
        start -= opener.length;
        break;
      }
    }
    final end = range.end > units.length ? units.length : range.end;
    for (var i = start; i < end; i++) {
      units[i] = 0x20;
    }
  }
  return String.fromCharCodes(units);
}

/// Whether [line] ends with a backslash outside a string, which continues the
/// statement onto the next line in languages that use it.
bool _endsWithLineContinuation(String line) {
  var i = line.length - 1;
  while (i >= 0 && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r')) {
    i--;
  }
  return i >= 0 && line[i] == '\\';
}

/// Columns occupied by the leading whitespace of [line], expanding tabs to the
/// next multiple of [tabSize].
int indentColumnsOf(String line, int tabSize) {
  var columns = 0;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == ' ') {
      columns += 1;
    } else if (ch == '\t') {
      columns += tabSize <= 0 ? 1 : tabSize - (columns % tabSize);
    } else {
      break;
    }
  }
  return columns;
}

/// One vertical run of an indent guide.
class IndentGuideSegment {
  const IndentGuideSegment({
    required this.startLine,
    required this.endLine,
    required this.columns,
  });

  /// First line of the run, inclusive.
  final int startLine;

  /// Line after the run, exclusive.
  final int endLine;

  /// Indent level the guide is drawn at, in columns.
  final int columns;
}

/// Vertical runs of indent guides covering `[firstLine, lastLine)`.
///
/// A guide is drawn at a level a line is indented *past*, which is what makes
/// it sit one level before the text it marks: a body at column 4 is marked by
/// a guide at column 0. The same rule also explains the level editors never
/// draw - the deepest indentation present, since nothing is indented past it.
///
/// Levels come from the indentation of the lines that *start a statement*. A
/// line that merely continues the statement above it is attributed to that
/// statement and contributes no level of its own, which is what keeps a wrapped
/// signature from inventing guides:
/// ```
/// def get_sub_buffer(self, fb: FrameBuffer, x: int, y: int,
///                    w: int, h: int) -> bytearray:
///     return sub_buffer
/// ```
/// The continuation is indented at column 19 and the body at column 4, but the
/// statement it belongs to starts at column 0, so the only guide is at column 0.
///
/// A blank line adds no level of its own. One that carries whitespace still
/// shows its indent on screen, so guides pass through it; one with no
/// characters at all shows nothing, so it cuts the runs it falls inside and
/// no guide is painted over it - nor does it light one up as the caret's.
///
/// A line that is nothing but string or comment prose behaves the same way for
/// levels - it adds none of its own - but it does take part in runs, measured
/// by its real leading whitespace. A docstring is indented past the statement
/// that holds it, so the guides of the enclosing levels are drawn in front of
/// it instead of only from the first code line below it.
List<IndentGuideSegment> indentGuideSegments({
  required int firstLine,
  required int lastLine,
  required int tabSize,
  required String Function(int lineIndex) lineTextAt,
  String? languageId,
}) {
  if (lastLine <= firstLine) return const [];

  final count = lastLine - firstLine;
  final indents = List<int>.filled(count, 0);
  final blanks = List<bool>.filled(count, false);
  // Real leading whitespace of a line that is nothing but prose, `null` for
  // every other line. Prose contributes no level of its own, but it still
  // occupies an indented position on screen, so the run scan needs to know
  // where the line actually starts.
  final proseIndents = List<int?>.filled(count, null);
  // True for a line without a single character on it - `\r`-only lines from
  // CRLF sources included. Such a line shows nothing on screen, so no guide
  // is painted over it and the runs it falls inside are cut there.
  final bare = List<bool>.filled(count, false);
  // Multi-line strings and block comments carry prose, not structure, so the
  // guide scan needs to know which stretches of each line belong to one. The
  // tracker walks lines in order, which is exactly how this loop reads them.
  // A language with no multi-line construct of its own gets an empty spec, so
  // the tracker reports no ranges and every line is read as ordinary code.
  final spec =
      resolveMultilineStringSpec(languageId: languageId) ??
      const MultilineStringSpec(
        openers: <String>[],
        closers: <String>[],
        scopeKeys: <String>[],
      );
  final tracker = MultilineStringTracker(spec)..lineText = lineTextAt;

  var carriedIndent = 0;
  var continuationRun = false;

  for (var i = 0; i < count; i++) {
    final text = lineTextAt(firstLine + i);

    if (text.trim().isEmpty) {
      blanks[i] = true;
      // A blank line says nothing about the statement it sits in. One with
      // not a single character on it also carries no indent on screen, so
      // no guide of any level belongs on it.
      if (text.isEmpty || text == '\r') bare[i] = true;
      continue;
    }

    // Blank out any prose so only structure is left to reason about.
    final masked = _maskMultiline(
      text,
      tracker.rangesForLine(firstLine + i, lineTextAt),
      spec,
    );

    // A line that is nothing but prose - the body of a docstring, a block
    // comment - carries no code, so its indentation is prose layout rather
    // than a nesting level. Counting it would hang a guide off a wrapped
    // sentence. It keeps the indentation of the code line the prose belongs
    // to, so a run neither invents a deeper level nor breaks where the
    // sentence happens to be indented.
    //
    // The line is not dropped from the run scan the way a blank line is,
    // though: it is remembered with its real leading whitespace and takes
    // part in runs at the levels the code around it already uses. That is
    // what keeps a guide in front of a docstring line instead of starting
    // on the first code line below it.
    if (masked.trim().isEmpty) {
      indents[i] = carriedIndent;
      blanks[i] = true;
      proseIndents[i] = indentColumnsOf(text, tabSize);
      continue;
    }

    final ownIndent = indentColumnsOf(text, tabSize);

    // A line continues the statement above it when it sits further right than
    // that statement does, in which case it belongs to that statement and
    // contributes no level of its own. The flag is refreshed from the line
    // that was just read, so a wrapped line hands it to the line after it
    // instead of letting it stick for the rest of the file.
    final int columns;
    if (continuationRun && ownIndent > carriedIndent) {
      columns = carriedIndent;
    } else {
      columns = ownIndent;
      carriedIndent = ownIndent;
    }
    continuationRun = _continuesStatement(text, masked);

    indents[i] = columns;
  }
  // Guides sit at every distinct indentation except the deepest one, which
  // nothing is indented past. Using the levels actually present rather than
  // stepping by [tabSize] keeps the result correct for files that mix tabs
  // and spaces or indent by an unusual amount.
  final levels = <int>{for (var i = 0; i < count; i++) indents[i]}.toList()
    ..sort();
  // The deepest indentation present is the one nothing is indented past, and
  // that is exactly the level an editor never draws a guide for.
  if (levels.isNotEmpty) levels.removeLast();

  final segments = <IndentGuideSegment>[];
  for (final level in levels) {
    var runStart = -1;
    for (var i = 0; i < count; i++) {
      // A blank line contributes no level of its own. A whitespace-only one
      // still shows its indent on screen, so an open run passes through it.
      // A line with no characters at all shows nothing, so the open run is
      // cut at it - no guide is painted over the line itself - and a fresh
      // one starts at the next line indented past the level.
      final proseIndent = proseIndents[i];
      if (proseIndent == null && blanks[i]) {
        if (bare[i] && runStart >= 0) {
          segments.add(
            IndentGuideSegment(
              startLine: firstLine + runStart,
              endLine: firstLine + i,
              columns: level,
            ),
          );
          runStart = -1;
        }
        continue;
      }

      final indentInRun = proseIndent ?? indents[i];
      if (indentInRun > level) {
        if (runStart < 0) runStart = i;
        continue;
      }
      if (runStart >= 0) {
        segments.add(
          IndentGuideSegment(
            startLine: firstLine + runStart,
            endLine: firstLine + i,
            columns: level,
          ),
        );
        runStart = -1;
      }
    }

    if (runStart >= 0) {
      segments.add(
        IndentGuideSegment(
          startLine: firstLine + runStart,
          endLine: lastLine,
          columns: level,
        ),
      );
    }
  }

  return segments;
}

/// Represents a foldable code region in the editor.
///
/// A fold range defines a region of code that can be collapsed (folded) to hide
/// its contents. This is typically used for code blocks like functions, classes,
/// or control structures.
///
/// Fold ranges are automatically detected based on code structure (braces,
/// indentation) when folding is enabled in the editor.
///
/// Example:
/// ```dart
/// // A fold range from line 5 to line 10
/// final foldRange = FoldRange(5, 10);
/// foldRange.isFolded = true; // Collapse the region
/// ```
class FoldRange {
  /// The starting line index (zero-based) of the fold range.
  ///
  /// This is the line where the fold indicator appears in the gutter.
  final int startIndex;

  /// The ending line index (zero-based) of the fold range.
  ///
  /// When folded, all lines from `startIndex + 1` to `endIndex` are hidden.
  final int endIndex;

  /// Whether this fold range is currently collapsed.
  ///
  /// When true, the contents of this range are hidden in the editor.
  bool isFolded = false;

  /// Child fold ranges that were originally folded when this range was unfolded.
  ///
  /// Used to restore the fold state of nested ranges when toggling folds.
  List<FoldRange> originallyFoldedChildren = [];

  /// Creates a [FoldRange] with the specified start and end line indices.
  FoldRange(this.startIndex, this.endIndex);

  /// Adds a child fold range that was originally folded.
  ///
  /// Used internally to track nested fold states.
  void addOriginallyFoldedChild(FoldRange child) {
    if (!originallyFoldedChildren.contains(child)) {
      originallyFoldedChildren.add(child);
    }
  }

  /// Clears the list of originally folded children.
  void clearOriginallyFoldedChildren() {
    originallyFoldedChildren.clear();
  }

  /// Checks if a line is contained within this fold range.
  ///
  /// Returns true if [line] is strictly greater than [startIndex] and
  /// less than or equal to [endIndex].
  bool containsLine(int line) {
    return line > startIndex && line <= endIndex;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FoldRange &&
        other.startIndex == startIndex &&
        other.endIndex == endIndex;
  }

  @override
  int get hashCode => startIndex.hashCode ^ endIndex.hashCode;
}

/// Immutable copy of a folded region, safe to hold outside the editor.
///
/// The controller hands these out so callers can persist the folded state of a
/// session and seed it back into a fresh controller with
/// `CodeForgeController.restoreFoldedRanges`. [children] are nested ranges
/// that were folded before their parent collapsed; seeding them lets the
/// editor re-collapse them when the parent is unfolded again.
class FoldRangeSnapshot {
  final int startLine;
  final int endLine;
  final List<FoldRangeSnapshot> children;

  const FoldRangeSnapshot({
    required this.startLine,
    required this.endLine,
    this.children = const [],
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FoldRangeSnapshot &&
        other.startLine == startLine &&
        other.endLine == endLine &&
        _childrenEqual(other.children, children);
  }

  static bool _childrenEqual(
    List<FoldRangeSnapshot> a,
    List<FoldRangeSnapshot> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(startLine, endLine, Object.hashAll(children));
}

/// Custom scroll physics that reverses horizontal drag direction for RTL mode on mobile.
class RTLAwareScrollPhysics extends ClampingScrollPhysics {
  final bool isRTL;
  final bool isMobile;

  const RTLAwareScrollPhysics({
    super.parent,
    required this.isRTL,
    required this.isMobile,
  });

  @override
  RTLAwareScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return RTLAwareScrollPhysics(
      parent: buildParent(ancestor),
      isRTL: isRTL,
      isMobile: isMobile,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (isRTL && isMobile && position.axis == Axis.horizontal) {
      return super.applyPhysicsToUserOffset(position, -offset);
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (isRTL && isMobile && position.axis == Axis.horizontal) {
      return super.createBallisticSimulation(position, -velocity);
    }
    return super.createBallisticSimulation(position, velocity);
  }
}

/// Use the [GutterBuilder] to render custom content in the gutter.
/// eg:
/// ```dart
/// CodeForge(
///   gutterBuilder: GutterBuilder(
///     builder: (lineNumber, lineText) => if(lineNumber == 1) "[HEADER]" : null
///   )
/// )
/// ```
///
/// Result:
///
/// ```python
/// [HEADER]|   import os
///    2    |   import sys
///    3    |
///    4    |   def main():
///    5    |        pass
/// ```
/// -------------------------------------------------------------
///
/// To exclude the index from modified content. Set [includeReplacedIndex] to false.
/// <br> eg:
/// ```dart
/// CodeForge(
///   gutterBuilder: GutterBuilder(
///     includeReplacedIndex: false,
///     builder: (lineNumber, lineText) => if(lineNumber == 1) "[HEADER]" : null
///   )
/// )
/// ```
///
/// Result:
/// ```python
/// [HEADER]|   import os
///    1    |   import sys
///    2    |
///    3    |   def main():
///    4    |        pass
/// ```
class GutterBuilder {
  /// Builder that builds the custom gutter content.
  /// Takes the int lineNumber and String lineText parameters and returns the custom
  /// string content for the corresponding line.
  final String? Function(int, String) builder;

  /// To exclude the index from modified content. Set [includeReplacedIndex] to false.
  /// <br> eg:
  /// ```dart
  /// CodeForge(
  ///   gutterBuilder: GutterBuilder(
  ///     includeReplacedIndex: false,
  ///     builder: (lineNumber, lineText) => if(lineNumber == 1) "[HEADER]" : null
  ///   )
  /// )
  /// ```
  ///
  /// Result:
  /// ```python
  /// [HEADER]|   import os
  ///    1    |   import sys  # index `1` is included in the gutter.
  ///    2    |
  ///    3    |   def main():
  ///    4    |        pass
  /// ```
  final bool includeReplacedIndex;

  GutterBuilder({required this.builder, this.includeReplacedIndex = true});
}

/// Keyboard shortcuts used by the [CodeForge].
/// Ovrride to use your own custom shortcuts.
/// <br>
/// Defaults to:
/// ```dart
/// CodeForgeKeyboardShotcuts({
///   this.duplicate = const SingleActivator(LogicalKeyboardKey.keyD, control: true),
///   this.shiftLineUp = const SingleActivator(LogicalKeyboardKey.arrowUp, control: true, shift: true),
///   this.shiftLineDown= const SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
///   this.deletWordBackward = const SingleActivator(LogicalKeyboardKey.backspace, control: true),
///   this.deletWordForward = const SingleActivator(LogicalKeyboardKey.delete, control: true),
///   this.moveCursorToNextWord = const SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
///   this.moveCursorToPreviousWord = const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
///   this.moveSelectionToNextWord = const SingleActivator(LogicalKeyboardKey.arrowRight, control: true, shift: true),
///   this.moveSelectionToPreviousWord = const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true, shift: true),
///   this.lspCodeActions = const SingleActivator(LogicalKeyboardKey.period, control: true),
///   this.lspSignature = const SingleActivator(LogicalKeyboardKey.space, control: true, shift: true),
///   this.showFindBar = const SingleActivator(LogicalKeyboardKey.keyF, control: true),
///   this.showSearchAndReplaceBar = const SingleActivator(LogicalKeyboardKey.keyH, control: true),
/// });
/// ```
///
/// Note: The LSP inlay hints shortcut `(Ctrl + Alt)` is not modifiable.<br>
/// Also, core operations like cut, copy, paste, select all, undo, redo aren't modifiable.
class CodeForgeKeyboardShortcuts {
  /// Place the cursor at the starting position of the current line.
  /// Defaults to `Ctrl + home`
  final ShortcutActivator jumpToDocumentStart;

  /// Place the cursor at the starting position of the current line.
  /// Defaults to `Ctrl + end`
  final ShortcutActivator jumpToDocumentEnd;

  /// Similar to [jumpToDocumentStart], place the cursor at the starting position of the current line
  /// and selecting the text from the start position to the document start.
  /// Defaults to `Ctrl + Shift + home`.
  final ShortcutActivator jumpToDocumentStartAndSelectText;

  /// Similar to [jumpToDocumentEnd], place the cursor at the starting position of the current line
  /// and selecting the text from the start position to the document end.
  /// Defaults to `Ctrl + Shift + end`.
  final ShortcutActivator jumpToDocumentEndAndSelectText;

  /// Duplicate the selection, if no active selectio, current line gets duplicated.
  /// Defaults to `Shift + Alt + down`
  final ShortcutActivator duplicate;

  /// Grows the selection to the next occurrence of the word under the caret.
  /// Defaults to `Ctrl + D`
  final ShortcutActivator selectNextOccurrence;

  /// Deletes the line(s) the selection touches.
  /// Defaults to `Ctrl + Shift + K`
  final ShortcutActivator deleteLine;

  /// Extends a rectangular (column) selection one line down.
  /// Defaults to `Ctrl + Shift + Alt + down`
  final ShortcutActivator columnSelectDown;

  /// Extends a rectangular (column) selection one line up.
  /// Defaults to `Ctrl + Shift + Alt + up`
  final ShortcutActivator columnSelectUp;

  /// Toggles a block comment around the selection.
  /// Defaults to `Ctrl + Shift + /`
  final ShortcutActivator toggleBlockComment;

  /// Requests formatting from the language server.
  /// Defaults to `Shift + Alt + F`
  final ShortcutActivator formatDocument;

  /// Requests the references of the symbol under the caret.
  /// Defaults to `Shift + F12`
  final ShortcutActivator findReferences;

  /// Jumps to an implementation of the symbol under the caret.
  /// Defaults to `Ctrl + F12`
  final ShortcutActivator goToImplementation;

  /// Folds the region containing the caret.
  /// Defaults to `Ctrl + Shift + [`
  final ShortcutActivator foldRegion;

  /// Unfolds the region containing the caret.
  /// Defaults to `Ctrl + Shift + ]`
  final ShortcutActivator unfoldRegion;

  /// Folds every region in the document.
  /// Defaults to `Ctrl + K` then `Ctrl + 0`
  final ShortcutActivator foldAll;

  /// Unfolds every region in the document.
  /// Defaults to `Ctrl + K` then `Ctrl + J`
  final ShortcutActivator unfoldAll;

  /// Moves the current line upwards.
  /// Defaults to `Alt + up`
  final ShortcutActivator shiftLineUp;

  /// Moves the current line downwards.
  /// Defaults to `Alt + down`
  final ShortcutActivator shiftLineDown;

  /// Delete an entire word and moves the cursor backward.
  /// Defaults to `Ctrl + backspace`
  final ShortcutActivator deletWordBackward;

  /// Delete an entore word and moves the cursor forward.
  /// Defaults to `Ctrl + delete`
  final ShortcutActivator deletWordForward;

  /// Cursor jumps to the previous word.
  /// Defaults to `Ctrl + arrowLeft`
  final ShortcutActivator moveCursorToPreviousWord;

  /// Cursor jumps to the next word.
  /// Defaults to `Ctrl + arrowRight`
  final ShortcutActivator moveCursorToNextWord;

  /// Similar to [moveCursorToPreviousWord], but selection also jumps with the cursor.
  /// Defaults to `Ctrl + Shift + arrowLeft`
  final ShortcutActivator moveSelectionToPreviousWord;

  /// Extends the selection forward by one character at a time.
  /// Defaults to `Shift + arrowRight`
  final ShortcutActivator moveSelectionForward;

  /// Extends the selection backward by one character at a time.
  /// Defaults to `Shift + arrowLeft
  final ShortcutActivator moveSelectionBackward;

  /// Extends the text selection to upward lines.
  /// Defaults tp `Shift + arrowUp`.
  final ShortcutActivator moveSelectionUpward;

  /// Extends the text selection to downward lines.
  /// Defaults tp `Shift + arrowDown`.
  final ShortcutActivator moveSelectionDownward;

  /// Similar to [moveCursorToNextWord], but selection also jumps with the cursor.
  /// Defaults to `Ctrl + Shift + arrowRight`
  final ShortcutActivator moveSelectionToNextWord;

  /// Shows the [LSP code actions](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_codeAction) if available.
  /// Defaults to `Ctrl + .`
  final ShortcutActivator lspCodeActions;

  /// Shows [LSP signature help](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_signatureHelp) if available.
  /// Defaults to `Ctrl + Shift + space`
  final ShortcutActivator lspSignatureHelp;

  /// Show the word finder bar if provided.
  /// Defaults to `Ctrl + F`
  final ShortcutActivator showFindBar;

  /// Show the finder bar along with the replace bar.
  /// Defaults to `Ctrl + H`
  final ShortcutActivator showFindAndReplaceBar;

  /// Jumps the cursor to the start of the current line by selecting the line text.
  /// Defaults to `Shift + home`.
  final ShortcutActivator selectToLineStart;

  /// Jumps the cursor to the end of the current line by selecting the line text.
  /// Defaults to `Shift + end`.
  final ShortcutActivator selectToLineEnd;

  /// Creates mutlicursor to the same column and downward rows/lines.
  /// Defaults to `Ctrl + Alt + down`
  final ShortcutActivator extendMutliCursorDownward;

  /// Creates mutlicursor to the same column and upward rows/lines.
  /// Defaults to `Ctrl + Alt + up`
  final ShortcutActivator extendMutliCursorUpward;

  const CodeForgeKeyboardShortcuts({
    this.duplicate = const SingleActivator(
      LogicalKeyboardKey.arrowDown,
      alt: true,
      shift: true,
    ),
    this.selectNextOccurrence = const SingleActivator(
      LogicalKeyboardKey.keyD,
      control: true,
    ),
    this.deleteLine = const SingleActivator(
      LogicalKeyboardKey.keyK,
      control: true,
      shift: true,
    ),
    this.columnSelectDown = const SingleActivator(
      LogicalKeyboardKey.arrowDown,
      control: true,
      shift: true,
      alt: true,
    ),
    this.columnSelectUp = const SingleActivator(
      LogicalKeyboardKey.arrowUp,
      control: true,
      shift: true,
      alt: true,
    ),
    this.toggleBlockComment = const SingleActivator(
      LogicalKeyboardKey.slash,
      control: true,
      shift: true,
    ),
    this.formatDocument = const SingleActivator(
      LogicalKeyboardKey.keyF,
      alt: true,
      shift: true,
    ),
    this.findReferences = const SingleActivator(
      LogicalKeyboardKey.f12,
      shift: true,
    ),
    this.goToImplementation = const SingleActivator(
      LogicalKeyboardKey.f12,
      control: true,
    ),
    this.foldRegion = const SingleActivator(
      LogicalKeyboardKey.bracketLeft,
      control: true,
      shift: true,
    ),
    this.unfoldRegion = const SingleActivator(
      LogicalKeyboardKey.bracketRight,
      control: true,
      shift: true,
    ),
    // The VSCode spelling is a two-key chord (`Ctrl+K` then `Ctrl+0`).
    // A chord needs a stateful handler, which the flat activator table this
    // class describes cannot express, so the single-key variant is used
    // instead: `Ctrl+Shift+[` folds, `Ctrl+Shift+]` unfolds, and these two
    // take the unshifted brackets that would otherwise be dead.
    this.foldAll = const SingleActivator(
      LogicalKeyboardKey.bracketLeft,
      control: true,
    ),
    this.unfoldAll = const SingleActivator(
      LogicalKeyboardKey.bracketRight,
      control: true,
    ),
    this.shiftLineUp = const SingleActivator(
      LogicalKeyboardKey.arrowUp,
      alt: true,
    ),
    this.shiftLineDown = const SingleActivator(
      LogicalKeyboardKey.arrowDown,
      alt: true,
    ),
    this.deletWordBackward = const SingleActivator(
      LogicalKeyboardKey.backspace,
      control: true,
    ),
    this.deletWordForward = const SingleActivator(
      LogicalKeyboardKey.delete,
      control: true,
    ),
    this.moveCursorToNextWord = const SingleActivator(
      LogicalKeyboardKey.arrowRight,
      control: true,
    ),
    this.moveCursorToPreviousWord = const SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      control: true,
    ),
    this.moveSelectionToNextWord = const SingleActivator(
      LogicalKeyboardKey.arrowRight,
      control: true,
      shift: true,
    ),
    this.moveSelectionToPreviousWord = const SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      control: true,
      shift: true,
    ),
    this.moveSelectionUpward = const SingleActivator(
      LogicalKeyboardKey.arrowUp,
      shift: true,
    ),
    this.moveSelectionDownward = const SingleActivator(
      LogicalKeyboardKey.arrowDown,
      shift: true,
    ),
    this.moveSelectionForward = const SingleActivator(
      LogicalKeyboardKey.arrowRight,
      shift: true,
    ),
    this.moveSelectionBackward = const SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      shift: true,
    ),
    this.lspCodeActions = const SingleActivator(
      LogicalKeyboardKey.period,
      control: true,
    ),
    this.lspSignatureHelp = const SingleActivator(
      LogicalKeyboardKey.space,
      control: true,
      shift: true,
    ),
    this.showFindBar = const SingleActivator(
      LogicalKeyboardKey.keyF,
      control: true,
    ),
    this.showFindAndReplaceBar = const SingleActivator(
      LogicalKeyboardKey.keyH,
      control: true,
    ),
    this.jumpToDocumentStart = const SingleActivator(
      LogicalKeyboardKey.home,
      control: true,
    ),
    this.jumpToDocumentEnd = const SingleActivator(
      LogicalKeyboardKey.end,
      control: true,
    ),
    this.jumpToDocumentStartAndSelectText = const SingleActivator(
      LogicalKeyboardKey.home,
      control: true,
      shift: true,
    ),
    this.jumpToDocumentEndAndSelectText = const SingleActivator(
      LogicalKeyboardKey.end,
      control: true,
      shift: true,
    ),
    this.selectToLineStart = const SingleActivator(
      LogicalKeyboardKey.home,
      shift: true,
    ),
    this.selectToLineEnd = const SingleActivator(
      LogicalKeyboardKey.end,
      shift: true,
    ),
    this.extendMutliCursorDownward = const SingleActivator(
      LogicalKeyboardKey.arrowDown,
      control: true,
      alt: true,
    ),
    this.extendMutliCursorUpward = const SingleActivator(
      LogicalKeyboardKey.arrowUp,
      control: true,
      alt: true,
    ),
  });
}

/// Create a custom entry for the context menu (The menu that appears on right click).
/// Pass it to the [CodeForge] class to add the custom entry to the context menu.
/// eg:
/// ```dart
/// CodeForge(
///   customContextMenuItems: [
///     CustomContextMenu(
///        label: "Goto defenition",
///        desciption: "Ctrl + Shift + .",
///        onPress: ()=> goToDefinition()
///     ),
///     CustomContextMenu(
///        label: "Code actions",
///        desciption: "Ctrl + .",
///        onPress: ()=> getCodeActions()
///     ),
///   ]
/// )
/// ```
class CustomContextMenu {
  /// The label that shown in the context menu
  final String label;

  /// The description for the context item.
  /// Shown at the right end of the menu.
  final String description;

  /// The action to be performed on pressing the context menu item.
  final VoidCallback onPress;

  /// Whether this item should be included when the menu is opened.
  final bool Function()? visible;

  /// Whether this item should be included for the text offset that opened the menu.
  final bool Function(int textOffset)? visibleAt;

  /// The action to perform with the text offset that opened the menu.
  final void Function(int textOffset)? onPressAt;

  /// Optional icon shown before the label.
  final IconData? icon;

  const CustomContextMenu({
    required this.label,
    required this.description,
    required this.onPress,
    this.visible,
    this.visibleAt,
    this.onPressAt,
    this.icon,
  });
}

/// Use it to display error lints (wavy underlines) in [CodeForge].
class DiagnosticLine extends LspErrors {
  DiagnosticLine({
    required super.severity,
    required super.range,
    required super.message,
  });
}
