import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _tokenKey = 'token';

  final FlutterSecureStorage _storage;
  String? _cachedToken;

  Future<String?> readToken() async {
    _cachedToken ??= await _storage.read(key: _tokenKey);
    return _cachedToken;
  }

  Future<void> writeToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clear() async {
    _cachedToken = null;
    await _storage.delete(key: _tokenKey);
  }
}
