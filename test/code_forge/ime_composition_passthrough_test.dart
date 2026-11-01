import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression net for the IME composition key gate.
///
/// While the platform IME owns a composition the editor's focus handler
/// answers [KeyEventResult.skipRemainingHandlers] for the pass-through keys
/// ([kImeCompositionPassThroughKeys]): remaining framework handlers are
/// skipped — the app-level shortcut tables that would consume plain arrows as
/// scroll or focus traversal never see the event — while the event itself is
/// still reported unhandled, so the embedder forwards it to the input method
/// (candidate navigation, expanding the candidate window with the down arrow).
///
/// These tests avoid CodeForgeController on purpose: they reproduce the
/// focus/gate structure with a stand-in so they run without the native Rust
/// library. flutter_test cannot simulate keys on macOS, so the apps are
/// pumped on linux (ScrollIntent branch of the default table); the macOS
/// DirectionalFocusIntent branch is reproduced explicitly by its own test.
void main() {
  late FocusNode editorFocus;
  late ValueNotifier<bool> composing;

  Widget buildEditorStandIn() {
    return Focus(
      focusNode: editorFocus,
      onKeyEvent: (node, event) {
        // Mirrors the real editor: during composition navigation keys are
        // skipped-but-unhandled so the IME can drive the session, everything
        // else is ignored; outside composition the editor acts on navigation
        // keys itself.
        if (composing.value) {
          if (kImeCompositionPassThroughKeys.contains(event.logicalKey)) {
            return KeyEventResult.skipRemainingHandlers;
          }
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final navigationKeys = <LogicalKeyboardKey>{
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.pageUp,
            LogicalKeyboardKey.pageDown,
            LogicalKeyboardKey.home,
            LogicalKeyboardKey.end,
          };
          if (navigationKeys.contains(event.logicalKey)) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: const SizedBox(width: 100, height: 40),
    );
  }

  setUp(() {
    editorFocus = FocusNode();
    composing = ValueNotifier<bool>(false);
  });

  tearDown(() {
    editorFocus.dispose();
    composing.dispose();
  });

  Future<bool> pressArrowDown(WidgetTester tester) {
    return simulateKeyDownEvent(
      LogicalKeyboardKey.arrowDown,
      platform: 'linux',
    );
  }

  testWidgets('arrow keys leave the framework unhandled during composition', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              buildEditorStandIn(),
              for (final i in List<int>.generate(40, (i) => i))
                ListTile(title: Text('line $i')),
            ],
          ),
        ),
      ),
    );
    editorFocus.requestFocus();
    await tester.pump();

    composing.value = true;
    await tester.pump();

    // False = the framework reports the key unhandled, so the embedder
    // forwards it to the IME like a native text view.
    final result = await pressArrowDown(tester);
    debugDefaultTargetPlatformOverride = null;
    expect(result, isFalse);
  });

  testWidgets('without the gate the app-level shortcuts consume the key', (
    tester,
  ) async {
    // Reproduces the reported bug: composition active, but the handler
    // answers plain `ignored` like the pre-fix editor did, so the app-level
    // default shortcuts (ScrollIntent on linux/windows, DirectionalFocus on
    // macOS) swallow the arrow.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Focus(
                focusNode: editorFocus,
                onKeyEvent: (node, event) => KeyEventResult.ignored,
                child: const SizedBox(width: 100, height: 40),
              ),
              for (final i in List<int>.generate(40, (i) => i))
                ListTile(title: Text('line $i')),
            ],
          ),
        ),
      ),
    );
    editorFocus.requestFocus();
    await tester.pump();

    final result = await pressArrowDown(tester);
    debugDefaultTargetPlatformOverride = null;
    expect(result, isTrue);
  });

  testWidgets(
    'macOS-style focus traversal shortcuts cannot eat the key either',
    (tester) async {
      // Reproduces the macOS app table, where plain arrows map to
      // DirectionalFocusIntent instead of ScrollIntent, above the gated
      // editor and verifies the gate still shields the IME.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(
        Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
          },
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  buildEditorStandIn(),
                  for (final i in List<int>.generate(40, (i) => i))
                    ListTile(title: Text('line $i')),
                ],
              ),
            ),
          ),
        ),
      );
      editorFocus.requestFocus();
      await tester.pump();

      composing.value = true;
      await tester.pump();

      final result = await pressArrowDown(tester);
      debugDefaultTargetPlatformOverride = null;
      expect(result, isFalse);
    },
  );

  testWidgets('the editor still owns navigation keys outside composition', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              buildEditorStandIn(),
              for (final i in List<int>.generate(40, (i) => i))
                ListTile(title: Text('line $i')),
            ],
          ),
        ),
      ),
    );
    editorFocus.requestFocus();
    await tester.pump();

    expect(composing.value, isFalse);
    final result = await pressArrowDown(tester);
    debugDefaultTargetPlatformOverride = null;
    expect(result, isTrue);
  });
}
