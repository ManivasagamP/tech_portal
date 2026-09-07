import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Identity as the API needs it. `userId` is the technician UUID and is what every
/// `/technician/:id` call takes; `technicianId` (TECH001) is display only.
class Session {
  const Session({
    required this.userId,
    required this.name,
    this.technicianId,
    this.email,
    this.username,
    this.department,
    this.partnerRole,
    this.vendorId,
    this.loginAt,
  });

  final String userId;
  final String name;
  final String? technicianId;
  final String? email;
  final String? username;
  final String? department;
  final String? partnerRole;
  final String? vendorId;
  final DateTime? loginAt;

  bool get isInHouse => partnerRole == null || partnerRole == 'in-house';

  /// Session is valid for 24 hours from login
  bool get isExpired {
    if (loginAt == null) return false;
    return DateTime.now().difference(loginAt!) >= const Duration(hours: 24);
  }

  Duration get remainingValidity {
    if (loginAt == null) return const Duration(hours: 24);
    final remaining = const Duration(hours: 24) - DateTime.now().difference(loginAt!);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory Session.fromLoginResponse(Map<String, dynamic> technician) => Session(
        userId: technician['id']?.toString() ?? '',
        name: technician['name']?.toString() ?? '',
        technicianId: technician['technicianId']?.toString(),
        email: technician['email']?.toString(),
        username: technician['username']?.toString(),
        department: technician['department']?.toString(),
        partnerRole: technician['partnerRole']?.toString(),
        vendorId: technician['vendorId']?.toString(),
        loginAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'technicianId': technicianId,
        'email': email,
        'username': username,
        'department': department,
        'partnerRole': partnerRole,
        'vendorId': vendorId,
        'loginAt': (loginAt ?? DateTime.now()).toIso8601String(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        userId: json['userId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        technicianId: json['technicianId']?.toString(),
        email: json['email']?.toString(),
        username: json['username']?.toString(),
        department: json['department']?.toString(),
        partnerRole: json['partnerRole']?.toString(),
        vendorId: json['vendorId']?.toString(),
        loginAt: json['loginAt'] != null
            ? DateTime.tryParse(json['loginAt'].toString())
            : null,
      );
}

/// Feature flags from GET /api/auth/config. Only these three reach the technician UI.
class Permissions {
  const Permissions({
    this.isAiAgent = false,
    this.currencyType,
    this.currencyRates = const {},
  });

  final bool isAiAgent;
  final String? currencyType;
  final Map<String, double> currencyRates;

  factory Permissions.fromJson(Map<String, dynamic> json) {
    final rates = <String, double>{};
    final raw = json['currencyRates'];
    if (raw is Map) {
      raw.forEach((key, value) {
        final parsed = value is num ? value.toDouble() : double.tryParse('$value');
        if (parsed != null) rates[key.toString()] = parsed;
      });
    }
    return Permissions(
      isAiAgent: json['isAiAgent'] == true,
      currencyType: json['currencyType']?.toString(),
      currencyRates: rates,
    );
  }

  Map<String, dynamic> toJson() => {
        'isAiAgent': isAiAgent,
        'currencyType': currencyType,
        'currencyRates': currencyRates,
      };
}

class SessionStore {
  SessionStore(this._prefs);

  static const _sessionKey = 'session';
  static const _sessionTimestampKey = 'session_timestamp';
  static const _permissionsKey = 'permissions';
  static const _baseUrlKey = 'apiBaseUrl';
  static const sessionDuration = Duration(hours: 24);

  final SharedPreferences _prefs;

  static Future<SessionStore> open() async =>
      SessionStore(await SharedPreferences.getInstance());

  Session? readSession() {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null) return null;

    // Check 24h validity via timestamp
    final savedTimeMs = _prefs.getInt(_sessionTimestampKey);
    if (savedTimeMs != null) {
      final savedTime = DateTime.fromMillisecondsSinceEpoch(savedTimeMs);
      if (DateTime.now().difference(savedTime) >= sessionDuration) {
        clear();
        return null;
      }
    }

    try {
      final session = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session.isExpired) {
        clear();
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSession(Session session) async {
    final now = session.loginAt ?? DateTime.now();
    await _prefs.setInt(_sessionTimestampKey, now.millisecondsSinceEpoch);
    await _prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Permissions readPermissions() {
    final raw = _prefs.getString(_permissionsKey);
    if (raw == null) return const Permissions();
    try {
      return Permissions.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Permissions();
    }
  }

  Future<void> writePermissions(Permissions permissions) =>
      _prefs.setString(_permissionsKey, jsonEncode(permissions.toJson()));

  String? readBaseUrlOverride() => _prefs.getString(_baseUrlKey);

  Future<void> writeBaseUrlOverride(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_baseUrlKey);
    } else {
      await _prefs.setString(_baseUrlKey, value);
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_sessionKey);
    await _prefs.remove(_sessionTimestampKey);
    await _prefs.remove(_permissionsKey);
  }
}
