/// FR-1.5 — turns raw OCR text off a nameplate photo into pre-fill guesses.
/// Deliberately a plain string-in, struct-out function with no ML Kit
/// dependency: the recognizer is unreliable in ways worth testing without a
/// device, and this is the part that decides what goes in front of the
/// technician, who is the one who actually confirms it.
///
/// Never treat a field here as ground truth — it is always a guess shown in
/// an editable box. A machine reading the same plate the register was built
/// from proves nothing about whether the physical asset matches; only the
/// technician's own judgement does.
class NameplateFields {
  const NameplateFields({this.manufacturer, this.model, this.serial});

  final String? manufacturer;
  final String? model;
  final String? serial;

  bool get isEmpty => manufacturer == null && model == null && serial == null;
}

const _serialLabels = ['S/N', 'SERIAL NO', 'SERIAL NUMBER', 'SERIAL', 'SER NO', 'SN'];
const _modelLabels = ['MODEL NO', 'MODEL NUMBER', 'MODEL', 'MDL', 'TYPE'];
const _manufacturerLabels = ['MANUFACTURED BY', 'MANUFACTURER', 'MFG BY', 'MADE BY', 'MFR'];
final _allLabels = [..._serialLabels, ..._modelLabels, ..._manufacturerLabels];

NameplateFields extractNameplateFields(String rawText) {
  final lines = rawText
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  String? manufacturer;
  String? model;
  String? serial;

  for (var i = 0; i < lines.length; i++) {
    serial ??= _labelledValue(lines, i, _serialLabels);
    model ??= _labelledValue(lines, i, _modelLabels);
    manufacturer ??= _labelledValue(lines, i, _manufacturerLabels);
  }

  // Nameplate convention when no explicit "Mfr:" label is printed: the brand
  // name is the first legible line — the logo text at the top of the plate.
  manufacturer ??= lines.isNotEmpty ? lines.first : null;

  return NameplateFields(manufacturer: manufacturer, model: model, serial: serial);
}

/// Looks for one of [labels] on `lines[index]`. The value is either the rest
/// of that same line after the label ("S/N: 27673571") or, when the label
/// sits alone on its line, the line right after it — a layout nameplates use
/// often enough to be worth the one-line lookahead.
String? _labelledValue(List<String> lines, int index, List<String> labels) {
  final line = lines[index];
  final upper = line.toUpperCase();

  // Longest first: "SERIAL NUMBER" must win over the "SERIAL" it contains,
  // or a bare label with no value ("Serial Number" on its own line, next
  // line rejected as another label) falls through to the shorter label and
  // grabs the tail of its own text ("Number") as a fake value.
  final sorted = [...labels]..sort((a, b) => b.length.compareTo(a.length));

  for (final label in sorted) {
    final at = upper.indexOf(label);
    if (at == -1) continue;

    final rest = line.substring(at + label.length).replaceFirst(RegExp(r'^[\s:.\-=]+'), '').trim();
    if (rest.isNotEmpty) return rest;

    if (index + 1 < lines.length) {
      final next = lines[index + 1];
      final isAnotherLabel = _allLabels.any((l) => next.toUpperCase().contains(l));
      if (!isAnotherLabel) return next;
    }
    // The label matched but produced no usable value — stop here rather
    // than trying a weaker, overlapping label against the same line.
    return null;
  }
  return null;
}
