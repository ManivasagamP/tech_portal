/// fe_ar: the FieldOps native AR engine (docs/ar-bim-overlay.md §6).
///
/// This library is deliberately a stub. The Dart side of the engine lives in
/// the app, behind the `ArEngine` seam (lib/core/ar/ar_engine.dart), and
/// talks to this plugin only through the three platform names below; the
/// app's `ChannelArEngine` is the one implementation. Keeping the Dart code
/// in the app means the app compiles, tests and runs its Demo mode whether
/// or not this plugin is in the build.
///
/// Every command's and event's argument map is in CHANNEL.md.
library;

/// The three platform names (CONTRACT C8).
abstract final class FeArChannels {
  /// Commands, Dart → native. Method name = the ArEngine command name.
  static const methods = 'fusioneco/ar';

  /// Events, native → Dart: maps with a `type` key.
  static const events = 'fusioneco/ar/events';

  /// The AR surface (camera + model): AndroidView / UiKitView view type.
  static const viewType = 'fusioneco/ar/view';
}

/// Method names on [FeArChannels.methods].
abstract final class FeArMethods {
  static const capabilities = 'capabilities';
  static const startSession = 'startSession';
  static const loadTiles = 'loadTiles';
  static const unloadTiles = 'unloadTiles';
  static const setModelTransform = 'setModelTransform';
  static const setFeatureState = 'setFeatureState';
  static const setLayers = 'setLayers';
  static const setTarget = 'setTarget';
  static const setGridLines = 'setGridLines';
  static const setPins = 'setPins';
  static const detectCornerAt = 'detectCornerAt';
  static const pick = 'pick';
  static const capture = 'capture';
  static const pause = 'pause';
  static const resume = 'resume';
  static const stop = 'stop';

  /// Extension (not in CONTRACT C8): tile-frame points to screen points.
  static const projectTile = 'projectTile';

  /// Extension (Android only): asks the Play Store for Google Play Services
  /// for AR. iOS answers false.
  static const installArCore = 'installArCore';
}

/// `type` values on [FeArChannels.events].
abstract final class FeArEventTypes {
  static const tracking = 'tracking';
  static const marker = 'marker';
  static const corner = 'corner';
  static const anchor = 'anchor';
  static const pose = 'pose';
  static const targetScreen = 'targetScreen';
  static const error = 'error';

  /// Extension, only after `startSession({progressEvents: true})`: one per
  /// QR sample while a board is being locked (drives the M3 Lock ring).
  static const markerProgress = 'markerProgress';
}

/// `code` values of `error` events and of `capabilities().reason`.
abstract final class FeArCodes {
  // capabilities().reason
  static const deviceNotSupported = 'device-not-supported';
  static const arcoreMissing = 'arcore-missing';
  static const arcoreChecking = 'arcore-checking';
  static const arcoreUnknown = 'arcore-unknown';
  static const cameraDenied = 'camera-denied';

  // session
  static const arcoreInstallRequested = 'arcore-install-requested';
  static const cameraUnavailable = 'camera-unavailable';
  static const sessionFailed = 'session-failed';
  static const rendererFailed = 'renderer-failed';
  static const recordingFailed = 'recording-failed';
  static const recordingUnsupported = 'recording-unsupported';
  static const playbackUnsupported = 'playback-unsupported';

  // tiles
  static const tileHashMismatch = 'tile-hash-mismatch';
  static const tileUploadFailed = 'tile-upload-failed';

  // markers
  static const markerUnstable = 'marker-unstable';
  static const anchorFailed = 'anchor-failed';

  // corner coaching (detectCornerAt returned null; say why)
  static const cornerNotTracking = 'corner-not-tracking';
  static const cornerNoSurface = 'corner-no-surface';
  static const cornerNoFloor = 'corner-no-floor';
  static const cornerNoWalls = 'corner-no-walls';
  static const cornerNotFound = 'corner-not-found';
}
