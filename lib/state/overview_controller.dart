import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/technician_insights.dart';
import 'auth_controller.dart';
import 'profile_controller.dart';

/// Year-to-date counts, work in progress and the twelve-month trend for the
/// signed-in technician. Online only, like the profile figures: reporting is
/// read-only, and a stale cached chart is worse than an honest "not available".
final technicianInsightsProvider =
    FutureProvider<TechnicianInsights>((ref) async {
  final session = ref.watch(authControllerProvider).session;
  if (session == null || session.userId.isEmpty) {
    throw StateError('No signed-in technician');
  }
  return ref.watch(analyticsRepositoryProvider).insights(session.userId);
});
