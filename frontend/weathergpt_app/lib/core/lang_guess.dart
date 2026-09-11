/// Offline script guess for read-aloud fallback. Returns a Bhashini code
/// only for unambiguous unique scripts; Devanagari (hi/mr/ne/...) and
/// Perso-Arabic (ur/ks/sd) are deliberately ambiguous and return null so
/// callers fall back to the stored per-message language, then global.
/// Old chats have no stored language — this is their only signal.
String? guessLanguageFromScript(String text) {
  final counts = <String, int>{};
  void bump(String k) => counts[k] = (counts[k] ?? 0) + 1;

  for (final unit in text.codeUnits) {
    final isLatin = (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
    if (isLatin) {
      bump('en');
    } else if (unit >= 0x0C80 && unit <= 0x0CFF) {
      bump('kn');
    } else if (unit >= 0x0C00 && unit <= 0x0C7F) {
      bump('te');
    } else if (unit >= 0x0B80 && unit <= 0x0BFF) {
      bump('ta');
    } else if (unit >= 0x0D00 && unit <= 0x0D7F) {
      bump('ml');
    } else if (unit >= 0x0980 && unit <= 0x09FF) {
      bump('bn');
    } else if (unit >= 0x0A80 && unit <= 0x0AFF) {
      bump('gu');
    } else if (unit >= 0x0A00 && unit <= 0x0A7F) {
      bump('pa');
    } else if (unit >= 0x0B00 && unit <= 0x0B7F) {
      bump('or');
    }
    // Devanagari (0x0900-0x097F) and Perso-Arabic (0x0600-0x077F) skipped
    // on purpose: shared by several languages, never a unique answer.
  }
  if (counts.isEmpty) return null;
  var best = counts.entries.first;
  for (final e in counts.entries) {
    if (e.value > best.value) best = e;
  }
  return best.key;
}
