import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'bridge_script.dart';

/// The browser surface that displays chapters for a `ReaderController`.
///
/// [WebViewReaderSurface] implements it with `webview_flutter`. Other
/// implementations, such as test doubles or another WebView plugin, must run
/// scripts in the page's main world and deliver [readerChannelName] messages.
abstract interface class ReaderSurface {
  /// Called with each JSON message the page posts to [readerChannelName].
  set onMessage(void Function(String message)? callback);

  /// Called when a document has finished loading, with its URL.
  set onPageFinished(void Function(Uri url)? callback);

  /// Decides whether the surface may navigate to a URL.
  set onNavigationRequest(bool Function(Uri url)? callback);

  /// Loads [url] in the main frame.
  Future<void> load(Uri url);

  /// Reloads the current document from the network.
  Future<void> reload();

  /// Runs [script] in the page without a result.
  Future<void> run(String script);

  /// Evaluates [expression], which must produce a JSON string, and returns the
  /// decoded value.
  Future<Object?> evaluate(String expression);

  /// Sets the color shown before and around the page.
  Future<void> setBackgroundColor(Color color);
}

/// A [ReaderSurface] backed by a `webview_flutter` [WebViewController].
///
/// JavaScript is enabled so the host can inject the reader scripts; the
/// render session's Content Security Policy and script removal keep
/// publication scripts from running. Android file and content access are
/// disabled, and navigation outside the session is decided by
/// [onNavigationRequest].
final class WebViewReaderSurface implements ReaderSurface {
  /// Creates a surface with a new WebView controller.
  WebViewReaderSurface() : webViewController = _createController() {
    unawaited(_configured);
  }

  /// The controller displayed by a `WebViewWidget`.
  final WebViewController webViewController;

  void Function(String message)? _onMessage;
  void Function(Uri url)? _onPageFinished;
  bool Function(Uri url)? _onNavigationRequest;
  late final Future<void> _configured = _configureOnce();

  @override
  set onMessage(void Function(String message)? callback) =>
      _onMessage = callback;

  @override
  set onPageFinished(void Function(Uri url)? callback) =>
      _onPageFinished = callback;

  @override
  set onNavigationRequest(bool Function(Uri url)? callback) =>
      _onNavigationRequest = callback;

  static WebViewController _createController() {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    return WebViewController.fromPlatformCreationParams(params);
  }

  Future<void> _configureOnce() async {
    final controller = webViewController;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      readerChannelName,
      onMessageReceived: (message) => _onMessage?.call(message.message),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          final allowed =
              uri != null && (_onNavigationRequest?.call(uri) ?? false);
          return allowed
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageFinished: (url) {
          final uri = Uri.tryParse(url);
          if (uri != null) _onPageFinished?.call(uri);
        },
      ),
    );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setAllowFileAccess(false);
      await platform.setAllowContentAccess(false);
    }
  }

  @override
  Future<void> load(Uri url) async {
    await _configured;
    await webViewController.loadRequest(url);
  }

  @override
  Future<void> reload() async {
    await _configured;
    await webViewController.reload();
  }

  @override
  Future<void> run(String script) async {
    await _configured;
    await webViewController.runJavaScript(script);
  }

  @override
  Future<Object?> evaluate(String expression) async {
    await _configured;
    final result = await webViewController.runJavaScriptReturningResult(
      expression,
    );
    return decodeScriptResult(result);
  }

  @override
  Future<void> setBackgroundColor(Color color) =>
      webViewController.setBackgroundColor(color);
}

/// Decodes the result of evaluating a JSON-string expression.
///
/// WebKit returns the string itself, while Android returns it JSON-encoded.
Object? decodeScriptResult(Object? result) {
  if (result is! String) return result;
  Object? decoded;
  try {
    decoded = jsonDecode(result);
  } on FormatException {
    return result;
  }
  if (decoded is String) {
    try {
      return jsonDecode(decoded);
    } on FormatException {
      return decoded;
    }
  }
  return decoded;
}
