import 'package:dio/dio.dart';

sealed class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The request never reached a server (no response object). This is the offline
/// signal the sync engine keys off — it is the only failure that gets queued.
class NetworkFailure extends ApiFailure {
  const NetworkFailure([super.message = 'No connection']);
}

/// The server answered. Replaying it would fail the same way, so it is never queued.
class HttpFailure extends ApiFailure {
  const HttpFailure({
    required this.status,
    required String message,
    this.missing = const [],
    this.body,
  }) : super(message);

  final int status;

  /// Populated by the 422 close gates: `["rootCause"]` or `["checklist"]`.
  final List<String> missing;
  final dynamic body;

  bool get isUnauthorized => status == 401;

  /// The server rejects a duplicate close with 400 "…already completed"; the web
  /// client treats that as success because an offline replay is not a failure.
  bool get isAlreadyCompleted =>
      status == 400 &&
      RegExp(
        r'already (completed|been started or completed)',
        caseSensitive: false,
      ).hasMatch(message);
}

class UnknownFailure extends ApiFailure {
  const UnknownFailure([super.message = 'Something went wrong']);
}

ApiFailure mapDioException(DioException e) {
  final response = e.response;
  if (response == null) {
    return NetworkFailure(e.message ?? 'No connection');
  }
  final data = response.data;
  var message = 'Something went wrong. Please try again.';
  var missing = <String>[];

  if (data is Map) {
    final raw = data['message'] ?? data['error'];
    if (raw is String && raw.isNotEmpty) message = raw;
    final rawMissing = data['missing'];
    if (rawMissing is List) {
      missing = rawMissing.map((e) => e.toString()).toList();
    }
  } else if (data is String && data.isNotEmpty) {
    message = data;
  }

  return HttpFailure(
    status: response.statusCode ?? 0,
    message: message,
    missing: missing,
    body: data,
  );
}
