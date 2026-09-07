import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/storage/session_store.dart';
import 'package:technician_portal/core/utils/currency.dart';
import 'package:technician_portal/domain/history_entry.dart';
import 'package:technician_portal/domain/maintenance_record.dart';
import 'package:technician_portal/features/order_detail/checklist_tab.dart';
import 'package:technician_portal/features/order_detail/order_detail_screen.dart';

void main() {
  group('per-type headings', () {
    test('each kind names its own screen', () {
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.workOrder),
        'Work Order Details',
      );
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.preventive),
        'Preventive Maintenance',
      );
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.reactive),
        'Reactive Maintenance',
      );
      expect(
        OrderDetailScreen.headerTitleFor(OrderType.annual),
        'Annual Maintenance',
      );
    });

    test('the work order heading is its title', () {
      final record = MaintenanceRecord.fromJson({
        'id': '1',
        'workOrderId': 'WO-1',
        'title': 'Chiller service',
        'assetName': 'Chiller 3',
      });
      expect(OrderDetailScreen.detailTitleFor(record), 'Chiller service');
    });

    test('reactive falls back asset then subRequest, never throwing', () {
      final withAsset = MaintenanceRecord.fromJson({
        'id': '1',
        'ticketId': 'RM-1',
        'asset': {'name': 'Pump 2'},
        'subRequest': 'Noise complaint',
      });
      expect(OrderDetailScreen.detailTitleFor(withAsset), 'Pump 2');

      // The web reads `order.asset.name` unguarded and crashes on a ticket
      // with no asset relation.
      final withoutAsset = MaintenanceRecord.fromJson({
        'id': '2',
        'ticketId': 'RM-2',
        'subRequest': 'Noise complaint',
      });
      expect(OrderDetailScreen.detailTitleFor(withoutAsset), 'Noise complaint');

      final bare = MaintenanceRecord.fromJson({'id': '3', 'ticketId': 'RM-3'});
      expect(OrderDetailScreen.detailTitleFor(bare), 'Reactive Maintenance');
    });

    test('preventive and annual fall back to their kind', () {
      expect(
        OrderDetailScreen.detailTitleFor(
          MaintenanceRecord.fromJson({'id': '1', 'pmScheduleId': 'PM-1'}),
        ),
        'Preventive Maintenance',
      );
      expect(
        OrderDetailScreen.detailTitleFor(
          MaintenanceRecord.fromJson({'id': '2', 'amcScheduleId': 'AMC-1'}),
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
      expect(entry.timestamp, DateTime.parse('2026-09-04T08:00:00.000Z').toLocal());
      expect(entry.userName, 'Unknown');
    });

    test('a row with no value change says so', () {
      expect(HistoryEntry.fromJson({'action': 'CREATED'}).hasValueChange, isFalse);
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
