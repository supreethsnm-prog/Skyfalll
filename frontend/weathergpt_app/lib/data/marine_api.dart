import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../core/network/api_client.dart';

/// One INCOIS Potential Fishing Zone (PFZ) advisory.
///
/// PFZ advisories are line geometry — satellite ocean-colour/SST fronts
/// where fish are predicted to concentrate — not areas, so there is no
/// polygon to fill in, only lines to draw. Every live row is a
/// `MultiLineString`; `sector_name` is empty on every row and must never be
/// displayed or relied on — `externalId` and `sectorBoundary` identify a
/// zone instead.
class PfzZone {
  final int id;
  final String externalId;
  final String category;
  final int sectorBoundary;

  /// Day-of-year as a STRING (e.g. `"252"`), paired with [year]. Never
  /// shown to a user directly — see [issueDate].
  final String julianDay;
  final int year;
  final double lengthKm;

  /// Parsed from the GeoJSON `MultiLineString` at this boundary, so no
  /// widget downstream ever touches raw coordinate pairs. GeoJSON orders
  /// coordinates longitude-first (`[lon, lat]`); `LatLng` takes
  /// (latitude, longitude) — this constructor is the one place that
  /// reordering happens, and getting it backwards would land every zone in
  /// the wrong hemisphere.
  final List<List<LatLng>> lines;

  const PfzZone({
    required this.id,
    required this.externalId,
    required this.category,
    required this.sectorBoundary,
    required this.julianDay,
    required this.year,
    required this.lengthKm,
    required this.lines,
  });

  factory PfzZone.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final lines = coordinates.map((rawLine) {
      return (rawLine as List<dynamic>).map((rawPoint) {
        final pair = rawPoint as List<dynamic>;
        // GeoJSON: [longitude, latitude]. LatLng: (latitude, longitude).
        final lon = (pair[0] as num).toDouble();
        final lat = (pair[1] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();
    }).toList();

    return PfzZone(
      id: json['id'] as int,
      externalId: json['external_id'] as String,
      category: json['category'] as String,
      sectorBoundary: json['sector_boundary'] as int,
      julianDay: json['julian_day'] as String,
      year: json['year'] as int,
      lengthKm: (json['length_km'] as num).toDouble(),
      lines: lines,
    );
  }

  /// The calendar date this advisory was issued for. `julianDay` is a
  /// day-of-year string paired with `year` (e.g. `"252"` + `2026` ->
  /// 9 September 2026) — showing the raw Julian day to a user would be
  /// indefensible.
  DateTime get issueDate =>
      DateTime(year, 1, 1).add(Duration(days: int.parse(julianDay) - 1));

  /// Every coordinate across every line segment, flattened — used to fit
  /// the map camera to the real extent of the loaded zones rather than a
  /// hardcoded camera position.
  List<LatLng> get allPoints => lines.expand((line) => line).toList();
}

/// Wraps `GET /marine/pfz-zones`.
class MarineApi {
  final Dio _dio;

  MarineApi(this._dio);

  /// The array can legitimately be empty when ingestion has not run yet —
  /// that is a real, displayable state, not an error and not "there are no
  /// fishing zones".
  Future<List<PfzZone>> fetchPfzZones() {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>('/marine/pfz-zones');
      return response.data!
          .map((entry) => PfzZone.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }
}
