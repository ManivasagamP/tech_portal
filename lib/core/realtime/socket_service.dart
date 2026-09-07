import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../domain/app_notification.dart';

/// The server's live channel. It carries one event this app cares about,
/// `new_notification`, and only while the app is running and connected —
/// there is no push infrastructure behind it, so nothing arrives when the app
/// is closed.
class SocketService {
  SocketService({
    required this.baseUrl,
    required this.onNotification,
  });

  final String baseUrl;
  final void Function(AppNotification) onNotification;

  io.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  /// Opens the connection for one signed-in technician. Calling it again with a
  /// different token replaces the connection rather than stacking a second one.
  void connect(String token) {
    if (token.isEmpty) return;
    disconnect();

    // The API base may carry an `/api` suffix; the socket server is mounted at
    // the root, same as the web client's `SOCKET_URL.replace("/api", "")`.
    final url = baseUrl.replaceAll('/api', '');

    final socket = io.io(
      url,
      io.OptionBuilder()
          // Websocket first, long-polling as the fallback — a phone on a weak
          // mobile network often cannot hold a websocket open.
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );

    socket.on('new_notification', (data) {
      if (data is! Map) return;
      onNotification(
        AppNotification.fromJson(Map<String, dynamic>.from(data)),
      );
    });

    _socket = socket;
  }

  void disconnect() {
    final socket = _socket;
    if (socket == null) return;
    _socket = null;
    socket.clearListeners();
    socket.dispose();
  }
}
