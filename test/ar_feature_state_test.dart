import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/feature_state.dart';
import 'package:technician_portal/domain/ar_models.dart';

void main() {
  test('one RGBA texel per feature, row-major, width texels a row', () {
    final tex = FeatureState.build(featureCount: 10, width: 4);
    expect(tex.width, 4);
    expect(tex.height, 3);
    expect(tex.rgba.length, 4 * 3 * 4);
    // Every texel starts as "normal, untinted".
    for (var id = 0; id < 12; id++) {
      expect(tex.texel(id), (0, 0, 0, FeatureDisplay.normal.alpha));
    }
  });

  test('a small floor gets a one-row texture, never a mostly empty one', () {
    final tex = FeatureState.build(featureCount: 3);
    expect(tex.width, 3);
    expect(tex.height, 1);
  });

  test('styles encode tint in RGB and the display mode in A', () {
    final tex = FeatureState.build(
      featureCount: 5,
      styles: {
        1: const FeatureStyle(rgb: 0x10B981),
        2: FeatureStyle.hidden,
        3: const FeatureStyle(display: FeatureDisplay.highlight, rgb: 0x0EA5E9),
        99: FeatureStyle.hidden, // out of range: ignored, never a crash
      },
    );
    expect(tex.texel(1), (0x10, 0xB9, 0x81, 170));
    expect(tex.texel(2), (0, 0, 0, 0));
    expect(tex.texel(3), (0x0E, 0xA5, 0xE9, 255));
  });

  test('fromStatus: hidden beats target beats selection beats status', () {
    final tex = FeatureState.fromStatus(
      featureCount: 8,
      statusByFeature: {
        0: ArProgressStatus.installed,
        1: ArProgressStatus.verified,
        2: ArProgressStatus.issue,
        3: ArProgressStatus.notStarted,
        4: ArProgressStatus.verified,
        5: ArProgressStatus.verified,
      },
      selected: {4, 6},
      target: {5, 6},
      hidden: {6},
      ghostOthers: true,
    );
    expect(tex.texel(0), (0xF5, 0x9E, 0x0B, FeatureDisplay.normal.alpha));
    expect(tex.texel(1), (0x10, 0xB9, 0x81, FeatureDisplay.normal.alpha));
    expect(tex.texel(2), (0xEF, 0x44, 0x44, FeatureDisplay.normal.alpha));
    // Not started carries no tint, so with ghostOthers it fades into context.
    expect(tex.texel(3).$4, FeatureDisplay.ghost.alpha);
    expect(tex.texel(4).$4, FeatureDisplay.highlight.alpha);
    expect(tex.texel(5).$4, FeatureDisplay.highlight.alpha);
    expect(tex.texel(6).$4, FeatureDisplay.hidden.alpha);
    expect(tex.texel(7).$4, FeatureDisplay.ghost.alpha);
  });

  test('alpha levels are 85 apart so filtering can\'t confuse modes', () {
    final alphas = FeatureDisplay.values.map((d) => d.alpha).toList();
    expect(alphas, [0, 85, 170, 255]);
  });
}
