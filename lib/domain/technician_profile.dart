import '../core/network/envelope.dart';

/// The identity half of `GET /api/analytics/technician/{userId}/profile`.
class TechnicianProfile {
  const TechnicianProfile({
    required this.name,
    this.email,
    this.phone,
    this.department,
    this.status,
    this.experienceYears,
    this.specialization = const [],
    this.certifications = const [],
  });

  final String name;
  final String? email;
  final String? phone;
  final String? department;
  final String? status;
  final double? experienceYears;

  /// Arrives as either a list or a single string, so both are accepted.
  final List<String> specialization;
  final List<String> certifications;

  factory TechnicianProfile.fromJson(Map<String, dynamic> json) =>
      TechnicianProfile(
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString(),
        phone: json['phone']?.toString(),
        department: json['department']?.toString(),
        status: json['status']?.toString(),
        experienceYears: asDouble(json['experience']),
        specialization: _stringList(json['specialization']),
        certifications: _stringList(json['certifications']),
      );

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final single = value?.toString().trim();
    return (single == null || single.isEmpty) ? const [] : [single];
  }
}

/// The performance half of the same response.
class TechnicianMetrics {
  const TechnicianMetrics({
    this.totalOrders = 0,
    this.completedOrders = 0,
    this.completionRate = 0,
    this.avgResolutionTime = 0,
    this.qualityScore = 0,
    this.customerSatisfaction = 0,
  });

  final int totalOrders;
  final int completedOrders;

  /// A percentage, already computed server-side.
  final double completionRate;
  final double avgResolutionTime;
  final double qualityScore;
  final double customerSatisfaction;

  factory TechnicianMetrics.fromJson(Map<String, dynamic> json) =>
      TechnicianMetrics(
        totalOrders: asInt(json['totalOrders']) ?? 0,
        completedOrders: asInt(json['completedOrders']) ?? 0,
        completionRate: asDouble(json['completionRate']) ?? 0,
        avgResolutionTime: asDouble(json['avgResolutionTime']) ?? 0,
        qualityScore: asDouble(json['qualityScore']) ?? 0,
        customerSatisfaction: asDouble(json['customerSatisfaction']) ?? 0,
      );
}

class TechnicianProfilePage {
  const TechnicianProfilePage({required this.profile, required this.metrics});

  final TechnicianProfile profile;
  final TechnicianMetrics metrics;
}
