import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/socket_service.dart';
import 'auth_controller.dart';
import 'notifications_controller.dart';
import 'providers.dart';

/// Holds the live connection open for as long as somebody is signed in, and
/// feeds anything that arrives into the notification list and the bell.
///
/// Watched by the shell rather than by a screen: a notification that arrives
/// while the technician is on the checklist still has to bump the badge.
final socketConnectionProvider = Provider<SocketService>((ref) {
  final service = SocketService(
    baseUrl: ref.watch(apiClientProvider).baseUrl,
    onNotification: (notification) {
      // The list may not have been opened yet; the controller ignores the
      // prepend in that case and the fresh count below still lands.
      ref.read(notificationsControllerProvider.notifier).prepend(notification);
      ref.invalidate(unseenNotificationCountProvider);
    },
  );

  // Sign-in opens the connection, sign-out closes it. Reconnection inside a
  // session is the socket client's own business.
  ref.listen<bool>(
    authControllerProvider.select((state) => state.isAuthenticated),
    (previous, next) {
      if (next) {
        unawaited(_connect(ref, service));
      } else {
        service.disconnect();
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(service.disconnect);
  return service;
});

Future<void> _connect(Ref ref, SocketService service) async {
  final token = await ref.read(secureStoreProvider).readToken();
  if (token == null || token.isEmpty) return;
  service.connect(token);
}
