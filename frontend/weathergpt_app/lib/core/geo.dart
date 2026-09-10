import 'dart:math' as math;

const double _earthRadiusKm = 6371.0;

/// Great-circle distance between two lat/lon points, in kilometers.
/// Mirrors backend/app/geo.py's `haversine_km` exactly — same formula,
/// same Earth radius constant — so client-side alert-distance
/// filtering agrees with what the backend would compute for the same
/// coordinates.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) * math.cos(phi2) * math.sin(dLambda / 2) * math.sin(dLambda / 2);
  return 2 * _earthRadiusKm * math.asin(math.sqrt(a));
}

/// A coarse bounding box for "is this location roughly India", used only to
/// decide whether Home should explain why no alerts are showing.
///
/// Our alert sources (SACHET-IMD-NOWCAST, SACHET-SDMA) are both Indian
/// government feeds. Measured across 726 live alerts, their actual coverage
/// is lat 7.01-34.55, lon 68.83-94.91 — padded out to round numbers here.
/// This is a UI hint, NOT a border: it exists only to distinguish "no
/// alerts because nothing is happening" (inside this box) from "no alerts
/// because this location isn't in our coverage at all" (outside it). Never
/// use it for anything that needs real geographic accuracy.
class IndiaAlertCoverageBox {
  IndiaAlertCoverageBox._();

  static const double minLatitude = 6.5;
  static const double maxLatitude = 37.5;
  static const double minLongitude = 68.0;
  static const double maxLongitude = 97.5;

  static bool contains(double latitude, double longitude) =>
      latitude >= minLatitude &&
      latitude <= maxLatitude &&
      longitude >= minLongitude &&
      longitude <= maxLongitude;
}
