import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/app_error.dart';

double? _asDoubleOrNull(dynamic value) =>
    value == null ? null : (value as num).toDouble();

/// A decoded METAR observation for one airport.
///
/// METAR is the aviation weather standard: a station report issued every
/// 30-60 minutes, far more frequently and more locally than a model
/// forecast. Every derived field is nullable — a station can report a
/// partial observation, and the upstream decoder passes that through
/// rather than guessing.
class MetarReading {
  final String icaoId;
  final String rawMetar;
  final String observedAt;
  final String? stationName;

  final double? temperatureC;
  final double? dewpointC;
  final double? windDirDeg;
  final double? windSpeedKt;
  final double? visibilitySm;

  /// VFR / MVFR / IFR / LIFR — the aviation ceiling-and-visibility
  /// category. Null when the station did not report enough to derive it.
  final String? flightCategory;

  const MetarReading({
    required this.icaoId,
    required this.rawMetar,
    required this.observedAt,
    this.stationName,
    this.temperatureC,
    this.dewpointC,
    this.windDirDeg,
    this.windSpeedKt,
    this.visibilitySm,
    this.flightCategory,
  });

  factory MetarReading.fromJson(Map<String, dynamic> json) {
    return MetarReading(
      icaoId: json['icao_id'] as String,
      rawMetar: json['raw_metar'] as String,
      observedAt: json['observed_at'] as String,
      stationName: json['station_name'] as String?,
      temperatureC: _asDoubleOrNull(json['temperature_c']),
      dewpointC: _asDoubleOrNull(json['dewpoint_c']),
      windDirDeg: _asDoubleOrNull(json['wind_dir_deg']),
      windSpeedKt: _asDoubleOrNull(json['wind_speed_kt']),
      visibilitySm: _asDoubleOrNull(json['visibility_sm']),
      flightCategory: json['flight_category'] as String?,
    );
  }

  /// Statute miles to kilometres, for a screen that shows metric
  /// everywhere else. Aviation reports visibility in statute miles by
  /// convention; showing "2.49 SM" next to "6.4 km" elsewhere on Home
  /// would make the app look like it had two unit systems.
  double? get visibilityKm =>
      visibilitySm == null ? null : visibilitySm! * 1.609344;
}

/// Wraps `GET /metar`.
class MetarApi {
  final Dio _dio;

  MetarApi(this._dio);

  /// Returns null when the station has no current observation — the
  /// backend 404s that case, and a station being temporarily silent is
  /// normal rather than an error. Mirrors `GeocodingApi.search`.
  Future<MetarReading?> fetch(String icao) async {
    try {
      return await guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/metar',
          queryParameters: {'icao': icao},
        );
        return MetarReading.fromJson(response.data!);
      });
    } on ServerError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
