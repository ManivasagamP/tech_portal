import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/theme/app_colors.dart';
import 'package:technician_portal/theme/theme_extensions.dart';

void main() {
  const chips = FeStatusColors();

  group('status chips match OrderCard.getStatusColor', () {
    test('substring match, not exact', () {
      expect(chips.status('Completed').background, AppColors.green100);
      expect(chips.status('Closed').background, AppColors.green100);
      expect(chips.status('In Progress').background, AppColors.blue100);
      expect(chips.status('in-progress').background, AppColors.blue100);
      expect(chips.status('On Hold').background, AppColors.yellow100);
      expect(chips.status('Cancelled').background, AppColors.gray100);
    });

    test('pending lands on the on-hold palette, as the web does', () {
      expect(chips.status('pending').background, AppColors.yellow100);
    });

    test('unknown statuses fall back to slate', () {
      expect(chips.status('Waiting for Parts').background, AppColors.slate100);
      expect(chips.status(null).background, AppColors.slate100);
    });

    // "Close the Request" contains "close" but not "closed", so the web's
    // substring rule drops it into the fallback palette rather than green.
    test('reactive "Close the Request" is not treated as completed', () {
      expect(chips.status('Close the Request').background, AppColors.slate100);
    });
  });

  group('priority chips keep both web palettes', () {
    test('cards paint Medium blue', () {
      expect(chips.priorityOnCard('medium').foreground, AppColors.blue600);
      expect(chips.priorityOnCard('Medium').foreground, AppColors.blue600);
    });

    test('detail pages paint Medium yellow', () {
      expect(chips.priorityOnDetail('Medium').foreground, AppColors.yellow700);
    });

    test('reactive lowercase enums resolve the same as capitalised ones', () {
      expect(
        chips.priorityOnCard('critical').foreground,
        chips.priorityOnCard('Critical').foreground,
      );
    });
  });
}
