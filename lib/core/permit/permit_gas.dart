import '../../domain/permit.dart';

/// Permit to Work — live gas colouring (docs/permit-to-work.md). This is the
/// **one** rule this app computes on the device rather than reading off the
/// server's `readiness` object: judging a reading the technician is about to
/// submit against [GasProfile.limits] as they type it, so the gas-test sheet
/// can colour O2/LEL/H2S/CO red or green *before* the network round trip.
/// Everything else about a permit — can it be issued, closed, extended — is
/// the server's call; see `domain/permit.dart`'s doc comment.
///
/// The server re-judges the same reading on `POST /:id/gas-tests` and is the
/// only source of truth for what actually gets recorded (including whether
/// it auto-suspends the permit); a disagreement here is a display bug, never
/// a safety decision.
enum GasReadingVerdict { pass, fail, unknown }

class GasReadingResult {
  const GasReadingResult({required this.verdict, required this.message});

  final GasReadingVerdict verdict;
  final String message;

  bool get isPass => verdict == GasReadingVerdict.pass;
  bool get isFail => verdict == GasReadingVerdict.fail;
  bool get isUnknown => verdict == GasReadingVerdict.unknown;
}

abstract final class PermitGas {
  /// Judges [value] against [limit]'s **inclusive** min/max band — a reading
  /// exactly on the boundary passes. Either bound may be absent (O2 usually
  /// has both; LEL/H2S/CO usually only a `max`). Null [value] is "not tested
  /// yet", not a failure: an untested gas must never render as a red fail
  /// chip before the technician has even taken the reading.
  static GasReadingResult evaluate(GasLimit limit, double? value) {
    if (value == null) {
      return const GasReadingResult(
        verdict: GasReadingVerdict.unknown,
        message: 'Not tested yet',
      );
    }
    if (limit.min != null && value < limit.min!) {
      return GasReadingResult(
        verdict: GasReadingVerdict.fail,
        message: '${limit.label} is below the minimum of ${_fmt(limit.min!)} ${limit.unit}',
      );
    }
    if (limit.max != null && value > limit.max!) {
      return GasReadingResult(
        verdict: GasReadingVerdict.fail,
        message: '${limit.label} is above the maximum of ${_fmt(limit.max!)} ${limit.unit}',
      );
    }
    return const GasReadingResult(verdict: GasReadingVerdict.pass, message: 'Within limits');
  }

  /// One verdict per gas the permit's [profile] judges, keyed by gas code
  /// (`o2`, `lel`, `h2s`, `co`) — the gas-test sheet's live chip row.
  static Map<String, GasReadingResult> evaluateAll(
    GasProfile profile,
    Map<String, double?> readings,
  ) => {for (final limit in profile.limits) limit.gas: evaluate(limit, readings[limit.gas])};

  /// The sheet's overall pass/fail banner. Passes only when **every** limit
  /// in [profile] has been read AND is within band — one untested or failing
  /// gas fails the whole test, mirroring the server's `evaluateGasTest`. A
  /// profile with no limits at all (a permit type with no gas requirement)
  /// trivially passes.
  static bool overallPass(GasProfile profile, Map<String, double?> readings) {
    for (final limit in profile.limits) {
      if (!evaluate(limit, readings[limit.gas]).isPass) return false;
    }
    return true;
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// `https://<host>/permit-check/<token>` anywhere after any http(s) host,
/// any case, optional trailing slash, query or fragment — the worksite QR
/// printed on the permit certificate (`permitCheckPath` in permits.ts).
/// Mirrors `MarkerCode.fromScan`'s URL matching (core/ar/marker_code.dart):
/// the host is deliberately not checked, so a printed certificate keeps
/// working across a domain change.
final _permitCheckUrl = RegExp(
  r'^https?://[^/\s]+/permit-check/([^/\s?#]+)/?(?:[?#].*)?$',
  caseSensitive: false,
);

/// A scanned QR value → the permit-check token, or null when [raw] is not a
/// worksite permit QR. The token itself is base64url and case-sensitive, so
/// unlike [MarkerCode] this never upper-cases or otherwise normalises it.
String? permitCheckTokenFromScan(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final match = _permitCheckUrl.firstMatch(trimmed);
  if (match == null) return null;
  final token = match.group(1);
  return (token == null || token.isEmpty) ? null : token;
}
