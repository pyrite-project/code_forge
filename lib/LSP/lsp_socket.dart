part of 'lsp.dart';

/// A configuration class for Language Server Protocol (LSP) using WebSocket communication.
///
/// Documenation available [here](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/LSPClient.md).
///
///Example:
/// create a [LspSocketConfig] object and pass it to the [CodeForge] widget.
///
///```dart
///final lspConfig = LspSocketConfig(
///    workspacePath: "/home/athul/Projects/lsp",
///    languageId: "python",
///    serverUrl: "ws://localhost:5656"
///),
///```
///Then pass the `lspConfig` instance to the `CodeForge` widget:
///
///```dart
///CodeForge(
///    controller: controller,
///    theme: anOldHopeTheme,
///    lspConfig: lspConfig, // Pass the LSP config here
///),
///```
class LspSocketConfig extends LspConfig {
  /// The URL of the LSP server to connect to via WebSocket.
  final String serverUrl;
  final WebSocketChannel _channel;
  bool _streamListening = false;
  Object? _connectionError;
  StackTrace? _connectionStackTrace;

  /// Set when the connection ended without [dispose] — a dropped server. It
  /// also makes [isUsable] false, so a host holding pooled configs replaces
  /// the dead transport instead of handing it to every later editor.
  bool _closed = false;

  /// Set by [dispose] so the stream's onDone can tell a deliberate stop from
  /// a drop; only the latter triggers [onUnexpectedExit].
  bool _disposedByClient = false;

  LspSocketConfig({
    required super.workspacePath,
    required super.languageId,
    required this.serverUrl,
    super.capabilities,
    super.initializationOptions,
    super.workspaceConfiguration,
    super.disableWarning,
    super.disableError,
  }) : _channel = WebSocketChannel.connect(Uri.parse(serverUrl)) {
    // web_socket_channel exposes connection failures through both `ready` and
    // the stream. Observe `ready` even when a caller never reaches connect()
    // so a refused endpoint cannot become an unhandled Future error.
    unawaited(_observeReady());
  }

  Future<void> _observeReady() async {
    try {
      await _channel.ready;
    } catch (error, stackTrace) {
      _connectionError = error;
      _connectionStackTrace = stackTrace;
      _failPendingRequests(error, stackTrace);
    }
  }

  /// This method is used to initialize the LSP server. and it's used internally by the [CodeCrafter] widget.
  /// Calling it directly is not recommended and may crash the LSP server if called multiple times.
  Future<void> connect() async {
    if (!_streamListening) {
      _streamListening = true;
      _channel.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String);
            if (json is! Map) {
              throw const FormatException('Expected JSON object');
            }
            _handleResponse(Map<String, dynamic>.from(json));
          } catch (error, stackTrace) {
            _failPendingRequests(error, stackTrace);
          }
        },
        onError: _failPendingRequests,
        onDone: () {
          _closed = true;
          _failPendingRequests(StateError('LSP socket closed'));
          if (!_disposedByClient) {
            onUnexpectedExit?.call();
          }
        },
      );
    }
    try {
      await _channel.ready;
    } catch (error, stackTrace) {
      _connectionError = error;
      _connectionStackTrace = stackTrace;
      _failPendingRequests(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
    final error = _connectionError;
    if (error != null) {
      Error.throwWithStackTrace(
        error,
        _connectionStackTrace ?? StackTrace.current,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> _sendRequestOnce({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    _ensureHandshakeAllows(method);
    final id = _nextId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final responseFuture = _waitForResponse(id);
    // The connection can drop while the write below is still in flight,
    // completing the response future before the await at the bottom observes
    // it; mark it ignored so that window never surfaces as an unhandled
    // exception.
    responseFuture.ignore();
    _channel.sink.add(jsonEncode(request));
    return await responseFuture;
  }

  @override
  Future<void> sendNotification({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    _ensureHandshakeAllows(method);
    _channel.sink.add(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
  }

  @override
  Future<Map<String, dynamic>> sendResponse(
    int id,
    List<dynamic> result,
  ) async {
    final request = {'jsonrpc': '2.0', 'id': id, "result": result};

    _channel.sink.add(jsonEncode(request));
    return request;
  }

  @override
  bool get isUsable => !_closed && _connectionError == null;

  @override
  void dispose() {
    _disposedByClient = true;
    _closed = true;
    _channel.sink.close();
    _failPendingRequests(StateError('LSP socket disposed'));
    _responseController.close();
  }
}
