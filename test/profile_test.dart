import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/domain/maintenance_record.dart';
import 'package:technician_portal/domain/technician_profile.dart';

void main() {
  group('technician profile', () {
    test('reads the identity fields the screen shows', () {
      final profile = TechnicianProfile.fromJson({
        'name': 'Balaji',
        'email': 'balaji@eco.com',
        'phone': '9876543210',
        'department': 'Electrical Equipment',
        'status': 'Active',
        'experience': '4.5',
        'specialization': ['HVAC', 'Electrical'],
        'certifications': ['NEBOSH', 'IOSH'],
      });

      expect(profile.name, 'Balaji');
      // Sequelize DECIMAL arrives as a string.
      expect(profile.experienceYears, 4.5);
      expect(profile.specialization, ['HVAC', 'Electrical']);
      expect(profile.certifications, ['NEBOSH', 'IOSH']);
    });

    test('accepts a single specialization sent as a bare string', () {
      final profile = TechnicianProfile.fromJson({'specialization': 'HVAC'});

      expect(profile.specialization, ['HVAC']);
    });

    test('an absent list is empty, not a list holding nothing useful', () {
      final profile = TechnicianProfile.fromJson({'specialization': ''});

      expect(profile.specialization, isEmpty);
      expect(profile.certifications, isEmpty);
    });

    test('metrics fall back to zero rather than blanking the screen', () {
      final metrics = TechnicianMetrics.fromJson({});

      expect(metrics.totalOrders, 0);
      expect(metrics.completionRate, 0);
      expect(metrics.qualityScore, 0);
    });
  });

  group('invite rows', () {
    test('the endpoint\'s own kind wins over inference', () {
      // A preventive row carrying no pmScheduleId would otherwise be inferred
      // as a work order and open the wrong detail route.
      final record = MaintenanceRecord.fromJson(
        {'id': 'pm-1', 'assignmentStatus': 'pending'},
        OrderType.preventive,
      );

      expect(record.type, OrderType.preventive);
      expect(record.isAssignmentPending, isTrue);
    });

    test('inference still applies when no kind is passed', () {
      final record = MaintenanceRecord.fromJson({
        'id': 'rm-1',
        'ticketId': 'RM0165',
      });

      expect(record.type, OrderType.reactive);
    });
  });
}
