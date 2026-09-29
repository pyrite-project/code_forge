import 'dart:math' as math;

/// The parts of a language that can legally span several physical lines and
/// therefore have to be painted as one continuous run of tokens instead of
/// being re-read as fresh code on every line.
///
/// [openers], [closers] and [scopeKeys] are index aligned: reaching
/// `openers[i]` paints text through the next `closers[i]` with the theme entry
/// named by `scopeKeys[i]`, even when the two delimiters sit on different
/// lines.
///
/// [singleQuotes] are ordinary quotes that never span lines. They are skipped
/// over so an apostrophe inside a word, or a comment marker inside a quoted
/// value, is not mistaken for something structural. [lineComments] end the
/// scan of a line without opening anything, and [prefixLetters] lists the
/// identifier letters allowed directly in front of an opener, such as the `f`
/// of an f-string or the `r` of a raw string.
class MultilineStringSpec {
  const MultilineStringSpec({
    required this.openers,
    required this.closers,
    required this.scopeKeys,
    this.singleQuotes = const <String>{},
    this.lineComments = const <String>[],
    this.prefixLetters,
    this.escapes = true,
  });

  final List<String> openers;
  final List<String> closers;
  final List<String> scopeKeys;
  final Set<String> singleQuotes;
  final List<String> lineComments;
  final String? prefixLetters;

  /// Whether a backslash escapes the next character while looking for a
  /// closer. True for quoted strings, false for languages such as C where a
  /// backslash means nothing inside a block comment.
  final bool escapes;
}

/// A half-open `[start, end)` stretch of one line that belongs to a
/// multi-line construct, painted with [scopeKey].
class MultilineStringRange {
  const MultilineStringRange(this.start, this.end, this.scopeKey);

  final int start;
  final int end;
  final String scopeKey;

  @override
  bool operator ==(Object other) =>
      other is MultilineStringRange &&
      other.start == start &&
      other.end == end &&
      other.scopeKey == scopeKey;

  @override
  int get hashCode => Object.hash(start, end, scopeKey);
}

/// Python triple-quoted strings, the shape behind essentially every docstring.
const MultilineStringSpec _pythonSpec = MultilineStringSpec(
  openers: <String>["'''", '"""'],
  closers: <String>["'''", '"""'],
  scopeKeys: <String>['string', 'string'],
  singleQuotes: <String>{'"', "'"},
  lineComments: <String>['#'],
  prefixLetters: 'fFrRbBuU',
);

/// JavaScript and TypeScript template literals.
const MultilineStringSpec _templateLiteralSpec = MultilineStringSpec(
  openers: <String>['`'],
  closers: <String>['`'],
  scopeKeys: <String>['string'],
  singleQuotes: <String>{'"', "'"},
  lineComments: <String>['//'],
);

/// C-style block comments, the multi-line construct of the curly-brace
/// languages.
const MultilineStringSpec _blockCommentSpec = MultilineStringSpec(
  openers: <String>['/*'],
  closers: <String>['*/'],
  scopeKeys: <String>['comment'],
  singleQuotes: <String>{'"', "'"},
  lineComments: <String>['//'],
  escapes: false,
);

/// Dart carries both shapes, so it needs the union with a scope per opener.
const MultilineStringSpec _dartSpec = MultilineStringSpec(
  openers: <String>["'''", '"""', '/*'],
  closers: <String>["'''", '"""', '*/'],
  scopeKeys: <String>['string', 'string', 'comment'],
  singleQuotes: <String>{'"', "'"},
  lineComments: <String>['//'],
  prefixLetters: 'rR',
);

const Map<String, MultilineStringSpec> _specsByLanguageId =
    <String, MultilineStringSpec>{
      'python': _pythonSpec,
      'python3': _pythonSpec,
      'ipython': _pythonSpec,
      'javascript': _templateLiteralSpec,
      'javascriptreact': _templateLiteralSpec,
      'jsx': _templateLiteralSpec,
      'typescript': _templateLiteralSpec,
      'typescriptreact': _templateLiteralSpec,
      'tsx': _templateLiteralSpec,
      'dart': _dartSpec,
      'c': _blockCommentSpec,
      'cpp': _blockCommentSpec,
      'c++': _blockCommentSpec,
      'csharp': _blockCommentSpec,
      'c#': _blockCommentSpec,
      'java': _blockCommentSpec,
      'go': _blockCommentSpec,
      'rust': _blockCommentSpec,
      'kotlin': _blockCommentSpec,
      'swift': _blockCommentSpec,
      'scala': _blockCommentSpec,
      'groovy': _blockCommentSpec,
      'php': _blockCommentSpec,
      'objectivec': _blockCommentSpec,
      'objective-c': _blockCommentSpec,
      'objectivec++': _blockCommentSpec,
    };

