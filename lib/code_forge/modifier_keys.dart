import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What the most recent Alt key event we actually received reported.
enum _AltEvent { none, down, up }

/// Decides whether Alt is really held, repairing the framework's key cache.
///
/// `HardwareKeyboard.instance.isAltPressed` answers from `_pressedKeys`, a map
/// the framework adds to on key down and removes from on key up
/// (`handleKeyEvent` in the framework's `hardware_keyboard.dart`). Nothing ever
/// revalidates it against the OS, so a key-up that never arrives leaves the
/// entry behind for the rest of the session. Losing a key-up is routine on
/// Windows - Alt held while the window loses focus, Alt+Tab, a combination
/// swallowed by the system menu - and a pointer event carries no modifier bits
/// of its own, so the click inherits the stale "Alt is down" and silently
/// becomes an alt-click.
///
/// The engine tracks the keyboard independently and answers `getKeyboardState`
/// over the `flutter/keyboard` channel (the same channel the framework's own
/// `HardwareKeyboard.syncKeyboardState` uses, so it is available wherever that
/// is). Consulting it repairs the cache - but only if the answer is *newer*
/// than what we already know.
///
/// That freshness is the whole design. The engine cannot be trusted blindly:
///
///  * a channel round-trip takes time, and a click that arrives in between must
///    still see a genuine alt-click working, so an answer obtained before the
///    newest Alt key-down must not veto the framework's fresh reading;
///  * conversely an answer obtained after that key-down is proof the modifier
///    came back up, and must win over the cache that still claims otherwise.
///
/// So every Alt key event stamps a generation, every engine answer records the
/// generation it was requested at, and an answer only outranks the framework
/// when it is at least as new. This is what makes a lost key-up recoverable
/// without breaking Alt+Click, which a plain "always trust the engine" reading
/// does: that version intermittently drops real alt-clicks while the channel
/// is in flight.
///
/// [isAltPressed] is synchronous because pointer handlers cannot await.
class EditorModifierKeys {
  EditorModifierKeys();

  static const _channelName = 'flutter/keyboard';
  static const _getKeyboardState = 'getKeyboardState';

  /// USB HID usages of the two Alt keys.
  ///
  /// The engine reports `getKeyboardState` as a map keyed by physical key
  /// code, so membership is tested against these usages rather than against
  /// the [PhysicalKeyboardKey] values themselves.
  static final _altPhysicalKeys = {
    PhysicalKeyboardKey.altLeft.usbHidUsage,
    PhysicalKeyboardKey.altRight.usbHidUsage,
  };

  final _methodChannel = const MethodChannel(_channelName);

  /// Alt state as last reported by the engine, or `null` if never answered.
  bool? _engineAltPressed;

  /// The [_gen] the current [_engineAltPressed] was requested at. `-1` means
  /// there is no answer to weigh.
  int _engineAnswerGen = -1;

  /// Set when the platform does not implement the channel, so the class stops
  /// querying and callers fall back to the framework cache for good.
  bool _engineUnavailable = false;

  /// What the newest Alt key event said. A key-up we received is trustworthy;
  /// the *absence* of one is not.
  _AltEvent _lastAltEvent = _AltEvent.none;

  /// The [_gen] at which [_lastAltEvent] was observed.
  int _altEventGen = 0;

  /// Monotonic counter, bumped on every Alt key event.
  int _gen = 0;

  bool _queryInFlight = false;
  bool _queryAgain = false;
  bool _disposed = false;

  /// Whether the engine has confirmed a modifier state at least once.
  bool get hasEngineState => _engineAltPressed != null;

  /// Whether the engine could not be consulted on this platform.
  bool get isEngineUnavailable => _engineUnavailable;

  /// The Alt state to believe right now.
  ///
  /// Resolution order, strongest evidence first:
  ///
  ///  1. A key-up we actually received. Alt cannot be held without a newer
  ///     key-down, and that would have replaced this.
  ///  2. An engine answer taken at or after the newest Alt key event - the
  ///     only evidence that can overturn the framework's cache, and the
  ///     repair for a key-up that was lost.
  ///  3. The framework's cache, i.e. "Alt really is down" when its last word
  ///     was a key-down, so a genuine alt-click keeps working even while the
  ///     channel is still in flight.
  bool get isAltPressed {
    if (_lastAltEvent == _AltEvent.up) return false;

    if (_engineAltPressed != null && _engineAnswerGen >= _altEventGen) {
      return _engineAltPressed!;
    }

    if (_lastAltEvent == _AltEvent.down) return true;

    return HardwareKeyboard.instance.isAltPressed;
  }

  /// Feeds a key event in, keeping the framework cache and engine answer in
  /// step.
  ///
  /// Safe on every key event: an in-flight query is not duplicated, and a
  /// request arriving mid-query is folded into one follow-up pass. Called by
  /// [EditorModifierKeysObserver] for each event the framework delivers.
  void observeKeyEvent(KeyEvent event) {
    if (!_altPhysicalKeys.contains(event.physicalKey.usbHidUsage)) return;

    _gen++;
    _lastAltEvent = event is KeyUpEvent ? _AltEvent.up : _AltEvent.down;
    _altEventGen = _gen;

    // Any Alt key event is a chance the modifier changed without the
    // framework noticing, so re-read the engine.
    unawaited(sync());
  }

