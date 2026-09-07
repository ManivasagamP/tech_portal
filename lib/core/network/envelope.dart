/// The API ships four response shapes: `{success,data}`, `{message,data}`,
/// `{data}` and a raw record (preventive detail). One tolerant unwrapper.
dynamic unwrap(dynamic body) {
  if (body is Map && body.containsKey('data')) return body['data'];
  return body;
}

Map<String, dynamic> unwrapMap(dynamic body) {
  final data = unwrap(body);
  return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
}

List<Map<String, dynamic>> unwrapList(dynamic body) {
  final data = unwrap(body);
  if (data is List) {
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const [];
}

/// Sequelize returns DECIMAL columns as strings and FLOAT columns as numbers.
double? asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? asInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool? asBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = value.toString().toLowerCase();
  if (s == 'true') return true;
  if (s == 'false') return false;
  return null;
}

/// Every date on the wire is ISO-8601 UTC with a trailing Z.
DateTime? asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

/// First non-empty value in a fallback chain, mirroring the web renderers.
String? firstNonEmpty(List<dynamic> candidates) {
  for (final c in candidates) {
    if (c == null) continue;
    final s = c.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}
