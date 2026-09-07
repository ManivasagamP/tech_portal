import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analytics_repository.dart';
import '../domain/technician_profile.dart';
import 'auth_controller.dart';
import 'providers.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => AnalyticsRepository(ref.watch(apiClientProvider)),
);

/// Identity and performance for the signed-in technician. Online only: these
/// figures are read-only reporting, and a stale cached score is worse than an
/// honest "not available".
final technicianProfileProvider =
    FutureProvider<TechnicianProfilePage>((ref) async {
  final session = ref.watch(authControllerProvider).session;
  if (session == null || session.userId.isEmpty) {
    throw StateError('No signed-in technician');
  }
  return ref.watch(analyticsRepositoryProvider).profile(session.userId);
});
