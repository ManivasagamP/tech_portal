import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/storage/session_store.dart';
import 'providers.dart';

class AuthState {
  const AuthState({
    this.session,
    this.permissions = const Permissions(),
    this.isBusy = false,
    this.error,
    this.sessionExpired = false,
  });

  final Session? session;
  final Permissions permissions;
  final bool isBusy;
  final String? error;
  final bool sessionExpired;

  bool get isAuthenticated => session != null && session!.userId.isNotEmpty;

  AuthState copyWith({
    Session? session,
    Permissions? permissions,
    bool? isBusy,
    String? error,
    bool? sessionExpired,
    bool clearSession = false,
    bool clearError = false,
  }) =>
      AuthState(
        session: clearSession ? null : (session ?? this.session),
        permissions: permissions ?? this.permissions,
        isBusy: isBusy ?? this.isBusy,
        error: clearError ? null : (error ?? this.error),
        sessionExpired: sessionExpired ?? this.sessionExpired,
      );
}

class AuthController extends Notifier<AuthState> {
  StreamSubscription<void>? _expirySub;

  @override
  AuthState build() {
    final store = ref.read(sessionStoreProvider);
    _expirySub ??= ref.read(apiClientProvider).onSessionExpired.listen((_) {
      state = state.copyWith(sessionExpired: true);
    });
    ref.onDispose(() => _expirySub?.cancel());

    return AuthState(
      session: store.readSession(),
      permissions: store.readPermissions(),
    );
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final repo = ref.read(authRepositoryProvider);
      final result = await repo.login(username: username, password: password);

      await ref.read(secureStoreProvider).writeToken(result.token);
      final store = ref.read(sessionStoreProvider);
      await store.writeSession(result.session);

      var permissions = const Permissions();
      try {
        permissions = await repo.fetchPermissions();
        await store.writePermissions(permissions);
      } on ApiFailure {
        // Config is advisory; a failure here must not block sign-in.
      }

      state = AuthState(session: result.session, permissions: permissions);
      ref.read(syncClientProvider).startAutoFlush();
      return true;
    } on ApiFailure catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    }
  }

  Future<void> logout() async {
    await ref.read(secureStoreProvider).clear();
    await ref.read(sessionStoreProvider).clear();
    await ref.read(offlineDbProvider).wipe();
    state = const AuthState();
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
