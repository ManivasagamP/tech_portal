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

  /// The gate in `middleware/auth.ts` rejecting a mutating request because
  /// the technician's last GPS fix is stale — see `ApiClient.onLocationRequired`.
  bool get isLocationRequired => status == 428;

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
  final status = response.statusCode ?? 0;
  var message = status >= 500
      ? 'Server is temporarily unavailable. Please try again in a moment.'
      : 'Something went wrong. Please try again.';
  var missing = <String>[];

  if (data is Map) {
    final raw = data['message'] ?? data['error'];
    if (raw is String && raw.isNotEmpty) message = raw;
    final rawMissing = data['missing'];
    if (rawMissing is List) {
      missing = rawMissing.map((e) => e.toString()).toList();
    }
  } else if (data is String && data.isNotEmpty && !_looksLikeMarkup(data)) {
    message = data;
  }

  return HttpFailure(
    status: status,
    message: message,
    missing: missing,
    body: data,
  );
}

/// Reverse-proxy/gateway failures (a 502/504 from nginx/openresty in front of
/// the API) answer with an HTML error page instead of JSON — that raw markup
/// must never reach a technician as the error text.
bool _looksLikeMarkup(String data) {
  final trimmed = data.trimLeft().toLowerCase();
  return trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');
}
