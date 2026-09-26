import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme_extensions.dart';

/// Permit to Work (PTW) type → icon/colour, the one place that turns the
/// server's `PermitType` wire values into something a hub card or a type
/// chip can draw — so the hub, the detail header and any future screen can
/// never disagree about what a "hot work" permit looks like. Composed from
/// the existing [FeAccents] badge palette rather than new hex values, per
/// this app's "no raw `Color(0x…)` outside `lib/theme/`" rule (this file is
/// inside it, but reusing the shared palette keeps one true set of tones
/// anyway instead of inventing 10 more).
abstract final class PermitVisuals {
  static IconData icon(String type) => switch (type) {
    'hot_work' => LucideIcons.flame,
    'work_at_height' => LucideIcons.moveVertical,
    'confined_space' => LucideIcons.doorClosed,
    'electrical' => LucideIcons.plugZap,
    'excavation' => LucideIcons.layers,
    'fire_impairment' => LucideIcons.shieldAlert,
    'roof_access' => LucideIcons.house,
    'lifting' => LucideIcons.link,
    'hazardous_substances' => LucideIcons.triangleAlert,
    _ => LucideIcons.fileText, // 'general' and anything the app doesn't know yet
  };

  static FeBadgeStyle badge(String type, FeAccents accents) => switch (type) {
    'hot_work' => accents.rose,
    'work_at_height' => accents.amber,
    'confined_space' => accents.purple,
    'electrical' => accents.blue,
    'excavation' => accents.emerald,
    'fire_impairment' => accents.rose,
    'roof_access' => accents.amber,
    'lifting' => accents.orange,
    'hazardous_substances' => accents.purple,
    _ => accents.slate,
  };
}