/// Grammar names as reported by the `Mode` a file is actually opened with. The
/// editor picks its grammar from the file extension, so this is the lookup
/// that matters when no language id is configured.
const Map<String, MultilineStringSpec> _specsByModeName =
    <String, MultilineStringSpec>{
      'python': _pythonSpec,
      'javascript': _templateLiteralSpec,
      'dart': _dartSpec,
      'c': _blockCommentSpec,
      'c++': _blockCommentSpec,
    };

/// The spec for the language a file is open as, or `null` when the language
/// has no known multi-line construct. A `null` result leaves highlighting
/// exactly as it was before, so unlisted languages are unaffected.
MultilineStringSpec? resolveMultilineStringSpec({
  String? languageId,
  String? modeName,
}) {
  final id = languageId?.trim().toLowerCase();
  if (id != null && id.isNotEmpty) {
    final byId = _specsByLanguageId[id];
    if (byId != null) return byId;
  }

  final name = modeName?.trim().toLowerCase();
  if (name != null && name.isNotEmpty) {
    final byName = _specsByModeName[name];
    if (byName != null) return byName;
  }

  return null;
}

/// Reports which stretches of a line sit inside a multi-line string or block
/// comment so the editor can paint them as one continuous string rather than
/// as whatever the per-line grammar made of them.
///
/// The tracker keeps the boundary state for every line it has walked, so
/// asking for a line it has never seen costs one forward pass from the last
/// known boundary. Painting a viewport therefore touches each line once, no
/// matter how far down the file it starts.
class MultilineStringTracker {
  MultilineStringTracker(this.spec);

  final MultilineStringSpec spec;

  /// Text of a line by index. Without it the tracker cannot see the lines
  /// above a line and stays inert.
  String Function(int lineIndex)? lineText;

  final Map<int, List<MultilineStringRange>> _ranges =
      <int, List<MultilineStringRange>>{};
  final Map<int, int> _stateAfterLine = <int, int>{};
  final Map<int, String> _scannedText = <int, String>{};

  /// Line up to which the forward walk has run, and the boundary it produced.
  int _walkedLine = -1;
  int _stateAfterWalk = _closed;

  /// Upper bound on remembered line boundaries, so a very large file cannot
  /// grow the maps without limit. Dropping them only costs a re-walk.
  static const int _maxTrackedLines = 200000;

  /// Sentinel for "not inside a multi-line construct".
  static const int _closed = -1;

  /// The stretches of [lineText] that belong to a multi-line construct, with
  /// the line's own start at [textOffset] in the full line. This lets a caller
  /// that renders only a slice of a line still colour the slice correctly.
  List<MultilineStringRange> rangesForLine(
    int lineIndex,
    String Function(int lineIndex) lineText, {
    int textOffset = 0,
  }) {
    if (lineIndex < 0) return const <MultilineStringRange>[];

    final provider = this.lineText;
    if (provider == null) return const <MultilineStringRange>[];

    final whole = _rangesForWholeLine(lineIndex, provider, lineText);
    if (textOffset <= 0) return whole;
    if (whole.isEmpty) return const <MultilineStringRange>[];

    final shifted = <MultilineStringRange>[];
    for (final range in whole) {
      final start = range.start - textOffset;
      if (range.end <= textOffset) continue;
      shifted.add(
        MultilineStringRange(
          start < 0 ? 0 : start,
          range.end - textOffset,
          range.scopeKey,
        ),
      );
    }
    return shifted;
  }

  /// Drops everything derived from [line] and below. A change there also
  /// invalidates the boundary that *precedes* it, because that boundary is
  /// what decides whether [line] itself continues a construct.
  void invalidateFrom(int line) {
    if (line <= 0) {
      clear();
      return;
    }

    final firstAffected = line - 1;
    _ranges.removeWhere((index, _) => index >= firstAffected);
    _scannedText.removeWhere((index, _) => index >= firstAffected);
    _stateAfterLine.removeWhere((index, _) => index >= firstAffected);

    if (_walkedLine < firstAffected) return;

    final boundary = _stateAfterLine[firstAffected - 1];
    if (boundary != null) {
      _walkedLine = firstAffected - 1;
      _stateAfterWalk = boundary;
    } else {
      _resetWalk();
    }
  }

  void clear() {
    _ranges.clear();
    _stateAfterLine.clear();
    _scannedText.clear();
    _resetWalk();
  }

  void _resetWalk() {
    _walkedLine = -1;
    _stateAfterWalk = _closed;
  }

  List<MultilineStringRange> _rangesForWholeLine(
    int lineIndex,
    String Function(int lineIndex) provider,
    String Function(int lineIndex) lineText,
  ) {
    final text = lineText(lineIndex);
    final cached = _ranges[lineIndex];
    if (cached != null && _scannedText[lineIndex] == text) return cached;

    final state = _stateBeforeLine(lineIndex, lineText);
    final scanned = _scan(text, state);

    _ranges[lineIndex] = scanned.ranges;
    _scannedText[lineIndex] = text;
    _stateAfterLine[lineIndex] = scanned.endState;

    if (_ranges.length > _maxTrackedLines) {
      _ranges.clear();
      _scannedText.clear();
    }
    if (_stateAfterLine.length > _maxTrackedLines) {
      _stateAfterLine.clear();
    }

    return scanned.ranges;
  }

