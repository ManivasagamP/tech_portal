import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/theme/fe_status_tokens.dart';
import 'package:technician_portal/theme/theme_extensions.dart';

void main() {
  const chips = FeStatusColors();

  group('status chips match OrderCard.getStatusColor', () {
    test('substring match, not exact', () {
      expect(chips.status('Completed').foreground, FeStatusHues.completed);
      expect(chips.status('Closed').foreground, FeStatusHues.completed);
      expect(chips.status('In Progress').foreground, FeStatusHues.inProgress);
      expect(chips.status('in-progress').foreground, FeStatusHues.inProgress);
      expect(chips.status('On Hold').foreground, FeStatusHues.onHold);
      expect(chips.status('Cancelled').foreground, FeStatusHues.cancelled);
    });

    test('pending lands on the on-hold palette, as the web does', () {
      expect(chips.status('pending').foreground, FeStatusHues.onHold);
    });

    test('unknown statuses fall back to the draft hue', () {
      expect(chips.status('Waiting for Parts').foreground, FeStatusHues.draft);
      expect(chips.status(null).foreground, FeStatusHues.draft);
    });

    // "Close the Request" contains "close" but not "closed", so the web's
    // substring rule drops it into the fallback palette rather than green.
    test('reactive "Close the Request" is not treated as completed', () {
      expect(chips.status('Close the Request').foreground, FeStatusHues.draft);
    });
  });

  group('priority chips use one palette everywhere', () {
    // Previously the app ran two different "Medium" colors depending on
    // context (card view blue, detail view yellow) — a duplication the web
    // app's own source carried too. The web's real token layer defines
    // exactly one `--priority-medium`, so there is now one `priority()`
    // lookup, and it must return the same value regardless of call site.
    test('medium is the same color everywhere', () {
      expect(chips.priority('medium').foreground, FeStatusHues.priorityMedium);
      expect(chips.priority('Medium').foreground, FeStatusHues.priorityMedium);
    });

    test('critical, high and low resolve to their own hues', () {
      expect(
        chips.priority('critical').foreground,
        FeStatusHues.priorityCritical,
      );
      expect(chips.priority('high').foreground, FeStatusHues.priorityHigh);
      expect(chips.priority('low').foreground, FeStatusHues.priorityLow);
    });

    test('lowercase enums resolve the same as capitalised ones', () {
      expect(
        chips.priority('critical').foreground,
        chips.priority('Critical').foreground,
      );
    });
  });
}
