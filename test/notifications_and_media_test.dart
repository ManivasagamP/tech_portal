import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/domain/app_notification.dart';
import 'package:technician_portal/widgets/voice_note_player.dart';

void main() {
  group('pending audio', () {
    test('a queued recording is not playable', () {
      expect(isPendingAudio('__pending_audio_abc__'), isTrue);
    });

    test('an uploaded recording is', () {
      expect(isPendingAudio('https://minio.local/voice/note.m4a'), isFalse);
    });
  });

  group('clip duration', () {
    test('pads the seconds', () {
      expect(formatClipDuration(const Duration(seconds: 8)), '0:08');
      expect(formatClipDuration(const Duration(seconds: 65)), '1:05');
      expect(formatClipDuration(const Duration(minutes: 3)), '3:00');
    });
  });

  group('notifications', () {
    test('reads the fields the bell and the list need', () {
      final notification = AppNotification.fromJson({
        'id': 'n1',
        'title': 'New assignment',
        'message': 'You have been invited to WO-42',
        'type': 'info',
        'entityId': 'wo-42',
        'entityType': 'work-order',
        'isSeen': false,
        'isRead': false,
        'createdAt': '2026-09-04T08:00:00.000Z',
      });

      expect(notification.id, 'n1');
      expect(notification.entityType, 'work-order');
      expect(notification.isSeen, isFalse);
      expect(
        notification.createdAt,
        DateTime.parse('2026-09-04T08:00:00.000Z').toLocal(),
      );
    });

    test('defaults to an info notification when the type is missing', () {
      expect(AppNotification.fromJson({'id': 'n2'}).type, 'info');
    });
  });
}
