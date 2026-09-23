import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capture/capture_services.dart' show CaptureFailure;
import '../core/location/checkin_location.dart';
import '../core/network/api_exception.dart';
import 'auth_controller.dart';
import 'providers.dart';

class CheckInState {
  const CheckInState({
    this.required = false,
    this.isChecking = false,
    this.error,
  });

  final bool required;
  final bool isChecking;
  final String? error;

  CheckInState copyWith({
    bool? required,
    bool? isChecking,
    String? error,
    bool clearError = false,
  }) =>
      CheckInState(
        required: required ?? this.required,
        isChecking: isChecking ?? this.isChecking,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Mirrors [AuthController]'s `onSessionExpired` wiring, but for the
/// location gate: `required` starts from the session's `requestLocation`
/// flag (set at login from the server's stale-fix check) and flips true
/// again mid-session on any `ApiClient.onLocationRequired` (HTTP 428) —
/// the server rejecting a mutating request because the fix has since gone
/// stale (>24h, `TECHNICIAN_LOCATION_STALE_MS`).
class CheckInController extends Notifier<CheckInState> {
  StreamSubscription<void>? _sub;

  @override
  CheckInState build() {
    final auth = ref.watch(authControllerProvider);
    final apiClient = ref.watch(apiClientProvider);

    _sub?.cancel();
    _sub = apiClient.onLocationRequired.listen((_) {
      state = state.copyWith(required: true);
    });
    ref.onDispose(() => _sub?.cancel());

    return CheckInState(required: auth.session?.requestLocation ?? false);
  }

  Future<void> checkIn() async {
    state = state.copyWith(isChecking: true, clearError: true);
    try {
      final position = await currentCheckInPosition();
      await ref
          .read(technicianLocationRepositoryProvider)
          .updateLocation(position.latitude, position.longitude);
      await ref.read(sessionStoreProvider).clearRequestLocation();
      state = state.copyWith(required: false, isChecking: false, clearError: true);
      // A stale fix is exactly what stopped `flushQueue` mid-run on a 428
      // (see `SyncClient.flushQueue`) — resume it now instead of leaving a
      // shift's queued checks stuck until the technician happens to open
      // Sync Center.
      unawaited(ref.read(syncClientProvider).flushQueue());
    } on CaptureFailure catch (e) {
      state = state.copyWith(isChecking: false, error: e.message);
    } on ApiFailure catch (e) {
      state = state.copyWith(isChecking: false, error: e.message);
    }
  }
}

final checkInControllerProvider = NotifierProvider<CheckInController, CheckInState>(
  CheckInController.new,
);
