/// Maps an advisory risk band — `LOW` / `MODERATE` / `HIGH` / `SEVERE`,
/// the four values `GET /advisory/urban`'s `risk_summary` is documented to
/// send — onto the CAP severity vocabulary `AppColors.alertSeverity`
/// already understands, so the advisory screen can colour a risk tile with
/// the app's one existing severity ramp instead of inventing a second one.
///
/// Returns null for anything else, including the backend's own `UNKNOWN`
/// (emitted when there was no forecast to compute a band from) and any
/// value this mapping has never seen. Matching is deliberately exact-case:
/// the backend contract guarantees uppercase, so a lowercase or
/// differently-cased string is itself a signal something is wrong upstream
/// and must not be silently accepted.
///
/// A caller MUST treat a null result as "no reading" and render neutrally
/// — never fall back to a real band's colour, and especially never to
/// `minor` (LOW's colour), which would under-report an unknown risk as a
/// known-safe one. Under-reporting is the one mistake a disaster-advisory
/// screen cannot make.
String? capSeverityForRiskBand(String band) {
  switch (band) {
    case 'LOW':
      return 'minor';
    case 'MODERATE':
      return 'moderate';
    case 'HIGH':
      return 'severe';
    case 'SEVERE':
      return 'extreme';
    default:
      return null;
  }
}
