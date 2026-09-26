import 'dart:typed_data';

import '../../domain/ar_models.dart' show ArProgressStatus;

/// How one feature is drawn. Encoded in the texel's alpha so the native
/// material can branch on it (see [FeatureStateTexture]).
enum FeatureDisplay {
  /// Not drawn at all (filtered out).
  hidden(0),

  /// Faint context, x-ray style (everything around a target).
  ghost(85),

  /// The layer's own material; RGB, when non-zero, tints it (progress
  /// colours, a system tint).
  normal(170),

  /// The target or a selection: drawn solid **through walls** with an
  /// outline, in the texel's RGB.
  highlight(255);

  const FeatureDisplay(this.alpha);

  final int alpha;
}

class FeatureStyle {
  const FeatureStyle({this.display = FeatureDisplay.normal, this.rgb});

  static const normal = FeatureStyle();
  static const hidden = FeatureStyle(display: FeatureDisplay.hidden);
  static const ghost = FeatureStyle(display: FeatureDisplay.ghost);

  final FeatureDisplay display;

  /// 0xRRGGBB tint, or null for the material's own colour (RGB 0,0,0 on the
  /// wire, which therefore can't be used as a tint; use 0x010101 for black).
  final int? rgb;
}

/// The feature-state texture (docs/ar-bim-overlay.md §5.4): one RGBA8 texel
/// per feature id, row-major, [width] texels per row, so showing, hiding,
/// tinting or highlighting any set of elements is **one texture upload and
/// no geometry change**. The native material reads the texel at
/// `(featureId % width, featureId ~/ width)`, where `featureId` comes from
/// the tile's `TEXCOORD_1` local index through the tile's
/// `extras.fe.featureIds` table (CONTRACT C7).
///
/// Encoding (shared with `packages/fe_ar`'s shader; change both together):
/// - **R, G, B:** tint colour; `0,0,0` = no tint (use the material colour).
/// - **A:** display mode, decoded as `round(a · 255)`:
///   `0` hidden · `85` ghost · `170` normal · `255` highlight (x-ray, drawn
///   through walls, outlined). Values are spaced 85 apart so a sampler's
///   filtering or an 8-bit round trip can't turn one mode into another.
class FeatureStateTexture {
  const FeatureStateTexture({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;

  int get texelCount => width * height;

  /// Reads back one feature's texel as (r, g, b, a) — for tests and debugging.
  (int, int, int, int) texel(int featureId) {
    final i = featureId * 4;
    return (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]);
  }
}

/// Default progress colours (0xRRGGBB), mirroring `FeColors`/`FeStatusTokens`
/// hues: installed amber, verified green, issue red; not started untinted.
/// Kept as ints so this file stays pure Dart (the screen can pass its own
/// palette built from theme tokens).
const kProgressPalette = <String, int>{
  ArProgressStatus.installed: 0xF59E0B,
  ArProgressStatus.verified: 0x10B981,
  ArProgressStatus.issue: 0xEF4444,
};

/// Default selection/target highlight (FeColors.primaryLight hue).
const kHighlightRgb = 0x0EA5E9;

abstract final class FeatureState {
  /// Default texture width: 1024 texels a row keeps the texture under the
  /// 4096 max dimension of every supported GPU up to 4M features.
  static const defaultWidth = 1024;

  /// Builds a texture for [featureCount] features, each drawn with [base]
  /// unless [styles] says otherwise. Ids outside `0 ≤ id < featureCount`
  /// are ignored (a stale selection must not crash a redraw).
  static FeatureStateTexture build({
    required int featureCount,
    Map<int, FeatureStyle> styles = const {},
    FeatureStyle base = FeatureStyle.normal,
    int width = defaultWidth,
  }) {
    assert(width > 0, 'width must be positive');
    final count = featureCount < 1 ? 1 : featureCount;
    final w = count < width ? count : width;
    final h = (count + w - 1) ~/ w;
    final bytes = Uint8List(w * h * 4);

    void put(int id, FeatureStyle s) {
      final i = id * 4;
      final rgb = s.rgb;
      bytes[i] = rgb == null ? 0 : (rgb >> 16) & 0xFF;
      bytes[i + 1] = rgb == null ? 0 : (rgb >> 8) & 0xFF;
      bytes[i + 2] = rgb == null ? 0 : rgb & 0xFF;
      bytes[i + 3] = s.display.alpha;
    }

    for (var id = 0; id < w * h; id++) {
      put(id, base);
    }
    styles.forEach((id, style) {
      if (id >= 0 && id < featureCount) put(id, style);
    });
    return FeatureStateTexture(rgba: bytes, width: w, height: h);
  }

  /// The common case: colour by progress status, highlight the selection and
  /// the target, hide filtered features, and optionally ghost everything
  /// that isn't selected, targeted or coloured (Locate mode's x-ray context).
  ///
  /// Precedence, strongest first: hidden → target → selected → status tint
  /// → base.
  static FeatureStateTexture fromStatus({
    required int featureCount,
    Map<int, String> statusByFeature = const {},
    Set<int> selected = const {},
    Set<int> target = const {},
    Set<int> hidden = const {},
    bool ghostOthers = false,
    Map<String, int> palette = kProgressPalette,
    int highlightRgb = kHighlightRgb,
    int? selectedRgb,
    int width = defaultWidth,
  }) {
    final styles = <int, FeatureStyle>{};
    statusByFeature.forEach((id, status) {
      final rgb = palette[status];
      if (rgb != null) styles[id] = FeatureStyle(rgb: rgb);
    });
    for (final id in selected) {
      styles[id] = FeatureStyle(display: FeatureDisplay.highlight, rgb: selectedRgb ?? highlightRgb);
    }
    for (final id in target) {
      styles[id] = FeatureStyle(display: FeatureDisplay.highlight, rgb: highlightRgb);
    }
    for (final id in hidden) {
      styles[id] = FeatureStyle.hidden;
    }
    return build(
      featureCount: featureCount,
      styles: styles,
      base: ghostOthers ? FeatureStyle.ghost : FeatureStyle.normal,
      width: width,
    );
  }
}
