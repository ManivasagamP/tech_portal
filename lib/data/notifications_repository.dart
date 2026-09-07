import '../core/network/api_client.dart';
import '../core/network/envelope.dart';
import '../domain/app_notification.dart';

class NotificationsPage {
  const NotificationsPage({required this.notifications, required this.unseenCount});

  final List<AppNotification> notifications;

  /// "Seen" means the bell has been opened since they arrived — distinct from
  /// "read", which means a specific notification was tapped.
  final int unseenCount;
}

class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  Future<NotificationsPage> list({int limit = 10}) async {
    final response =
        await _api.get('/api/notifications', query: {'limit': limit});
    final data = unwrapMap(response.data);
    final rows = data['notifications'];
    return NotificationsPage(
      notifications: rows is List
          ? rows
              .whereType<Map>()
              .map((row) => AppNotification.fromJson(
                    Map<String, dynamic>.from(row),
                  ))
              .toList()
          : const [],
      unseenCount: asInt(data['unseenCount']) ?? 0,
    );
  }

  Future<void> markAllSeen() => _api.post('/api/notifications/mark-seen');

  Future<void> markRead(String id) =>
      _api.post('/api/notifications/mark-read/$id');

  Future<void> markAllRead() => _api.post('/api/notifications/mark-read/all');
}
