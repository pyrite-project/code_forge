import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Click-gesture tests for the desktop pointer-down path: a double click
/// selects the word under the caret, a triple click selects the whole line.
///
/// Both gestures are recognized by state kept in the editor itself (Flutter
/// has no triple-tap recognizer, and the editor's double-tap recognizer is fed
/// by hand), so they compete with each other. These tests drive real pointer
/// events through the widget so that competition is exercised, not mocked.
///
/// [debugDefaultTargetPlatformOverride] is pinned to desktop because the
/// editor picks its pointer-down branch from `defaultTargetPlatform`, which
/// the test binding otherwise reports as Android; that would run these cases
/// against the mobile branch they are not written for.

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

  /// Runs [body] with [debugDefaultTargetPlatformOverride] pinned to desktop.
  ///
  /// The override has to be set and cleared inside the test body: the framework
  /// asserts it is unset at the end of every test, so neither a suite-level
  /// [setUpAll] nor a [tearDown] is early enough.
  Future<void> onDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

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

  /// A press with a mouse pointer: [tester.tapAt] always speaks touch, and the
  /// editor gates its double-tap recognizer per pointer kind, so the mouse
  /// path needs its own tap.
  Future<void> mouseTapAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
  }

  /// Two mouse presses at [first] and [second], inside the double-tap window.
  Future<void> mouseClickTwice(
    WidgetTester tester,
    Offset first,
    Offset second,
  ) async {
    await mouseTapAt(tester, first);
    await tester.pump(const Duration(milliseconds: 120));
    await mouseTapAt(tester, second);
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('double click selects the word under the caret', (tester) async {
    await onDesktop(() async {
      final dx = await dxOfWord(tester, 'beta');
      final position = await positionOn(tester, dx);

      await clickTwice(tester, position);

      expect(selectedText(), 'beta');
    });
  });

  testWidgets('triple click selects the whole line', (tester) async {
    await onDesktop(() async {
      final dx = await dxOfWord(tester, 'beta');
      final position = await positionOn(tester, dx);

      await clickTwice(tester, position);
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 120));

      expect(selectedText(), 'alpha beta gamma');
    });
  });

  testWidgets('a slow fourth click starts a fresh single click', (
    tester,
  ) async {
    await onDesktop(() async {
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
  });

  testWidgets('a mouse click far from the previous one stays a single click', (
    tester,
  ) async {
    await onDesktop(() async {
      final dx = await dxOfWord(tester, 'beta');
      final position = await positionOn(tester, dx);

      // 40 logical px apart: inside the framework's 100px pairing radius but
      // on a different word, so a mouse pair this far apart must not read as
      // a double tap.
      await mouseClickTwice(tester, position, position + const Offset(40, 0));

      expect(controller.selection.isCollapsed, isTrue);
    });
  });

  testWidgets(
    'a mouse double click a few pixels apart still selects the word',
    (tester) async {
      await onDesktop(() async {
        final dx = await dxOfWord(tester, 'beta');
        final position = await positionOn(tester, dx);

        await mouseClickTwice(tester, position, position + const Offset(4, 0));

        expect(selectedText(), 'beta');
      });
    },
  );

  testWidgets(
    'a single click elsewhere does not block a following double click',
    (tester) async {
      await onDesktop(() async {
        final dxBeta = await dxOfWord(tester, 'beta');
        final dxGamma = await dxOfWord(tester, 'gamma');
        final position = await positionOn(tester, dxBeta);
        final gammaPosition = position + Offset(dxGamma - dxBeta, 0);

        // Clicking once to place the caret is the common prelude to a double
        // click on a different word. The double click's first press lands far
        // from that single click, which must not stop it from opening a pair.
        await mouseTapAt(tester, position);
        // The fake clock only advances the framework's double-tap timer; the
        // editor's triple-tap detection reads the real clock, so a real wait
        // is what separates the single click from the double click.
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        );
        await mouseClickTwice(tester, gammaPosition, gammaPosition);

        expect(selectedText(), 'gamma');
      });
    },
  );

  testWidgets('touch taps keep pairing across the framework radius', (
    tester,
  ) async {
    await onDesktop(() async {
      final dxBeta = await dxOfWord(tester, 'beta');
      final dxGamma = await dxOfWord(tester, 'gamma');
      final position = await positionOn(tester, dxBeta);
      final gammaPosition = position + Offset(dxGamma - dxBeta, 0);

      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(gammaPosition);
      await tester.pump(const Duration(milliseconds: 120));

      // The second tap is on another word tens of px away: only the
      // framework's touch-sized pairing radius makes this a double tap.
      expect(controller.selection.isCollapsed, isFalse);
    });
  });
}
