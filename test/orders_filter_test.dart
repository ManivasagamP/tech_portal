import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/domain/maintenance_record.dart';
import 'package:technician_portal/state/orders_controller.dart';

MaintenanceRecord record({
  required String id,
  String? workOrderId,
  String? ticketId,
  String? amcScheduleId,
  String? title,
  String? subRequest,
  String? assetName,
  String? description,
  String? priority,
  String? status,
  String? location,
  DateTime? dueDate,
}) =>
    MaintenanceRecord.fromJson({
      'id': id,
      'workOrderId': workOrderId,
      'ticketId': ticketId,
      'amcScheduleId': amcScheduleId,
      'title': title,
      'subRequest': subRequest,
      'assetName': assetName,
      'description': description,
      'priority': priority,
      'status': status,
      'location': location,
      'dueDate': dueDate?.toIso8601String(),
    });

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 9);
}

void main() {
  group('type inference', () {
    test('picks the kind from the reference id present', () {
      expect(record(id: 'a', workOrderId: 'WO-1').type, OrderType.workOrder);
      expect(record(id: 'b', ticketId: 'RM-1').type, OrderType.reactive);
      expect(record(id: 'c', amcScheduleId: 'AMC-1').type, OrderType.annual);
    });

    test('falls back to work order when no reference id is present', () {
      expect(record(id: 'd').type, OrderType.workOrder);
    });
  });

  group('path vocabulary', () {
    test('work orders pluralise for rca and downtime only', () {
      expect(OrderType.workOrder.entityPath, 'work-order');
      expect(OrderType.workOrder.rcaPath, 'work-orders');
      expect(OrderType.workOrder.downtimePath, 'work-orders');
      expect(OrderType.workOrder.completePath, 'work-order');
      expect(OrderType.workOrder.historyType, isNull);
    });

    test('maintenance kinds keep one path throughout', () {
      for (final type in [
        OrderType.preventive,
        OrderType.reactive,
        OrderType.annual,
      ]) {
        expect(type.rcaPath, type.entityPath);
        expect(type.downtimePath, type.entityPath);
        expect(type.completePath, type.entityPath);
        expect(type.historyType, isNotNull);
      }
    });

    test('preventive is not browsable', () {
      expect(kBrowsableOrderTypes, isNot(contains(OrderType.preventive)));
      expect(kBrowsableOrderTypes, hasLength(3));
    });
  });

  group('visibleRecords', () {
    final records = [
      record(
        id: '1',
        workOrderId: 'WO-1',
        title: 'Chiller service',
        priority: 'Critical',
        status: 'In Progress',
        location: 'Tower A',
        dueDate: _today.subtract(const Duration(days: 3)),
      ),
      record(
        id: '2',
        ticketId: 'RM-9',
        title: 'Leaking tap',
        priority: 'low',
        status: 'New',
        location: 'Tower B',
        dueDate: _today,
      ),
      record(
        id: '3',
        amcScheduleId: 'AMC-4',
        title: 'Lift contract',
        priority: 'Medium',
        status: 'Completed',
        location: 'Tower A',
        dueDate: _today.subtract(const Duration(days: 10)),
      ),
    ];

    OrdersState stateWith({
      OrderFilters filters = const OrderFilters(),
      String search = '',
    }) =>
        OrdersState(records: records, filters: filters, searchQuery: search);

    test('sorts newest first by default', () {
      expect(
        stateWith().visibleRecords.map((r) => r.id).toList(),
        ['2', '1', '3'],
      );
    });

    test('sorts oldest first when asked', () {
      final visible = stateWith(
        filters: const OrderFilters(sortOrder: SortOrder.asc),
      ).visibleRecords;
      expect(visible.map((r) => r.id).toList(), ['3', '1', '2']);
    });

    test('priority match is case-insensitive', () {
      final visible =
          stateWith(filters: const OrderFilters(priority: 'Low')).visibleRecords;
      expect(visible.single.id, '2');
    });

    test('status match flattens hyphens', () {
      final visible = stateWith(
        filters: const OrderFilters(status: 'In-Progress'),
      ).visibleRecords;
      expect(visible.single.id, '1');
    });

    test('overdue excludes finished records', () {
      final visible = stateWith(
        filters: const OrderFilters(dateFilter: DateFilter.overdue),
      ).visibleRecords;
      expect(visible.map((r) => r.id).toList(), ['1']);
    });

    test('due today is the calendar day', () {
      final visible = stateWith(
        filters: const OrderFilters(dateFilter: DateFilter.dueToday),
      ).visibleRecords;
      expect(visible.single.id, '2');
    });

    test('search covers title, reference id and location', () {
      expect(stateWith(search: 'chiller').visibleRecords.single.id, '1');
      expect(stateWith(search: 'amc-4').visibleRecords.single.id, '3');
      expect(
        stateWith(search: 'tower a').visibleRecords.map((r) => r.id).toList(),
        ['1', '3'],
      );
    });

    test('filters compose', () {
      final visible = stateWith(
        filters: const OrderFilters(priority: 'Critical'),
        search: 'tower a',
      ).visibleRecords;
      expect(visible.single.id, '1');
    });
  });

  group('display fallbacks', () {
    test('card title leads with the asset, dashboard title with the title', () {
      final r = record(
        id: '1',
        workOrderId: 'WO-1',
        title: 'AC not cooling',
        subRequest: 'AHU-3 service',
        assetName: 'AHU-3',
      );
      expect(r.cardTitle, 'AHU-3 service');
      expect(r.focusTitle, 'AC not cooling');
    });

    test('priority renders title case', () {
      expect(record(id: '1', priority: 'critical').displayPriority, 'Critical');
      expect(record(id: '2', priority: 'HIGH').displayPriority, 'High');
      expect(record(id: '3').displayPriority, 'Medium');
    });

    test('missing values fall back to the web placeholders', () {
      final r = record(id: '1');
      expect(r.cardTitle, 'Untitled Task');
      expect(r.cardDescription, 'No description provided');
      expect(r.displayStatus, 'Pending');
      expect(r.displayLocation, 'Unknown');
      expect(r.displayTechnician, 'Unassigned');
    });
  });

  test('status options are per selected type', () {
    expect(statusOptionsFor(OrderType.workOrder), contains('On Hold'));
    expect(statusOptionsFor(OrderType.reactive), isNot(contains('On Hold')));
    expect(statusOptionsFor(OrderType.annual), contains('Pending Renewal'));
    expect(statusOptionsFor(null), contains('Expired'));
  });
}
