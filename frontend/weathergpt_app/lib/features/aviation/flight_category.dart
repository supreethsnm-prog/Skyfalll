/// Maps a METAR flight category — `VFR` / `MVFR` / `IFR` / `LIFR`, the
/// four values `GET /metar`'s `flight_category` is documented to send —
/// onto the CAP severity vocabulary `AppColors.alertSeverity` already
/// understands, so the aviation screen can colour the category with the
/// app's one existing severity ramp instead of inventing a second one.
/// Mirrors `../advisory/risk_band.dart`'s `capSeverityForRiskBand` exactly.
///
/// Returns null for anything else, INCLUDING null itself — a station that
/// reported enough to derive a category but produced a string this mapping
/// has never seen, and a station that could not derive a category at all
/// (nullable in `MetarReading`), are both cases where the risk is unknown
/// rather than known-safe. Matching is deliberately exact-case: the backend
/// contract guarantees uppercase, so a differently-cased string is itself a
/// signal something is wrong upstream and must not be silently accepted.
///
/// A caller MUST treat a null result as "no reading" and render neutrally
/// — never fall back to a real category's colour, and especially never to
/// `minor` (VFR's colour), which would under-report unknown or degraded
/// conditions as good ones. Under-reporting is the one mistake a
/// disaster-advisory screen cannot make.
String? capSeverityForFlightCategory(String? category) {
  switch (category) {
    case 'VFR':
      return 'minor';
    case 'MVFR':
      return 'moderate';
    case 'IFR':
      return 'severe';
    case 'LIFR':
      return 'extreme';
    default:
      return null;
  }
}
