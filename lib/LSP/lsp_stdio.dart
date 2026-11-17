part of 'lsp.dart';

/// This class provides a configuration for Language Server Protocol (LSP) using standard input/output communication.
/// Little bit complex compared to [LspSocketConfig].
///
/// /// Documenation available [here](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/LSPClient.md).
///
/// Example:
///
/// Create an async method to initialize the LSP configuration.
///```dart
///Future<LspConfig?> _initLsp() async {
///    try {
///      final config = await LspStdioConfig.start(
///        executable: '/home/athul/.nvm/versions/node/v20.19.2/bin/pyright-langserver',
///        args: ['--stdio']
///        workspacePath: '/home/athul/Projects/lsp',
///        languageId: 'python',
///      );
///
///      return config;
///    } catch (e) {
///      debugPrint('LSP Initialization failed: $e');
///      return null;
///    }
///  }
///  ```
///  Then use a `FutureBuilder` to initialize the LSP configuration and pass it to the `CodeForge` widget:
///```dart
///  @override
///  Widget build(BuildContext context) {
///    return MaterialApp(
///      home: Scaffold(
///        body: SafeArea(
///          child: FutureBuilder(
///            future: _initLsp(), // Call the async method to get the LSP config
///            builder: (context, snapshot) {
///              if(snapshot.connectionState == ConnectionState.waiting) {
///                return Center(child: CircularProgressIndicator());
///              }
///              return CodeForge(
///                wrapLines: true,
///                editorTheme: anOldHopeTheme,
///                controller: controller,
///                filePath: '/home/athul/Projects/lsp/example.py',
///                textStyle: TextStyle(fontSize: 15, fontFamily: 'monospace'),
///                lspConfig: snapshot.data, // Pass the LSP config here
///              );
///            }
///          ),
///        )
///      ),
///    );
///  }
class LspStdioConfig extends LspConfig {
  /// location of the LSP executable, such as `pyright-langserver`, `rust-analyzer`, etc.
  ///
  /// To get the `executable` path, you can use the `which` command in the terminal. For example, to get the path of the `pyright-langserver`, you can use the following command:
  ///
  ///```bash
  ///which pyright-langserver
  ///```
  final String executable;

  @override
  bool get forceFullDocumentSync => executable.contains('ccls');

  /// Optional arguments for the executable.
  final List<String>? args;

  /// Optional environement variables for the executable.
  final Map<String, String>? environment;

  late Process _process;
  final _buffer = <int>[];
  Future<void> _sendTail = Future<void>.value();

  /// Last stderr bytes the server printed, so a server that dies during
  /// startup reports why instead of surfacing only as a broken-pipe write.
  static const int _stderrTailLimit = 8 * 1024;
  final List<int> _stderrTail = <int>[];

  /// Exit code of the server process, or null while it is running.
  int? _exitCode;

  /// Set by [dispose]; only an exit that happens without it counts as a
  /// crash and triggers [onUnexpectedExit].
  bool _disposedByClient = false;

  LspStdioConfig._({
    required this.executable,
    required super.workspacePath,
    required super.languageId,
    this.args,
    this.environment,
    super.capabilities,
    super.initializationOptions,
    super.workspaceConfiguration,
    super.disableWarning,
    super.disableError,
  });

  static Future<LspStdioConfig> start({
    required String executable,
    required String workspacePath,
    required String languageId,
    LspClientCapabilities? capabilities,
    Map<String, dynamic> initializationOptions = const {},
    Map<String, dynamic> workspaceConfiguration = const {},
    List<String>? args,
    Map<String, String>? environment,
    bool disableWarning = false,
    bool disableError = false,
  }) async {
    final effectiveCapabilities = capabilities ?? LspClientCapabilities();
    final effectiveInitializationOptions = _withCclsInitializationDefaults(
      executable,
      initializationOptions,
    );

    final config = LspStdioConfig._(
      executable: executable,
      languageId: languageId,
      workspacePath: workspacePath,
      args: args,
      environment: environment,
      disableWarning: disableWarning,
      disableError: disableError,
      capabilities: effectiveCapabilities,
      initializationOptions: effectiveInitializationOptions,
      workspaceConfiguration: workspaceConfiguration,
    );
    await config._startProcess();
    return config;
  }

  static Map<String, dynamic> _withCclsInitializationDefaults(
    String executable,
    Map<String, dynamic> initializationOptions,
  ) {
    if (!executable.toLowerCase().contains('ccls')) {
      return initializationOptions;
    }

    final defaults = <String, dynamic>{
      'highlight': {'enabled': true, 'lsRanges': true},
      'index': {'onChange': true},
    };

    return _deepMergeMaps(defaults, initializationOptions);
  }

