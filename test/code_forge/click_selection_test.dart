import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Click-gesture tests for the desktop pointer-down path: a double click
/// selects the word under the caret, a triple click selects the whole line.
///
/// Both gestures are recognized by state kept in the editor itself (Flutter
/// has no triple-tap recognizer, and the editor's double-tap recognizer is fed
/// by hand), so they compete with each other. These tests drive real pointer
/// events through the widget so that competition is exercised, not mocked.

const String _text = 'alpha beta gamma\ndelta epsilon';

void main() {
  setUpAll(() async {
    // The controller's text buffer is the Rust rope; without the runtime the
    // whole suite is unrunnable rather than silently green.
    await RustLib.init();
  });

  late CodeForgeController controller;
  var pumps = 0;

  setUp(() {
    controller = CodeForgeController();
    controller.text = _text;
    addTearDown(controller.dispose);
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    // A fresh key per pump gives the editor fresh click tracking, so the
    // calibration taps [dxOfWord] fires cannot leak into the clicks a test
    // makes afterwards.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 600,
              child: CodeForge(
                key: ValueKey(pumps++),
                controller: controller,
                readOnly: true,
              ),
            ),
          ),
        ),
      ),
    );
    // The blinking caret animates forever, so settle never returns; fixed
    // pumps are what this suite needs anyway, since the timing below is
    // measured against the fake clock.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  String selectedText() {
    final selection = controller.selection;
    return controller.text.substring(selection.start, selection.end);
  }

  /// Horizontal distance from the editor's left edge at which a click lands
  /// inside [word] on the first line.
  ///
  /// Found by asking the editor where a click lands rather than by hard-coding
  /// font metrics. Clicks are dense here, so the runs that the editor reads as
  /// double or triple taps move the selection off the caret; only the
  /// collapsed readings describe where the click actually landed.
  Future<double> dxOfWord(WidgetTester tester, String word) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(CodeForge));
    final start = _text.indexOf(word);
    final end = start + word.length;
    for (var dx = 4.0; dx < 700; dx += 2) {
      final gesture = await tester.startGesture(origin + Offset(dx, 10));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 120));
      final selection = controller.selection;
      if (selection.isCollapsed && selection.baseOffset >= start) {
        if (selection.baseOffset < end) return dx;
      }
    }
    throw StateError('no click position resolved to a click on "$word"');
  }

  /// Editor position for a click that lands on [word] of the first line.
  Future<Offset> positionOn(WidgetTester tester, double dx) async {
    await pumpEditor(tester);
    return tester.getTopLeft(find.byType(CodeForge)) + Offset(dx, 10);
  }

  Future<void> clickTwice(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('double click selects the word under the caret', (tester) async {
    final dx = await dxOfWord(tester, 'beta');
    final position = await positionOn(tester, dx);

    await clickTwice(tester, position);

    expect(selectedText(), 'beta');
  });

  testWidgets('triple click selects the whole line', (tester) async {
    final dx = await dxOfWord(tester, 'beta');
    final position = await positionOn(tester, dx);

    await clickTwice(tester, position);
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 120));

    expect(selectedText(), 'alpha beta gamma');
  });

  testWidgets('a slow fourth click starts a fresh single click', (
    tester,
  ) async {
    final dx = await dxOfWord(tester, 'beta');
    final position = await positionOn(tester, dx);

    await clickTwice(tester, position);
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 120));
    // Past the triple-click window, so this is a new gesture and the caret
    // moves instead of the selection growing.
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 120));

    expect(controller.selection.isCollapsed, isTrue);
  });
}
