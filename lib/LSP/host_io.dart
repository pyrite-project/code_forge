/// Conditional process access for the LSP transports.
///
/// The default export is the web stub (used by the Flutter Web build, where
/// `dart:io` does not exist); native platforms resolve the `dart.library.io`
/// branch and get the real `dart:io`.
export 'host_io_web.dart' if (dart.library.io) 'host_io_io.dart';