  static Map<String, dynamic> _deepMergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> overrides,
  ) {
    final merged = <String, dynamic>{};

    for (final entry in base.entries) {
      final value = entry.value;
      if (value is Map) {
        merged[entry.key] = Map<String, dynamic>.from(
          value.cast<dynamic, dynamic>(),
        );
      } else {
        merged[entry.key] = value;
      }
    }

    for (final entry in overrides.entries) {
      final existing = merged[entry.key];
      final incoming = entry.value;
      if (existing is Map && incoming is Map) {
        merged[entry.key] = _deepMergeMaps(
          Map<String, dynamic>.from(existing.cast<dynamic, dynamic>()),
          Map<String, dynamic>.from(incoming.cast<dynamic, dynamic>()),
        );
      } else {
        merged[entry.key] = incoming;
      }
    }

    return merged;
  }

  Future<void> _startProcess() async {
    _process = await Process.start(
      executable,
      args ?? [],
      environment: environment,
      workingDirectory: workspacePath,
    );
    _process.stdout.listen(
      _handleStdoutData,
      onError: _failPendingRequests,
      onDone: () => _failPendingRequests(StateError('LSP stdio closed')),
    );
    _process.stderr.listen((data) {
      // Collected but not echoed live: a crashing server (zuban's panic dump,
      // for example) prints dozens of lines per crash, and the reason reaches
      // the caller through [_serverExitMessage] anyway.
      _stderrTail.addAll(data);
      if (_stderrTail.length > _stderrTailLimit) {
        _stderrTail.removeRange(0, _stderrTail.length - _stderrTailLimit);
      }
    });
    unawaited(
      _process.exitCode.then((code) {
        _exitCode = code;
        // Wake in-flight requests with the real reason instead of leaving them
        // to time out against a process that is already gone.
        _failPendingRequests(StateError(_serverExitMessage()));
        if (!_disposedByClient) {
          onUnexpectedExit?.call();
        }
      }),
    );
  }

  String _serverExitMessage() {
    final tail = utf8.decode(_stderrTail, allowMalformed: true).trim();
    return 'LSP server process exited (code ${_exitCode ?? 'unknown'})'
        '${tail.isEmpty ? '' : ': ${_exitReasonFromTail(tail)}'}';
  }

  /// Condenses the stderr tail to the actual exit reason.
  ///
  /// A panicking server dumps its whole backtrace into stderr (zuban prints
  /// fifty-odd `<unknown>` frames per crash), and every failed request would
  /// otherwise repeat all of it. What identifies the crash is the first
  /// `panicked at` line plus the message on the next line; anything else is
  /// noise, so at most two lines — or a short prefix when the tail has no
  /// recognizable shape — reach the caller.
  String _exitReasonFromTail(String tail) {
    final lines = const LineSplitter().convert(tail);
    final panicIndex = lines.indexWhere((line) => line.contains('panicked at'));
    if (panicIndex != -1) {
      final reason = [
        lines[panicIndex],
        if (panicIndex + 1 < lines.length) lines[panicIndex + 1],
      ].join(' | ');
      return reason.length > 300 ? reason.substring(0, 300) : reason;
    }
    return tail.length > 200 ? tail.substring(0, 200) : tail;
  }

  /// Replaces a bare send failure with the server's exit reason when the
  /// process is already gone — `stdin` writes then report a broken pipe that
  /// hides what actually happened.
  Object _describeSendFailure(Object error) {
    if (_exitCode == null) return error;
    return StateError('${_serverExitMessage()} (original error: $error)');
  }

  /// Fails fast when the server has exited: a write into its stdin can still
  /// "succeed" into the kernel buffer and only time out later, so every sender
  /// checks liveness first and reports the exit reason instead.
  void _ensureServerAlive() {
    if (_exitCode != null) throw StateError(_serverExitMessage());
  }

  int get pid => _process.pid;
  Future<int> get exitCode => _process.exitCode;
  Process get process => _process;

  void _handleStdoutData(List<int> data) {
    try {
      _buffer.addAll(data);
      while (_buffer.isNotEmpty) {
        final headerEnd = _findHeaderEnd();
        if (headerEnd == -1) return;
        final header = utf8.decode(_buffer.sublist(0, headerEnd));
        final contentLength = int.parse(
          RegExp(r'Content-Length: (\d+)').firstMatch(header)?.group(1) ?? '0',
        );
        if (_buffer.length < headerEnd + 4 + contentLength) return;
        final messageStart = headerEnd + 4;
        final messageEnd = messageStart + contentLength;
        final messageBytes = _buffer.sublist(messageStart, messageEnd);
        _buffer.removeRange(0, messageEnd);
        final json = jsonDecode(utf8.decode(messageBytes));
        if (json is! Map) throw const FormatException('Expected JSON object');
        _handleResponse(Map<String, dynamic>.from(json));
      }
    } catch (error, stackTrace) {
      _failPendingRequests(error, stackTrace);
    }
  }

  int _findHeaderEnd() {
    for (var i = 0; i <= _buffer.length - 4; i++) {
      if (_buffer[i] == 13 &&
          _buffer[i + 1] == 10 &&
          _buffer[i + 2] == 13 &&
          _buffer[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  @override
  Future<Map<String, dynamic>> _sendRequestOnce({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    _ensureHandshakeAllows(method);
    _ensureServerAlive();
    final id = _nextId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final responseFuture = _waitForResponse(id);
    // The server can die while the write below is still in flight, completing
    // the response future before the await at the bottom observes it; mark it
    // ignored so that window never surfaces as an unhandled exception.
    responseFuture.ignore();

    await _sendLspMessage(request);

    return await responseFuture;
  }

  @override
  Future<void> sendNotification({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    _ensureHandshakeAllows(method);
    _ensureServerAlive();
    await _sendLspMessage({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  @override
  Future<Map<String, dynamic>> sendResponse(
    int id,
    List<dynamic> result,
  ) async {
    _ensureServerAlive();
    final request = {'jsonrpc': '2.0', 'id': id, 'result': result};
    await _sendLspMessage(request);
    return request;
  }

  Future<void> _sendLspMessage(Map<String, dynamic> message) async {
    final completer = Completer<void>();
    _sendTail = _sendTail.catchError((_) {}).then((_) async {
      try {
        final body = utf8.encode(jsonEncode(message));
        final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
        final combined = <int>[...header, ...body];
        _process.stdin.add(combined);
        await _process.stdin.flush();
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(_describeSendFailure(e), st);
        }
      }
    });

    return completer.future;
  }

  @override
  bool get isUsable => _exitCode == null;

  @override
  void dispose() {
    _disposedByClient = true;
    _failPendingRequests(StateError('LSP stdio disposed'));
    _process.kill();
    _responseController.close();
  }
}
