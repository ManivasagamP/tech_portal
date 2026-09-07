import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/data/ai_chat_repository.dart';
import 'package:technician_portal/domain/maintenance_record.dart';
import 'package:technician_portal/domain/technician_insights.dart';

void main() {
  group('technician insights', () {
    test('reads the four types out of the response', () {
      final insights = TechnicianInsights.fromJson({
        'yearToDate': {
          'workOrders': {'total': 12, 'cost': '450.50'},
          'preventive': {'total': 3, 'cost': 0},
          'reactive': {'total': 7, 'cost': 0},
          'annual': {'total': 1, 'cost': 0},
        },
        'inProgress': {
          'workOrders': 2,
          'preventive': 0,
          'reactive': 1,
          'annual': 0,
        },
        'monthlyTrends': [
          {
            'month': 'Jan',
            'workOrder': 4,
            'preventive': 1,
            'reactive': 2,
            'annual': 0,
          },
        ],
      });

      expect(insights.totalsFor(OrderType.workOrder).total, 12);
      // Sequelize DECIMAL arrives as a string.
      expect(insights.totalsFor(OrderType.workOrder).cost, 450.5);
      expect(insights.inProgressFor(OrderType.reactive), 1);
      expect(insights.monthlyTrends.single.countFor(OrderType.reactive), 2);
    });

    test('the response keys are not the route slugs', () {
      // Work orders are `workOrders` in this payload but `work-order`
      // everywhere else; reading the slug would silently give zeros.
      final insights = TechnicianInsights.fromJson({
        'yearToDate': {
          'workOrders': {'total': 9},
        },
      });

      expect(insights.totalsFor(OrderType.workOrder).total, 9);
    });

    test('an empty or broken payload degrades to zeros, never a crash', () {
      // The web page throws a white screen here — it reads
      // `insights.monthlyTrends` with insights still null (§10 row 4).
      final empty = TechnicianInsights.fromJson({});
      expect(empty.monthlyTrends, isEmpty);
      expect(empty.totalsFor(OrderType.annual).total, 0);
      expect(empty.inProgressFor(OrderType.annual), 0);

      final rubbish = TechnicianInsights.fromJson({
        'yearToDate': 'unavailable',
        'inProgress': null,
        'monthlyTrends': {'not': 'a list'},
      });
      expect(rubbish.monthlyTrends, isEmpty);
      expect(rubbish.totalsFor(OrderType.workOrder).total, 0);
    });

    test('a month with no work still draws a bar of zero', () {
      final trend = MonthlyTrend.fromJson({'month': 'Feb'});

      expect(trend.month, 'Feb');
      expect(trend.countFor(OrderType.workOrder), 0);
    });
  });

  group('assistant session id', () {
    test('is deterministic per order, so a thread resumes', () {
      expect(
        AiChatRepository.sessionIdFor(OrderType.reactive, 'rm-1'),
        'technician-checklist:reactive:rm-1',
      );
      expect(
        AiChatRepository.sessionIdFor(OrderType.workOrder, 'wo-1'),
        'technician-checklist:work-order:wo-1',
      );
    });
  });
}