  /// The construct the line above [lineIndex] left open, walking forward from
  /// the last known boundary when the exact one is not remembered yet.
  int _stateBeforeLine(int lineIndex, String Function(int lineIndex) lineText) {
    if (lineIndex == _walkedLine + 1) return _stateAfterWalk;
    if (lineIndex > _walkedLine + 1) return _walkForward(lineIndex, lineText);

    // Asked for a line the walk has already passed. A remembered boundary
    // answers this outright; without one the file has to be walked from the
    // top, which only happens after the maps have been dropped.
    final remembered = _stateAfterLine[lineIndex - 1];
    if (remembered != null) return remembered;
    _resetWalk();
    return _walkForward(lineIndex, lineText);
  }

  int _walkForward(int lineIndex, String Function(int lineIndex) lineText) {
    while (_walkedLine < lineIndex - 1) {
      final next = _walkedLine + 1;
      _stateAfterWalk = _scan(lineText(next), _stateAfterWalk).endState;
      _stateAfterLine[next] = _stateAfterWalk;
      _walkedLine = next;
    }
    return _stateAfterWalk;
  }

  /// Classifies one line given the state left by the line above, and reports
  /// the state the line leaves behind.
  ({List<MultilineStringRange> ranges, int endState}) _scan(
    String line,
    int state,
  ) {
    if (state != _closed) {
      // The line continues a construct from above, so all of it belongs to
      // that construct until the matching closer turns up.
      final closer = spec.closers[state];
      final closeAt = _indexOfCloser(line, 0, closer);
      if (closeAt < 0) {
        return (
          ranges: <MultilineStringRange>[
            MultilineStringRange(0, line.length, spec.scopeKeys[state]),
          ],
          endState: state,
        );
      }
      return (
        ranges: <MultilineStringRange>[
          MultilineStringRange(
            0,
            math.min(closeAt + closer.length, line.length),
            spec.scopeKeys[state],
          ),
        ],
        endState: _closed,
      );
    }

    final ranges = <MultilineStringRange>[];
    var index = 0;

    while (index < line.length) {
      if (_startsWithAny(line, index, spec.lineComments)) {
        // The remainder of the line is a comment, so nothing structural
        // follows on it.
        break;
      }

      var matched = false;
      for (var open = 0; open < spec.openers.length; open++) {
        final opener = spec.openers[open];
        if (!line.startsWith(opener, index)) continue;

        final start = _includeSpecifierPrefix(line, index);
        final closer = spec.closers[open];
        final closeAt = _indexOfCloser(line, index + opener.length, closer);

        if (closeAt < 0) {
          ranges.add(
            MultilineStringRange(start, line.length, spec.scopeKeys[open]),
          );
          return (ranges: ranges, endState: open);
        }

        final end = math.min(closeAt + closer.length, line.length);
        ranges.add(MultilineStringRange(start, end, spec.scopeKeys[open]));
        index = end;
        matched = true;
        break;
      }
      if (matched) continue;

      final char = line[index];
      if (spec.singleQuotes.contains(char)) {
        final closeAt = _indexOfCloser(line, index + 1, char);
        index = closeAt < 0 ? line.length : closeAt + 1;
        continue;
      }

      index++;
    }

    return (ranges: ranges, endState: _closed);
  }

  int _indexOfCloser(String text, int from, String closer) {
    var index = from < 0 ? 0 : from;
    final lastStart = text.length - closer.length;

    while (index <= lastStart) {
      if (spec.escapes && text.codeUnitAt(index) == _backslash) {
        index += 2;
        continue;
      }
      if (text.startsWith(closer, index)) return index;
      index++;
    }

    return -1;
  }

  /// Widens [start] backwards over a run of permitted prefix letters so the
  /// specifier of a prefixed literal is painted as part of the string, the
  /// way the per-line grammar paints it.
  int _includeSpecifierPrefix(String line, int start) {
    final letters = spec.prefixLetters;
    if (letters == null) return start;

    var begin = start;
    while (begin > 0 && letters.contains(line[begin - 1])) {
      begin--;
    }
    if (begin == start) return start;
    if (begin > 0 && _isWordChar(line[begin - 1])) {
      // Something word-shaped precedes the letters, so this is an ordinary
      // word that happens to end in a specifier letter.
      return start;
    }
    return begin;
  }

  static const int _backslash = 0x5C;

  static bool _isWordChar(String char) {
    final code = char.codeUnitAt(0);
    final lower = code | 0x20;
    return (lower >= 0x61 && lower <= 0x7a) ||
        (code >= 0x30 && code <= 0x39) ||
        char == '_';
  }

  static bool _startsWithAny(String line, int index, List<String> candidates) {
    for (final candidate in candidates) {
      if (line.startsWith(candidate, index)) return true;
    }
    return false;
  }
}
