import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/capture/capture_services.dart';
import 'package:technician_portal/data/checklist_repository.dart';
import 'package:technician_portal/domain/checklist.dart';

ChecklistItem item(Map<String, dynamic> json) => ChecklistItem.fromJson(json);

final _now = DateTime.utc(2026, 9, 4, 12, 0);

void main() {
  group('starting a session', () {
    test('appends to the existing sessions and clears the end time', () {
      final updates = ChecklistRepository.startUpdates(
        item: item({
          'sessions': [
            {
              'startTime': '2026-09-04T08:00:00.000Z',
              'endTime': '2026-09-04T09:00:00.000Z',
              'timeSpent': 60,
            }
          ],
          'endTime': '2026-09-04T09:00:00.000Z',
        }),
        now: _now,
      );

      final sessions = updates['sessions'] as List;
      expect(sessions, hasLength(2));
      expect(sessions.last['startTime'], _now.toIso8601String());
      expect(sessions.last['timeSpent'], 0);
      expect(updates['endTime'], isNull);
      expect(updates['startTime'], _now.toIso8601String());
    });

    test('carries the face placeholder and coordinates onto the session', () {
      final updates = ChecklistRepository.startUpdates(
        item: item({}),
        now: _now,
        facePlaceholder: '__pending_face_1__',
        location: const CapturedLocation(latitude: 25.2, longitude: 55.3),
      );

      final session = (updates['sessions'] as List).single;
      expect(session['faceCaptureUrl'], '__pending_face_1__');
      expect(session['latitude'], 25.2);
      expect(session['longitude'], 55.3);
    });

    test('omits verification keys entirely when nothing was captured', () {
      final session =
          (ChecklistRepository.startUpdates(item: item({}), now: _now)['sessions']
                  as List)
              .single as Map;
      expect(session.containsKey('faceCaptureUrl'), isFalse);
      expect(session.containsKey('latitude'), isFalse);
    });
  });

  group('stopping a session', () {
    test('closes the open session and totals every session', () {
      final updates = ChecklistRepository.stopUpdates(
        item: item({
          'sessions': [
            {
              'startTime': '2026-09-04T08:00:00.000Z',
              'endTime': '2026-09-04T08:30:00.000Z',
              'timeSpent': 30,
            },
            {'startTime': '2026-09-04T11:15:00.000Z'},
          ],
        }),
        now: _now,
      );

      final sessions = updates['sessions'] as List;
      expect(sessions.last['endTime'], _now.toIso8601String());
      expect(sessions.last['timeSpent'], 45);
      // 30 from the first session plus the 45 just closed.
      expect(updates['timeSpent'], 75);
    });

    test('synthesises a session for an item started before sessions existed', () {
      final updates = ChecklistRepository.stopUpdates(
        item: item({'startTime': '2026-09-04T11:00:00.000Z'}),
        now: _now,
      );

      final sessions = updates['sessions'] as List;
      expect(sessions, hasLength(1));
      expect(sessions.single['startTime'], '2026-09-04T11:00:00.000Z');
      expect(updates['timeSpent'], 60);
    });

    test('falls back to the top-level start when no session is open', () {
      final updates = ChecklistRepository.stopUpdates(
        item: item({
          'startTime': '2026-09-04T11:30:00.000Z',
          'endTime': '2026-09-04T11:45:00.000Z',
          'sessions': [
            {
              'startTime': '2026-09-04T11:30:00.000Z',
              'endTime': '2026-09-04T11:45:00.000Z',
              'timeSpent': 15,
            }
          ],
        }),
        now: _now,
      );
      expect(updates['timeSpent'], 30);
    });

    test('attaches the end-of-session face placeholder', () {
      final updates = ChecklistRepository.stopUpdates(
        item: item({
          'sessions': [
            {'startTime': '2026-09-04T11:00:00.000Z'}
          ],
        }),
        now: _now,
        facePlaceholder: '__pending_face_2__',
      );
      expect(
        (updates['sessions'] as List).single['endFaceCaptureUrl'],
        '__pending_face_2__',
      );
    });

    test('a session shorter than a minute rounds down to zero', () {
      final updates = ChecklistRepository.stopUpdates(
        item: item({
          'sessions': [
            {'startTime': '2026-09-04T11:59:30.000Z'}
          ],
        }),
        now: _now,
      );
      expect(updates['timeSpent'], 0);
    });
  });
}
