import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/storage/session_store.dart';
import 'package:technician_portal/core/utils/currency.dart';
import 'package:technician_portal/domain/history_entry.dart';
import 'package:technician_portal/domain/maintenance_record.dart';
import 'package:technician_portal/features/order_detail/checklist_tab.dart';
import 'package:technician_portal/features/order_detail/order_detail_screen.dart';

/// `OrderDetailScreen.headerTitleFor`/`detailTitleFor` now read from the
/// `FlutterLocalization` singleton, which needs a `BuildContext` sitting
/// under a `Localizations` ancestor. A `MapLocale` (in-memory, synchronous)
/// sidesteps the JSON-asset load `jsonLocales` would need this test to await
/// — it only defines the handful of keys these two helpers actually touch,
/// using the same English text the pre-i18n version of this screen
/// hardcoded, so the assertions below stay exactly as meaningful as before.
const _testEnStrings = {
  'order_detail.header_work_order': 'Work Order Details',
  'order_detail.header_preventive': 'Preventive Maintenance',
  'order_detail.header_reactive': 'Reactive Maintenance',
  'order_detail.header_annual': 'Annual Maintenance',
};

Future<BuildContext> _localizedContext(WidgetTester tester) async {
  final localization = FlutterLocalization.instance;
  await localization.ensureInitialized();
  localization.init(
    mapLocales: [const MapLocale('en', _testEnStrings)],
    initLanguageCode: 'en',
  );

  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: localization.supportedLocales,
      localizationsDelegates: localization.localizationsDelegates,
      locale: localization.currentLocale,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return captured;
}

void main() {
  group('per-type headings', () {
    testWidgets('each kind names its own screen', (tester) async {
      final context = await _localizedContext(tester);
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.workOrder, context),
        'Work Order Details',
      );
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.preventive, context),
        'Preventive Maintenance',
      );
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.reactive, context),
        'Reactive Maintenance',
      );
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.annual, context),
        'Annual Maintenance',
      );
    });

    testWidgets('the work order heading is its title', (tester) async {
      final context = await _localizedContext(tester);
      final record = MaintenanceRecord.fromJson({
        'id': '1',
        'workOrderId': 'WO-1',
        'title': 'Chiller service',
        'assetName': 'Chiller 3',
      });
      expect(
        OrderDetailScreen.detailTitleFor(record, context),
        'Chiller service',
      );
    });

    testWidgets('reactive falls back asset then subRequest, never throwing', (
      tester,
    ) async {
      final context = await _localizedContext(tester);
      final withAsset = MaintenanceRecord.fromJson({
        'id': '1',
        'ticketId': 'RM-1',
        'asset': {'name': 'Pump 2'},
        'subRequest': 'Noise complaint',
      });
      expect(
        OrderDetailScreen.detailTitleFor(withAsset, context),
        'Pump 2',
      );

      // The web reads `order.asset.name` unguarded and crashes on a ticket
      // with no asset relation.
      final withoutAsset = MaintenanceRecord.fromJson({
        'id': '2',
        'ticketId': 'RM-2',
        'subRequest': 'Noise complaint',
      });
      expect(
        OrderDetailScreen.detailTitleFor(withoutAsset, context),
        'Noise complaint',
      );

      final bare = MaintenanceRecord.fromJson({'id': '3', 'ticketId': 'RM-3'});
      expect(
        OrderDetailScreen.detailTitleFor(bare, context),
        'Reactive Maintenance',
      );
    });

    testWidgets('preventive and annual fall back to their kind', (
      tester,
    ) async {
      final context = await _localizedContext(tester);
      expect(
        OrderDetailScreen.detailTitleFor(
          MaintenanceRecord.fromJson({'id': '1', 'pmScheduleId': 'PM-1'}),
          context,
        ),
        'Preventive Maintenance',
      );
      expect(
        OrderDetailScreen.detailTitleFor(
          MaintenanceRecord.fromJson({'id': '2', 'amcScheduleId': 'AMC-1'}),
          context,
        ),
        'Annual Maintenance',
      );
    });
  });

  group('history entries', () {
    test('action codes read as words', () {
      expect(
        HistoryEntry.fromJson({'action': 'STATUS_UPDATE'}).actionLabel,
        'Status Update',
      );
      expect(
        HistoryEntry.fromJson({'action': 'CREATED'}).actionLabel,
        'Created',
      );
    });

    test('timestamp falls back to createdAt', () {
      final entry = HistoryEntry.fromJson({
        'action': 'CREATED',
        'createdAt': '2026-09-04T08:00:00.000Z',
      });
      expect(
        entry.timestamp,
        DateTime.parse('2026-09-04T08:00:00.000Z').toLocal(),
      );
      expect(entry.userName, 'Unknown');
    });

    test('a row with no value change says so', () {
      expect(
        HistoryEntry.fromJson({'action': 'CREATED'}).hasValueChange,
        isFalse,
      );
      expect(
        HistoryEntry.fromJson({'action': 'X', 'newValue': 'Open'}).hasValueChange,
        isTrue,
      );
    });
  });

  group('checklist row title', () {
    test('keeps the text before the first colon', () {
      expect(
        shortChecklistTitle('Check belt tension: use a gauge, 40-60 Hz'),
        'Check belt tension',
      );
    });

    test('caps a long head at 40 characters', () {
      final long = 'A' * 60;
      final shortened = shortChecklistTitle(long);
      expect(shortened.length, 41);
      expect(shortened.endsWith('…'), isTrue);
    });
  });

  group('currency', () {
    const permissions = Permissions(
      currencyType: 'AED',
      currencyRates: {'INR': 1.0, 'AED': 22.0},
    );

    test('converts out of the base currency', () {
      expect(convertFromBase(220, 'AED', permissions.currencyRates), 10);
    });

    test('passes through when the target is the base', () {
      expect(convertFromBase(220, 'INR', permissions.currencyRates), 220);
    });

    test('passes through when a rate is missing', () {
      expect(convertFromBase(220, 'USD', permissions.currencyRates), 220);
    });

    test('a null amount formats as zero', () {
      expect(formatCurrencyFromBase(null, permissions), contains('0'));
    });
  });
}
