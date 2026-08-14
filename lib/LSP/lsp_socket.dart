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

  LspSocketConfig({
    required super.workspacePath,
    required super.languageId,
    required this.serverUrl,
    super.capabilities,
    super.initializationOptions,
    super.workspaceConfiguration,
    super.disableWarning,
    super.disableError,
  }) : _channel = WebSocketChannel.connect(Uri.parse(serverUrl));

  /// This method is used to initialize the LSP server. and it's used internally by the [CodeCrafter] widget.
  /// Calling it directly is not recommended and may crash the LSP server if called multiple times.
  Future<void> connect() async {
    _channel.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String);
          if (json is! Map) throw const FormatException('Expected JSON object');
          _handleResponse(Map<String, dynamic>.from(json));
        } catch (error, stackTrace) {
          _failPendingRequests(error, stackTrace);
        }
      },
      onError: _failPendingRequests,
      onDone: () => _failPendingRequests(StateError('LSP socket closed')),
    );
  }

  @override
  Future<Map<String, dynamic>> _sendRequestOnce({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final id = _nextId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final responseFuture = _waitForResponse(id);
    _channel.sink.add(jsonEncode(request));
    return responseFuture;
  }

  @override
  Future<void> sendNotification({
    required String method,
    required Map<String, dynamic> params,
  }) async {
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
  void dispose() {
    _channel.sink.close();
    _failPendingRequests(StateError('LSP socket disposed'));
    _responseController.close();
  }
}
