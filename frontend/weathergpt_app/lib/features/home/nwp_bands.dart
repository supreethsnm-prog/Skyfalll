/// Pure CAPE/gust classification for the severe-weather panel. No widgets
/// here — the meteorology needs to be pinnable in tests independent of how
/// it is drawn, the same reason `risk_band.dart` is a separate file from
/// the advisory screen.
library;

/// CAPE (Convective Available Potential Energy, J/kg) bands, following the
/// widely-used operational convention (NOAA SPC's own thresholds, echoed
/// throughout the AMS glossary and IMD convective outlooks):
///
/// | CAPE (J/kg) | Band     |
/// |---|---|
/// | < 300       | Minimal  |
/// | 300–999     | Marginal |
/// | 1000–2499   | Moderate |
/// | 2500–3999   | Strong   |
/// | >= 4000     | Extreme  |
///
/// Returns null for a null CAPE reading. "Not modelled" must never be
/// classified as "Minimal" — that would assert calm conditions the model
/// never actually reported, exactly the failure mode the brief calls out
/// for this whole feature.
String? capeBand(double? capeJPerKg) {
  if (capeJPerKg == null) return null;
  if (capeJPerKg < 300) return 'Minimal';
  if (capeJPerKg < 1000) return 'Marginal';
  if (capeJPerKg < 2500) return 'Moderate';
  if (capeJPerKg < 4000) return 'Strong';
  return 'Extreme';
}

/// Maps a CAPE band onto the CAP severity vocabulary
/// `AppColors.alertSeverity` already understands, following the same
/// approach as `capSeverityForRiskBand` in `features/advisory/risk_band.dart`
/// — reusing the app's one severity ramp rather than inventing a second one.
///
/// "Minimal" (negligible convective energy — essentially no thunderstorm
/// risk) has no CAP equivalent: there is no standard word for "not a
/// hazard", so it deliberately returns null so the panel renders it
/// neutrally instead of borrowing a real band's colour. A null band (no
/// CAPE reading at all) returns null for the same reason
/// `capSeverityForRiskBand` returns null for the backend's own UNKNOWN —
/// under-reporting is the one mistake this product cannot make, and an
/// absent reading must never be colour-coded as calm.
String? capSeverityForCapeBand(String? band) {
  switch (band) {
    case 'Marginal':
      return 'minor';
    case 'Moderate':
      return 'moderate';
    case 'Strong':
      return 'severe';
    case 'Extreme':
      return 'extreme';
    default:
      return null;
  }
}

/// IMD's "gale" wind threshold. Gusts matter independently of sustained
/// wind speed — a gust is what tends to do structural damage — so this is
/// checked against `windGustKmh`, never `windSpeedKmh`.
const galeGustThresholdKmh = 62.0;

/// True when a gust is at or above [galeGustThresholdKmh]. Null for a
/// missing reading: "not modelled" must never quietly read as "calm",
/// which a bare `false` would imply.
bool? isGaleForceGust(double? gustKmh) {
  if (gustKmh == null) return null;
  return gustKmh >= galeGustThresholdKmh;
}
