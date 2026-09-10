import '../../core/geo.dart';

/// A METAR-reporting airport.
class Airport {
  final String icao;
  final String city;
  final double latitude;
  final double longitude;

  const Airport(this.icao, this.city, this.latitude, this.longitude);
}

/// Indian airports that publish METAR.
///
/// This list is bundled rather than fetched because the backend's
/// `/metar` takes an ICAO code and has no "nearest station" lookup —
/// something has to know which codes exist. ICAO identifiers and airport
/// coordinates are effectively static reference data, so a bundled list
/// is honest here in a way that bundling *weather* never would be.
///
/// Every code below was verified to return a live observation. Coordinates
/// are the airports' own, used only to pick the nearest one to the user;
/// the observation itself always comes from the backend.
const indianAirports = <Airport>[
  Airport('VIDP', 'Delhi', 28.5665, 77.1031),
  Airport('VABB', 'Mumbai', 19.0887, 72.8679),
  Airport('VOMM', 'Chennai', 12.9941, 80.1709),
  Airport('VOBL', 'Bengaluru', 13.1979, 77.7063),
  Airport('VECC', 'Kolkata', 22.6547, 88.4467),
  Airport('VOHS', 'Hyderabad', 17.2403, 78.4294),
  Airport('VAAH', 'Ahmedabad', 23.0772, 72.6347),
  Airport('VOCI', 'Kochi', 10.1520, 76.4019),
  Airport('VEBS', 'Bhubaneswar', 20.2444, 85.8178),
  Airport('VOTV', 'Thiruvananthapuram', 8.4821, 76.9201),
  Airport('VIJP', 'Jaipur', 26.8242, 75.8122),
  Airport('VILK', 'Lucknow', 26.7606, 80.8893),
  Airport('VEPT', 'Patna', 25.5913, 85.0880),
  Airport('VOGO', 'Goa', 15.3808, 73.8314),
];

/// The airport closest to a coordinate, by great-circle distance.
///
/// Uses the same `haversineKm` the alert radius filter uses, so "nearest"
/// means the same thing everywhere in the app.
Airport nearestAirport(double latitude, double longitude) {
  var closest = indianAirports.first;
  var closestDistance = double.infinity;

  for (final airport in indianAirports) {
    final distance = haversineKm(
      latitude,
      longitude,
      airport.latitude,
      airport.longitude,
    );
    if (distance < closestDistance) {
      closestDistance = distance;
      closest = airport;
    }
  }

  return closest;
}

/// Distance from a coordinate to an airport, so the UI can say how far
/// away the observation actually is — a METAR from 300km away is still
/// useful, but the user should know it is not local.
double distanceToAirportKm(double latitude, double longitude, Airport airport) =>
    haversineKm(latitude, longitude, airport.latitude, airport.longitude);
