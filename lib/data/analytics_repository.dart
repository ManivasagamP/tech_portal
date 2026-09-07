import '../core/network/api_client.dart';
import '../core/network/envelope.dart';
import '../domain/technician_insights.dart';
import '../domain/technician_profile.dart';

class AnalyticsRepository {
  AnalyticsRepository(this._api);

  final ApiClient _api;

  /// One call answers both halves of the profile screen: who the technician is
  /// under `profile`, and how they are doing under `analytics`.
  Future<TechnicianProfilePage> profile(String technicianId) async {
    final response =
        await _api.get('/api/analytics/technician/$technicianId/profile');
    final data = unwrapMap(response.data);

    final profile = data['profile'];
    final analytics = data['analytics'];

    return TechnicianProfilePage(
      profile: TechnicianProfile.fromJson(
        profile is Map ? Map<String, dynamic>.from(profile) : const {},
      ),
      metrics: TechnicianMetrics.fromJson(
        analytics is Map ? Map<String, dynamic>.from(analytics) : const {},
      ),
    );
  }

  /// Counts and costs behind the overview tabs.
  ///
  /// The endpoint takes no date range — `getTechnicianInsights` reads the
  /// current year and month off the server clock — so there is nothing to
  /// pass and nothing for a month picker to change.
  Future<TechnicianInsights> insights(String technicianId) async {
    final response =
        await _api.get('/api/analytics/technician/$technicianId/insights');
    return TechnicianInsights.fromJson(unwrapMap(response.data));
  }
}