  /// Asks the engine whether Alt is really held and caches the answer.
  ///
  /// Returns `null` when the engine cannot be consulted. Note that even a
  /// successful answer does not necessarily become the state [isAltPressed]
  /// reports: an answer older than the newest Alt key event is stale and is
  /// ignored.
  Future<bool?> sync() async {
    if (_disposed || _engineUnavailable) return null;
    if (_queryInFlight) {
      _queryAgain = true;
      return _engineAltPressed;
    }
    _queryInFlight = true;
    // Stamp the answer with the state as of the moment it was requested, so a
    // reply that arrives after a newer Alt key event can be recognised as
    // describing an older moment.
    final requestedAtGen = _gen;
    try {
      final pressed = await _methodChannel.invokeMapMethod<int, int>(
        _getKeyboardState,
      );
      if (_disposed) return null;
      if (pressed == null) {
        // A null map means the engine supports the channel but reports nothing
        // held. Treating that as "no modifiers" is what repairs a stale cache.
        _engineAltPressed = false;
      } else {
        _engineAltPressed = pressed.keys.any(_altPhysicalKeys.contains);
      }
      _engineAnswerGen = requestedAtGen;
      return _engineAltPressed;
    } on MissingPluginException {
      _engineUnavailable = true;
      return null;
    } on PlatformException {
      _engineUnavailable = true;
      return null;
    } finally {
      _queryInFlight = false;
      if (_queryAgain) {
        _queryAgain = false;
        unawaited(sync());
      }
    }
  }

  /// Drops the cached answer so the next read is re-derived.
  ///
  /// Used when the app resumes, where the cached answer is least
  /// trustworthy, followed by a [sync] to repopulate it.
  void invalidate() {
    _engineAltPressed = null;
    _engineAnswerGen = -1;
  }

  /// Call when the host window regains focus.
  ///
  /// This is the case the whole mechanism exists for: Alt held while focus
  /// left means the framework never sees the key-up, so its cache is wrong the
  /// moment the user comes back. The answer is dropped *synchronously* so the
  /// click that follows cannot read the state that was true while the window
  /// was in the background, then re-read from the engine.
  void onWindowFocus() {
    invalidate();
    unawaited(sync());
  }

  /// Call when the host window loses focus.
  ///
  /// Modifiers are often still held as focus leaves. Re-reading now means the
  /// first click back in the window is judged against the OS view rather than a
  /// cache that is about to go stale.
  void onWindowBlur() {
    unawaited(sync());
  }

  void dispose() {
    _disposed = true;
  }

  /// Returns the tracker to its initial state.
  ///
  /// The shared [editorModifierKeys] instance is process-wide, so a test that
  /// feeds it key events would otherwise leak generations into the next test.
  @visibleForTesting
  void resetForTesting() {
    _disposed = false;
    _engineAltPressed = null;
    _engineAnswerGen = -1;
    _engineUnavailable = false;
    _lastAltEvent = _AltEvent.none;
    _altEventGen = 0;
    _gen = 0;
    _queryInFlight = false;
    _queryAgain = false;
  }
}

/// A single shared [EditorModifierKeys] for the editor surface.
///
/// Modifier state is global - one keyboard, one answer - so every editor
/// reads the same tracker rather than issuing competing engine queries.
final EditorModifierKeys editorModifierKeys = EditorModifierKeys();

/// Keeps [editorModifierKeys] in step with the app lifecycle and the keyboard.
///
/// Every signal that could have hidden a lost key-up is wired up here, so
/// [EditorModifierKeys.isAltPressed] is corrected before a click can misread
/// it. The editor surface owns an instance: it observes app lifecycle as a
/// [WidgetsBindingObserver] and receives raw key events through
/// [HardwareKeyboard.addHandler]. The host application calls
/// [EditorModifierKeys.onWindowFocus] and [EditorModifierKeys.onWindowBlur]
/// from its own window listener, because this package deliberately does not
/// depend on a window-management plugin.
class EditorModifierKeysObserver extends WidgetsBindingObserver {
  /// Starts observing. Safe to call once; repeated calls are ignored.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    // Judge the very first click correctly rather than trusting a cache that
    // has never been checked.
    unawaited(editorModifierKeys.sync());
  }

  /// Stops observing.
  void detach() {
    if (!_attached) return;
    _attached = false;
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
  }

  bool _attached = false;

  /// Never claims the event: this only watches, and swallowing keys here would
  /// break shortcuts.
  bool _onKeyEvent(KeyEvent event) {
    // Any key event means the user touched the keyboard, and Alt may have come
    // up without the framework noticing. This keeps the answer fresh without
    // polling on a timer.
    editorModifierKeys.observeKeyEvent(event);
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Alt+Tab and other focus round-trips are where key-up messages go
      // missing. Re-read the engine before the user can click.
      editorModifierKeys.onWindowFocus();
    }
  }
}
