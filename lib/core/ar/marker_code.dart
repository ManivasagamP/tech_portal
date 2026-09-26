/// AR marker codes (docs/ar-markers-and-qr.md §2, CONTRACT C1). Mirrors the
/// server's `markerCodeService.ts`; both assert the same golden codes.
///
/// A code is 6 Crockford base32 characters plus one **check character** from
/// the same alphabet: `ALPHABET[Σ (2i+1) · indexOf(cᵢ) mod 32]`. Odd weights
/// are coprime with 32, so any single wrong character changes the check. The
/// check deliberately stays inside the alphabet (Crockford's own `~ = $ * U`
/// check symbols are not QR-alphanumeric and would push the printed QR out of
/// version 2).
///
/// - Canonical (stored, sent to every API): 7 upper-case chars, no hyphen,
///   `7K3QX9R`.
/// - Display: `7K3QX9-R`.
/// - QR payload: `HTTPS://<WEB_HOST>/M/7K3QX9-R`, upper case so the QR stays
///   in alphanumeric mode.
///
/// Design mockups show `7K3QX9-M`; that is sample text. The real check for
/// `7K3QX9` is `R`.
abstract final class MarkerCode {
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// `/m/<code>` anywhere after any http(s) host, any case, optional trailing
  /// slash, query or fragment. Host is deliberately not checked: printed
  /// boards outlive a domain change, and the check character (not the host)
  /// is what makes a code "ours".
  static final _url = RegExp(
    r'^https?://[^/\s]+/m/([0-9a-z\- ]+?)/?(?:[?#].*)?$',
    caseSensitive: false,
  );

  /// Check character for a 6-character body. Throws [ArgumentError] for a
  /// body that is not 6 alphabet characters — callers normalising user or
  /// scanner input go through [normalize], which never throws.
  static String checkChar(String code6) {
    if (code6.length != 6) {
      throw ArgumentError.value(code6, 'code6', 'must be 6 characters');
    }
    var sum = 0;
    for (var i = 0; i < 6; i++) {
      final index = alphabet.indexOf(code6[i]);
      if (index < 0) {
        throw ArgumentError.value(code6, 'code6', 'not Crockford base32');
      }
      sum += (2 * i + 1) * index;
    }
    return alphabet[sum % 32];
  }

  /// Canonical 7-char code, or null when [raw] is not a valid marker code.
  ///
  /// Trims, upper-cases, drops whitespace and hyphens, maps the look-alikes
  /// Crockford allows (`O → 0`, `I`/`L → 1`), rejects `U`, and requires 7
  /// characters with a matching check. A bad check means "not a marker", not
  /// "a marker we don't know": it is almost always a misread or somebody
  /// else's code, and must fall through to the other scanners.
  static String? normalize(String raw) {
    final cleaned = raw
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');
    if (cleaned.length != 7) return null;
    for (var i = 0; i < 7; i++) {
      if (!alphabet.contains(cleaned[i])) return null; // includes U
    }
    return checkChar(cleaned.substring(0, 6)) == cleaned[6] ? cleaned : null;
  }

  /// True only for an already-canonical code (7 upper-case chars, valid
  /// check). Use [normalize] for anything a person typed or a camera read.
  static bool isValid(String code7) =>
      code7.length == 7 && normalize(code7) == code7;

  /// `7K3QX9R → 7K3QX9-R`. Accepts any form [normalize] accepts; anything
  /// else is returned upper-cased and unchanged rather than throwing, so a
  /// bad value from the server still renders as *something* on screen.
  static String display(String code7) {
    final canonical = normalize(code7);
    if (canonical == null) return code7.trim().toUpperCase();
    return '${canonical.substring(0, 6)}-${canonical[6]}';
  }

  /// A scanned QR payload or typed text → canonical code, or null when it is
  /// not a FusionEco marker.
  ///
  /// Accepts the board URL in any case, over http or https, on any host
  /// (`HTTPS://FE.EXAMPLE/M/7K3QX9-R`, `https://dev.eco.x.com/m/7k3qx9r`),
  /// and — when [allowBare] — a bare code (`7K3QX9-R`, `7k3qx9r`).
  ///
  /// The scanner runs this **before** the C2O and general schemes (CONTRACT
  /// C9), so a URL that *looks* like a board but fails the check returns null
  /// and falls through, like any other foreign code. Pass `allowBare: false`
  /// from a general-purpose scanner if a 7-character asset plate could be
  /// mistaken for a code: about 1 in 32 random 7-character alphanumeric
  /// strings passes the check.
  static String? fromScan(String raw, {bool allowBare = true}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final match = _url.firstMatch(trimmed);
    if (match != null) return normalize(match.group(1)!);
    if (trimmed.contains('://')) return null; // some other link
    return allowBare ? normalize(trimmed) : null;
  }

  /// The label printed on a spare board: `SP-` + the first 4 characters.
  static String spareLabel(String code7) {
    final canonical = normalize(code7) ?? code7.trim().toUpperCase();
    final head = canonical.length >= 4 ? canonical.substring(0, 4) : canonical;
    return 'SP-$head';
  }

  /// The upper-case QR payload for [code7] on [webHost] (no scheme). Only
  /// the web admin prints boards; the app needs this for the fake engine's
  /// demo sightings and for tests.
  static String qrPayload(String code7, {required String webHost}) =>
      'HTTPS://${webHost.toUpperCase()}/M/${display(code7)}';
}
