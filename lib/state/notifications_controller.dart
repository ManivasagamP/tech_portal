import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_notification.dart';
import 'providers.dart';

class NotificationsState {
  const NotificationsState({
    this.notifications = const [],
    this.unseenCount = 0,
  });

  final List<AppNotification> notifications;
  final int unseenCount;
}

class NotificationsController extends AsyncNotifier<NotificationsState> {
  var _disposed = false;

  @override
  Future<NotificationsState> build() {
    ref.onDispose(() => _disposed = true);
    return _load();
  }

  Future<NotificationsState> _load() async {
    final page = await ref.read(notificationsRepositoryProvider).list(limit: 50);
    return NotificationsState(
      notifications: page.notifications,
      unseenCount: page.unseenCount,
    );
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(_load);
    if (_disposed) return;
    state = next;
  }

  /// Opening the list is what "seen" means — it clears the bell's count while
  /// leaving each notification unread until it is actually opened.
  Future<void> markAllSeen() async {
    // The screen asks for this on its first frame, while the list is very
    // likely still loading. Waiting for it means the badge actually clears
    // instead of silently doing nothing on the one open that matters.
    if (state.isLoading) {
      await future.catchError((_) => const NotificationsState());
    }
    final current = state.valueOrNull;
    if (current == null || current.unseenCount == 0) return;

    state = AsyncData(
      NotificationsState(notifications: current.notifications, unseenCount: 0),
    );
    try {
      await ref.read(notificationsRepositoryProvider).markAllSeen();
    } catch (_) {
      // The count is cosmetic; a failed call is not worth interrupting anyone.
    }
    ref.invalidate(unseenNotificationCountProvider);
  }

  Future<void> markRead(String id) async {
    _patch((n) => n.id == id ? _copyRead(n) : n);
    try {
      await ref.read(notificationsRepositoryProvider).markRead(id);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    _patch(_copyRead);
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
    } catch (_) {
      await refresh();
    }
  }

  /// A `new_notification` arriving over the socket while the app is open.
  /// Prepended rather than refetched — the payload is the whole notification.
  void prepend(AppNotification notification) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.notifications.any((n) => n.id == notification.id)) return;

    state = AsyncData(
      NotificationsState(
        notifications: [notification, ...current.notifications],
        unseenCount: current.unseenCount + 1,
      ),
    );
  }

  void _patch(AppNotification Function(AppNotification) transform) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      NotificationsState(
        notifications: current.notifications.map(transform).toList(),
        unseenCount: current.unseenCount,
      ),
    );
  }

  static AppNotification _copyRead(AppNotification n) => AppNotification(
        id: n.id,
        title: n.title,
        message: n.message,
        type: n.type,
        category: n.category,
        entityId: n.entityId,
        entityType: n.entityType,
        link: n.link,
        isSeen: true,
        isRead: true,
        createdAt: n.createdAt,
      );
}

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, NotificationsState>(
  NotificationsController.new,
);
