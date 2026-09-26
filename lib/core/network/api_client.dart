// ignore_for_file: prefer_initializing_formals — named params cannot be private
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../app/env.dart';
import '../storage/secure_store.dart';
import 'api_exception.dart';

const kMutationIdHeader = 'X-Client-Mutation-Id';

/// NFR-10 — a stable per-install id, so a queued/synced check is
/// attributable to the device it was captured on as well as the person
/// signed in at the time (the `Authorization` bearer token, which the
/// server already resolves to a technician). Read once and cached in
/// memory for the life of the client; [SecureStore.getOrCreateDeviceId]
/// mints it once per install and it outlives every sign-out.
const kDeviceIdHeader = 'X-Device-Id';

/// Dio wrapper carrying the two things the server cares about: a bearer token and
/// a stable mutation id for idempotent replays.
class ApiClient {
  ApiClient({required SecureStore secureStore, String? baseUrl})
      : _secureStore = secureStore,
        _uuid = const Uuid() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? Env.defaultApiBaseUrl,
        connectTimeout: Env.connectTimeout,
        receiveTimeout: Env.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStore.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers[kDeviceIdHeader] ??= await _deviceId();
          if (options.method != 'GET' &&
              !options.headers.containsKey(kMutationIdHeader)) {
            options.headers[kMutationIdHeader] = _uuid.v4();
          }
          handler.next(options);
        },
        onError: (e, handler) {
          if (e.response?.statusCode == 401) {
            _sessionExpired.add(null);
          }
          if (e.response?.statusCode == 428) {
            _locationRequired.add(null);
          }
          handler.next(e);
        },
      ),
    );
  }

  late final Dio _dio;
  final SecureStore _secureStore;
  final Uuid _uuid;
  final _sessionExpired = StreamController<void>.broadcast();
  final _locationRequired = StreamController<void>.broadcast();
  Future<String>? _deviceIdFuture;

  /// Fetched (and minted, on first-ever call) once per app run, not once
  /// per request — every request after the first reuses the same in-flight
  /// or completed future instead of hitting secure storage again.
  Future<String> _deviceId() =>
      _deviceIdFuture ??= _secureStore.getOrCreateDeviceId();

  Dio get raw => _dio;
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  /// Fires on every HTTP 428 (`LOCATION_REQUIRED`) — the server-side gate in
  /// `middleware/auth.ts` rejecting a mutating request because the
  /// technician's last GPS fix is stale. Mirrors `onSessionExpired`'s shape.
  Stream<void> get onLocationRequired => _locationRequired.stream;
  String get baseUrl => _dio.options.baseUrl;

  set baseUrl(String value) => _dio.options.baseUrl = value;

  String newMutationId() => _uuid.v4();

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) =>
      _run(() => _dio.get(
            path,
            queryParameters: query,
            options: Options(receiveTimeout: receiveTimeout),
          ));

  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    String? mutationId,
    Duration? receiveTimeout,
  }) =>
      _run(() => _dio.post(
            path,
            data: data,
            queryParameters: query,
            options: _mutationOptions(mutationId, receiveTimeout),
          ));

  Future<Response<dynamic>> put(
    String path, {
    dynamic data,
    String? mutationId,
  }) =>
      _run(() => _dio.put(
            path,
            data: data,
            options: _mutationOptions(mutationId, null),
          ));

  Future<Response<dynamic>> patch(
    String path, {
    dynamic data,
    String? mutationId,
  }) =>
      _run(() => _dio.patch(
            path,
            data: data,
            options: _mutationOptions(mutationId, null),
          ));

  Future<Response<dynamic>> delete(
    String path, {
    dynamic data,
    String? mutationId,
  }) =>
      _run(() => _dio.delete(
            path,
            data: data,
            options: _mutationOptions(mutationId, null),
          ));

  Future<Response<dynamic>> request(
    String method,
    String path, {
    dynamic data,
    String? mutationId,
  }) {
    switch (method.toLowerCase()) {
      case 'post':
        return post(path, data: data, mutationId: mutationId);
      case 'put':
        return put(path, data: data, mutationId: mutationId);
      case 'patch':
        return patch(path, data: data, mutationId: mutationId);
      case 'delete':
        return delete(path, data: data, mutationId: mutationId);
      default:
        return get(path);
    }
  }

  Options _mutationOptions(String? mutationId, Duration? receiveTimeout) => Options(
        headers: mutationId == null ? null : {kMutationIdHeader: mutationId},
        receiveTimeout: receiveTimeout,
      );

  Future<Response<dynamic>> _run(Future<Response<dynamic>> Function() send) async {
    try {
      return await send();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  void dispose() {
    _sessionExpired.close();
    _locationRequired.close();
  }
}
