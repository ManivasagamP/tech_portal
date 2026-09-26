import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technician_portal/core/bim_viewer/bim_view_engine.dart';
import 'package:technician_portal/features/bim_viewer/bim_plan_view.dart';
import 'package:technician_portal/features/bim_viewer/bim_viewer_screen.dart';
import 'package:technician_portal/state/ar_catalog_controller.dart' show arGatewayProvider;
import 'package:technician_portal/state/bim_viewer_pack.dart';
import 'package:technician_portal/theme/app_theme.dart';

import 'bim_viewer_fakes.dart';

/// Render smoke test of the model viewer screen (docs/bim-viewer.md) with a
/// [FakeBimViewEngine] in place of the WebView, in English and Arabic on a
/// narrow phone. Real `bim_viewer.*` strings, so a missing key shows here.
Map<String, dynamic> _strings(String lang) {
  final all = jsonDecode(File('assets/i18n/$lang.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in all.entries)
      if (e.key.startsWith('bim_viewer.') || e.key.startsWith('common.') || e.key.startsWith('ar.')) e.key: e.value,
  };
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
    testWidgets('split view: toolbar, 3D surface, plan, download banner, pick → card ($lang)', (tester) async {
      FlutterLocalization.instance.translate(lang);
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final gateway = FakeViewerGateway();
      final engine = FakeBimViewEngine();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          arGatewayProvider.overrideWithValue(gateway),
          bimViewerPackProvider.overrideWithValue(FakeViewerPack(gateway, tiles: [tileSolid])),
          bimViewEngineFactoryProvider.overrideWithValue(() => engine),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          supportedLocales: FlutterLocalization.instance.supportedLocales,
          localizationsDelegates: FlutterLocalization.instance.localizationsDelegates,
          locale: Locale(lang),
          home: const BimViewerScreen(floorId: 'flr-3'),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('fake-bim-view')), findsOneWidget);
      expect(find.byType(BimPlanView), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsWidgets);
      expect(find.text('bim_viewer.download'.getString(tester.element(find.byType(BimViewerScreen)))), findsOneWidget);
      expect(engine.named('setFloor'), hasLength(1));

      // A 3D pick shows the selection card with the asset action.
      engine.emit(const BimPick(featureId: 42, buildId: 'b1', layer: 'mep'));
      await tester.pump();
      expect(find.text('CHW pump P-01'), findsOneWidget);
      expect(find.text(lang == 'en' ? 'Open asset' : 'فتح الأصل'), findsOneWidget);

      // The layers sheet opens.
      await tester.tap(find.byTooltip('bim_viewer.layers'.getString(tester.element(find.byType(BimViewerScreen)))));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(6));

      expect(find.textContaining('bim_viewer.'), findsNothing, reason: 'a raw i18n key leaked');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a tap on the plan flies the 3D camera there', (tester) async {
    FlutterLocalization.instance.translate('en');
    final gateway = FakeViewerGateway();
    final engine = FakeBimViewEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        arGatewayProvider.overrideWithValue(gateway),
        bimViewerPackProvider.overrideWithValue(FakeViewerPack(gateway)),
        bimViewEngineFactoryProvider.overrideWithValue(() => engine),
      ],
      child: MaterialApp(
        theme: AppTheme.build(),
        supportedLocales: FlutterLocalization.instance.supportedLocales,
        localizationsDelegates: FlutterLocalization.instance.localizationsDelegates,
        home: const BimViewerScreen(floorId: 'flr-3'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final plan = find.byType(BimPlanView);
    final box = tester.getRect(plan);
    await tester.tapAt(box.center + const Offset(40, 20));
    // Single taps wait out the double-tap window.
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.named('flyTo'), isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
