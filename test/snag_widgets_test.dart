import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technician_portal/domain/snag.dart';
import 'package:technician_portal/features/snags/widgets/snag_card.dart';
import 'package:technician_portal/features/snags/widgets/snag_visuals.dart';
import 'package:technician_portal/theme/app_theme.dart';

/// Render smoke tests for the Snag Assistant's shared widgets, in English
/// and in Arabic (RTL) on a narrow phone. They load the real `snags.*`
/// strings from the asset files, so a missing key shows up here as the raw
/// key text instead of in front of a technician.
Map<String, dynamic> _strings(String lang) {
  final all = jsonDecode(File('assets/i18n/$lang.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in all.entries)
      if (e.key.startsWith('snags.') || e.key.startsWith('common.')) e.key: e.value,
  };
}

Snag _snag() => Snag(
  id: '4f0c7a8e-1111-4222-8333-444455556666',
  context: SnagContext.fmTakeover,
  issueType: 'damage',
  trade: 'doors-windows',
  priority: SnagPriority.critical,
  title: 'Fire door closer missing on the stair core door',
  status: SnagStatus.open,
  locationLabel: 'Tower A › Level 2 › Stair core 2',
  dueDate: DateTime(2020),
  reportCount: 3,
  reopenedCount: 2,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 2),
  localOnly: true,
);

Future<void> _pump(WidgetTester tester, String lang, Widget child) async {
  FlutterLocalization.instance.translate(lang);
  tester.view.physicalSize = const Size(320 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.build(),
        supportedLocales: FlutterLocalization.instance.supportedLocales,
        localizationsDelegates: FlutterLocalization.instance.localizationsDelegates,
        locale: Locale(lang),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final l = FlutterLocalization.instance;
    await l.ensureInitialized();
    l.init(
      mapLocales: [MapLocale('en', _strings('en')), MapLocale('ar', _strings('ar'))],
      initLanguageCode: 'en',
    );
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('SnagCard shows the flags that change what happens next ($lang)', (tester) async {
      await _pump(tester, lang, SnagCard(snag: _snag(), onTap: () {}));
      expect(tester.takeException(), isNull);
      expect(find.text('×3'), findsOneWidget);
      expect(find.text('↺2'), findsOneWidget);
      expect(find.textContaining('snags.'), findsNothing, reason: 'a raw i18n key leaked');
    });

    testWidgets('severity pills, stepper and compare slider render ($lang)', (tester) async {
      SnagPriority? picked;
      await _pump(
        tester,
        lang,
        Column(
          children: [
            SeveritySelector(value: SnagPriority.minor, onChanged: (p) => picked = p),
            SnagStatusStepper(snag: _snag()),
            const CompareSlider(before: null, after: null, height: 200),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(lang == 'en' ? 'Critical' : 'حرجة'));
      expect(picked, SnagPriority.critical);
      expect(find.textContaining('snags.'), findsNothing);
    });
  }
}
