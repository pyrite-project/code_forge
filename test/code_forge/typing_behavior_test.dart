import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Typing-behavior tests for the controller's insertion funnel: Python
/// block-end dedent, auto-pairing suppression, and selection wrapping.
///
/// The Rust-backed rope needs `code_forge.dll`; when it cannot be loaded the
/// suite is skipped so CI without a built runtime stays green.

/// Exposes the controller's protected delta funnel to the tests: the funnel
/// is what the platform IME connection feeds on real keystrokes, and the
/// tests need to drive it without a mounted text-input connection.
class _TypingController extends CodeForgeController {
  void sendDeltas(List<TextEditingDelta> deltas) =>
      updateEditingValueWithDeltas(deltas);
}

void main() {
  Future<bool> rustReady() async {
    try {
      await RustLib.init();
      return true;
    } catch (error) {
      // ignore: avoid_print
      print('RustLib.init failed: $error');
      return false;
    }
  }

  late bool rust;

  setUpAll(() async {
    rust = await rustReady();
    if (!rust) {
      // Loud, not silent: a skipped suite looks exactly like a green one, and
      // these tests once "passed" for weeks without ever running.
      // ignore: avoid_print
      print(
        '!!! typing_behavior_test SKIPPED: code_forge.dll not loadable '
        '(copy it next to the package root to run these tests) !!!',
      );
    }
  });

  _TypingController controller(String text) {
    final c = _TypingController();
    c.useSpaceAsTab = true;
    c.tabSize = 4;
    c.text = text;
    return c;
  }

  /// Types [chars] at the caret through the same delta funnel the platform
  /// IME connection feeds on real keystrokes.
  void type(_TypingController c, String chars) {
    for (final ch in chars.split('')) {
      final offset = c.selection.extentOffset;
      c.sendDeltas([
        TextEditingDeltaInsertion(
          oldText: c.text,
          textInserted: ch,
          insertionOffset: offset,
          selection: TextSelection.collapsed(offset: offset + 1),
          composing: TextRange.empty,
        ),
      ]);
    }
  }

  Future<void> replaceSelection(_TypingController c, String replacement) async {
    final selection = c.selection;
    c.sendDeltas([
      TextEditingDeltaReplacement(
        oldText: c.text,
        replacedRange: TextRange(start: selection.start, end: selection.end),
        replacementText: replacement,
        selection: TextSelection.collapsed(offset: selection.start + 1),
        composing: TextRange.empty,
      ),
    ]);
  }

  test('Enter after return dedents one level when Python hints are on', () {
    if (!rust) return;
    final c = controller('def f():\n    if x:\n        return x');
    c.autoDedentAfterBlockEnd = true;
    addTearDown(c.dispose);
    c.setSelectionSilently(TextSelection.collapsed(offset: c.length));
    type(c, '\n');
    expect(c.text, 'def f():\n    if x:\n        return x\n    ');
  });

  test(
    'Enter after return keeps the statement indent without Python hints',
    () {
      if (!rust) return;
      final c = controller('def f():\n    if x:\n        return x');
      addTearDown(c.dispose);
      c.setSelectionSilently(TextSelection.collapsed(offset: c.length));
      type(c, '\n');
      expect(c.text, 'def f():\n    if x:\n        return x\n        ');
    },
  );

  test('Enter after a colon still opens a block at the next level', () {
    if (!rust) return;
    final c = controller('def f():');
    c.autoDedentAfterBlockEnd = true;
    addTearDown(c.dispose);
    c.setSelectionSilently(TextSelection.collapsed(offset: c.length));
    type(c, '\n');
    expect(c.text, 'def f():\n    ');
  });

  test('typing an opener inserts its closer with the caret between', () {
    if (!rust) return;
    final c = controller('');
    addTearDown(c.dispose);
    type(c, '(');
    expect(c.text, '()');
    expect(c.selection.extentOffset, 1);
  });

  test("typing an apostrophe inside a word does not auto-pair", () {
    if (!rust) return;
    final c = controller("don't");
    addTearDown(c.dispose);
    c.setSelectionSilently(const TextSelection.collapsed(offset: 3));
    type(c, "'");
    expect(c.text, "don't");
    expect(c.selection.extentOffset, 4);
  });

  test('typing the third docstring quote inserts a single quote', () {
    if (!rust) return;
    final c = controller('x = ');
    addTearDown(c.dispose);
    type(c, '"""');
    expect(c.text, 'x = """');
    expect(c.selection.extentOffset, 7);
  });

  test('typing a bracket inside a comment does not auto-pair', () {
    if (!rust) return;
    final c = controller('# note');
    c.lineCommentMarkers = const ['#'];
    addTearDown(c.dispose);
    c.setSelectionSilently(TextSelection.collapsed(offset: c.length));
    type(c, '(');
    expect(c.text, '# note(');
  });

  test('typing a quote inside a comment does not auto-pair', () {
    if (!rust) return;
    final c = controller('# say ');
    c.lineCommentMarkers = const ['#'];
    addTearDown(c.dispose);
    c.setSelectionSilently(TextSelection.collapsed(offset: c.length));
    type(c, '"');
    expect(c.text, '# say "');
  });

  test('typing an opener over a selection wraps it in the pair', () {
    if (!rust) return;
    final c = controller('abc');
    addTearDown(c.dispose);
    c.setSelectionSilently(const TextSelection(baseOffset: 0, extentOffset: 3));
    replaceSelection(c, '(');
    expect(c.text, '(abc)');
    expect(c.selection.baseOffset, 1);
    expect(c.selection.extentOffset, 4);
  });

  test('typing a quote over a selection wraps it in quotes', () {
    if (!rust) return;
    final c = controller('abc');
    addTearDown(c.dispose);
    c.setSelectionSilently(const TextSelection(baseOffset: 0, extentOffset: 3));
    replaceSelection(c, '"');
    expect(c.text, '"abc"');
    expect(c.selection.baseOffset, 1);
    expect(c.selection.extentOffset, 4);
  });

  test('typing a letter over a selection still replaces it', () {
    if (!rust) return;
    final c = controller('abc');
    addTearDown(c.dispose);
    c.setSelectionSilently(const TextSelection(baseOffset: 0, extentOffset: 3));
    replaceSelection(c, 'x');
    expect(c.text, 'x');
  });
}
