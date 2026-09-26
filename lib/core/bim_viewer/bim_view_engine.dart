import 'dart:async';

import 'package:flutter/widgets.dart';

import 'bim_view_wire.dart';

export 'bim_view_wire.dart';

/// The 3D half of the model viewer, behind a seam (docs/bim-viewer.md §4),
/// the way `ArEngine` hides `packages/fe_ar` from the AR screens.
///
/// Implementations:
/// - `WebViewBimViewEngine` (features/bim_viewer): three.js in a WebView,
///   fed by a loopback server. The one that ships.
/// - [FakeBimViewEngine]: records commands, lets a test emit events; draws a
///   placeholder. Widget tests and anything without a WebView use it.
/// - later, perhaps, Filament via `packages/fe_ar` once its renderer has a
///   camera that isn't an AR session. Same commands, same events.
abstract interface class BimViewEngine {
  /// Ready, tile progress, camera pose (≤ 10 Hz), picks, errors.
  Stream<BimViewEvent> get events;

  /// Brings the engine up (server, page). Idempotent. Events follow;
  /// [BimReady] once it can draw, or a fatal [BimViewerError].
  Future<void> start();

  /// Queues until [BimReady], then delivers in order.
  Future<void> send(BimViewCommand command);

  /// Makes these tile files (content hash → local path) loadable by the
  /// engine and returns the base for [BimViewCommand.setTiles]. Replaces
  /// what was exposed before.
  String exposeTiles(Map<String, String> pathsByHash);

  /// The surface to put in the widget tree.
  Widget buildView(BuildContext context);

  Future<void> dispose();
}

/// A scripted engine: no rendering, every command recorded. The house
/// pattern for seams (CLAUDE.md "Tests": hand-written `implements` fakes).
class FakeBimViewEngine implements BimViewEngine {
  FakeBimViewEngine({this.autoReady = true});

  /// Emit [BimReady] from [start] (what a healthy WebView does).
  final bool autoReady;

  final _events = StreamController<BimViewEvent>.broadcast();
  final sent = <BimViewCommand>[];
  Map<String, String> exposed = const {};
  var started = false;
  var disposed = false;

  @override
  Stream<BimViewEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (started) return;
    started = true;
    if (autoReady) scheduleMicrotask(() => emit(const BimReady(version: 1, webgl2: true)));
  }

  @override
  Future<void> send(BimViewCommand command) async => sent.add(command);

  @override
  String exposeTiles(Map<String, String> pathsByHash) {
    exposed = Map.of(pathsByHash);
    return 'fake://tiles/';
  }

  /// Test hook: pretend viewer.js reported [event].
  void emit(BimViewEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// The commands sent so far with this name, oldest first.
  List<BimViewCommand> named(String name) => [for (final c in sent) if (c.name == name) c];

  @override
  Widget buildView(BuildContext context) => const SizedBox.expand(key: ValueKey('fake-bim-view'));

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
