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
