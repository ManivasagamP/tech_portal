import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _tokenKey = 'token';

  /// NFR-10 — one id per install, outliving any sign-out/sign-in cycle
  /// (unlike [_tokenKey], never touched by [clear]) so every check this
  /// phone ever queues or sends can be traced back to the device it came
  /// from, not just the technician who happened to be signed in.
  static const _deviceIdKey = 'device_id';

  /// FR-4.1/NFR-1 — the SQLCipher passphrase for `OfflineDb`, which holds
  /// cached assets, the mutation queue and queued photo blobs. Generated
  /// once per install and kept in the platform keystore (Android
  /// EncryptedSharedPreferences / iOS Keychain) — never in the database
  /// file itself, or on the wire, or in app code.
  static const _dbPassphraseKey = 'offline_db_passphrase';

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

  /// Returns the existing passphrase, or mints and stores a fresh 256-bit
  /// one on first launch. Losing this (a keystore wipe, an uninstall) makes
  /// the existing database file unreadable rather than silently corrupting
  /// it — `OfflineDb.open()` falling over in that case means "start a fresh
  /// queue," the same outcome as a plain uninstall already has today.
  /// FR-4.4 — read-only twin of [getOrCreateDbPassphrase] for the background
  /// sync engine, which must never create a passphrase of its own.
  Future<String?> readDbPassphrase() async {
    final existing = await _storage.read(key: _dbPassphraseKey);
    return existing == null || existing.isEmpty ? null : existing;
  }

  Future<String> getOrCreateDbPassphrase() async {
    final existing = await _storage.read(key: _dbPassphraseKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final passphrase = base64UrlEncode(bytes);
    await _storage.write(key: _dbPassphraseKey, value: passphrase);
    return passphrase;
  }

  /// Returns this install's device id, minting a fresh one on first launch.
  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }

  Future<void> clear() async {
    _cachedToken = null;
    await _storage.delete(key: _tokenKey);
  }
}
