import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technician_portal/state/checkin_controller.dart';
import 'package:technician_portal/theme/app_theme.dart';
import 'package:technician_portal/widgets/location_checkin_gate.dart';

/// Sidesteps the JSON-asset i18n load the same way `order_detail_test.dart`
/// does — only the keys `LocationCheckInGate` actually reads.
const _testEnStrings = {
  'location_checkin.title': 'Location Check-in Required',
  'location_checkin.message': 'Share your location to keep working.',
  'location_checkin.share_button': 'Share Location',
  'location_checkin.checking': 'Checking in…',
};

/// Overrides `build()` to skip the real dependency chain
/// (`authControllerProvider`, `apiClientProvider`) entirely — this test is
/// about what the GATE does with a given [CheckInState], not how that state
/// gets produced (that's `checkin_controller_test.dart`'s job, if/when one
/// exists).
class _FixedCheckInController extends CheckInController {
  _FixedCheckInController(this._state);
  final CheckInState _state;
  @override
  CheckInState build() => _state;
}

Future<void> _pumpGate(
  WidgetTester tester,
  CheckInState state, {
  required VoidCallback onChildTap,
}) async {
  final localization = FlutterLocalization.instance;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        checkInControllerProvider.overrideWith(() => _FixedCheckInController(state)),
      ],
      child: MaterialApp(
        theme: AppTheme.build(),
        supportedLocales: localization.supportedLocales,
        localizationsDelegates: localization.localizationsDelegates,
        locale: localization.currentLocale,
        home: LocationCheckInGate(
          child: Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: onChildTap, child: const Text('Do Work')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final localization = FlutterLocalization.instance;
    await localization.ensureInitialized();
    localization.init(
      mapLocales: [const MapLocale('en', _testEnStrings)],
      initLanguageCode: 'en',
    );
  });

  group('LocationCheckInGate', () {
    testWidgets('required:false — child works normally, no overlay', (tester) async {
      var tapped = false;
      await _pumpGate(tester, const CheckInState(required: false), onChildTap: () => tapped = true);

      expect(find.text('Location Check-in Required'), findsNothing);

      await tester.tap(find.text('Do Work'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('required:true — child is inert and the blocking card shows', (tester) async {
      var tapped = false;
      await _pumpGate(tester, const CheckInState(required: true), onChildTap: () => tapped = true);

      // The card itself renders — this is the fix for "banner was easy to
      // ignore": there's now a title + message + CTA blocking the screen.
      expect(find.text('Location Check-in Required'), findsOneWidget);
      expect(find.text('Share Location'), findsOneWidget);

      // Underlying app content must not receive the tap while required.
      await tester.tap(find.text('Do Work'), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isFalse, reason: 'AbsorbPointer must block taps reaching the app underneath');

      final absorbers = tester.widgetList<AbsorbPointer>(find.byType(AbsorbPointer));
      expect(absorbers.any((w) => w.absorbing), isTrue);

      // The card must sit under a SafeArea — this is the fix for the
      // status-bar overlap the technician saw on a real device.
      expect(
        find.ancestor(of: find.text('Location Check-in Required'), matching: find.byType(SafeArea)),
        findsOneWidget,
      );
    });

    testWidgets('isChecking:true disables the Share Location button', (tester) async {
      await _pumpGate(
        tester,
        const CheckInState(required: true, isChecking: true),
        onChildTap: () {},
      );

      expect(find.text('Checking in…'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Checking in…'));
      expect(button.onPressed, isNull);
    });

    testWidgets('an error message replaces the default copy', (tester) async {
      await _pumpGate(
        tester,
        const CheckInState(required: true, error: 'Could not get your location.'),
        onChildTap: () {},
      );

      expect(find.text('Could not get your location.'), findsOneWidget);
      expect(find.text('Share your location to keep working.'), findsNothing);
    });
  });
}
