import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/storage/session_store.dart';

class LoginResult {
  const LoginResult({required this.token, required this.session});
  final String token;
  final Session session;
}

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// POST /api/auth/technician-login — matches username OR email server-side.
  /// The response has no permissions block; fetch those separately.
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final response = await _api.post(
      '/api/auth/technician-login',
      data: {'username': username, 'password': password},
    );
    final body = response.data;
    if (body is! Map) {
      throw const UnknownFailure('Sign-in failed. Please try again.');
    }

    final token = body['token']?.toString();
    final technician = body['technician'];
    if (token == null || token.isEmpty || technician is! Map) {
      throw const UnknownFailure('Sign-in failed. Please try again.');
    }

    return LoginResult(
      token: token,
      session: Session.fromLoginResponse(Map<String, dynamic>.from(technician)),
    );
  }

  /// GET /api/auth/config returns the config object raw, not wrapped in `data`.
  Future<Permissions> fetchPermissions() async {
    final response = await _api.get('/api/auth/config');
    final body = response.data;
    if (body is Map) {
      return Permissions.fromJson(Map<String, dynamic>.from(body));
    }
    return const Permissions();
  }
}
