import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/bim_viewer/bim_view_engine.dart';
import '../../core/bim_viewer/viewer_asset_server.dart';

/// [BimViewEngine] over `assets/bim_viewer` (three.js, MIT) in a WebView,
/// served by a [ViewerAssetServer] on 127.0.0.1 (docs/bim-viewer.md §4).
///
/// Not the xeokit twin page `TwinScreen` shows: that one is the web
/// portal's own page, online only, AGPL. This page ships inside the app,
/// works offline from the floor pack's tiles, and is licence-free. Both
/// stay (the user asked for this viewer *alongside* the existing twin).
class WebViewBimViewEngine implements BimViewEngine {
  WebViewBimViewEngine({ViewerAssetServer? server, Color background = const Color(0xFFF1F3F5)})
      : _server = server ?? ViewerAssetServer(loadAsset: _loadBundled),
        _background = background;

  final ViewerAssetServer _server;
  final Color _background;
  final _events = StreamController<BimViewEvent>.broadcast();
  final _pending = <BimViewCommand>[];
  WebViewController? _controller;
  var _pageUp = false;
  var _disposed = false;
  Future<void>? _starting;

  static Future<List<int>?> _loadBundled(String path) async {
    try {
      final data = await rootBundle.load('assets/bim_viewer/$path');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<BimViewEvent> get events => _events.stream;

  @override
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      await _server.start();
    } catch (e) {
      _emit(BimViewerError(code: 'LOAD_FAILED', message: 'viewer server: $e'));
      return;
    }
    if (_disposed) return;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_background)
      ..addJavaScriptChannel('FeViewer', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // The page never navigates; anything else (a stray link) stays out.
        onNavigationRequest: (r) =>
            r.url.startsWith(_server.base) ? NavigationDecision.navigate : NavigationDecision.prevent,
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            _emit(BimViewerError(code: 'LOAD_FAILED', message: '${e.errorCode} ${e.description}'));
          }
        },
      ));
    _controller = c;
    await c.loadRequest(_server.appUri);
  }

  void _onMessage(String raw) {
    final e = BimViewEvent.parse(raw);
    if (e == null) return;
    if (e is BimReady && !_pageUp) {
      _pageUp = true;
      final queued = List.of(_pending);
      _pending.clear();
      for (final c in queued) {
        unawaited(_run(c));
      }
    }
    _emit(e);
  }

  void _emit(BimViewEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Future<void> send(BimViewCommand command) async {
    if (_disposed) return;
    // Before the page reports ready, JavaScript would run in whatever
    // document is loading (or about:blank) and be lost: keep it here.
    if (!_pageUp) {
      _pending.add(command);
      return;
    }
    await _run(command);
  }

  Future<void> _run(BimViewCommand command) async {
    final c = _controller;
    if (c == null || _disposed) return;
    try {
      await c.runJavaScript(command.toJavaScript());
    } catch (e) {
      if (kDebugMode) debugPrint('bim viewer: ${command.name} failed: $e');
    }
  }

  @override
  String exposeTiles(Map<String, String> pathsByHash) {
    _server.setTiles(pathsByHash);
    return _server.isRunning ? _server.tilesBase : '';
  }

  @override
  Widget buildView(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.expand();
    return WebViewWidget(
      controller: c,
      // Orbit, pinch and the walk joystick are handled by the page: it must
      // win every gesture over any Flutter parent.
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _pending.clear();
    await _server.close();
    await _events.close();
  }
}
