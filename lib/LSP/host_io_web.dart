/// Web stubs for the `dart:io` surface used by the LSP transports and the
/// controller file helpers.
///
/// Stdio language servers and synchronous file access cannot run from a
/// browser, so every operation throws [UnsupportedError]; the app only
/// selects the WebSocket transport on the web.
library;

import 'dart:convert';

/// Process id placeholder (no processes on the web).
const int pid = 0;

/// Web stand-in for `dart:io` [Platform].
class Platform {
  Platform._();

  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
}

/// Web stand-in for `dart:io` [File]; synchronous operations throw.
class File {
  File(String path);

  static Never _unsupported(String op) => throw UnsupportedError(
        'File operation "$op" is not supported in the browser.',
      );

  Future<String> readAsString({Encoding encoding = utf8}) =>
      _unsupported('readAsString');

  String readAsStringSync() => _unsupported('readAsStringSync');

  void writeAsStringSync(String contents) => _unsupported('writeAsStringSync');

  bool existsSync() => _unsupported('existsSync');
}

/// Web stand-in for `dart:io` [ProcessResult].
class ProcessResult {
  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);

  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
}

/// Web stand-in for `dart:io` [Process]; every operation throws.
class Process {
  Process._();

  static Never _unsupported() => throw UnsupportedError(
        'Local processes are not available in the browser.',
      );

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
  }) =>
      _unsupported();

  Stream<List<int>> get stdout => _unsupported();
  Stream<List<int>> get stderr => _unsupported();
  dynamic get stdin => _unsupported();
  int get pid => _unsupported();
  Future<int> get exitCode => _unsupported();
  bool kill([int signal = 0]) => _unsupported();
}
