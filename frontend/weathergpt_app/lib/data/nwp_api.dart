import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// Nullable numeric field. Every meteorological column on this endpoint is
/// `nullable=True` upstream — GFS ingestion can leave a field unmodelled
/// for a given cycle/hour — and a missing reading must stay null rather
/// than becoming 0, which would render as a real measurement. A null CAPE
/// in particular must never read as "0 J/kg", which asserts "no
/// instability" — the exact opposite of "unknown".
double? _asDoubleOrNull(dynamic value) =>
    value == null ? null : (value as num).toDouble();

/// One forecast hour of NOAA GFS numerical weather prediction data for a
/// point — the fields a meteorologist actually forecasts severe weather
/// from (CAPE, CIN, wind gust, MSLP, cloud cover), as opposed to the
/// consumer temperature/icon feed in `weather_api.dart`.
///
/// `runDate`/`runHour`/`forecastHour`/`validTime` identify the model cycle
/// and are always present; every other field is nullable — see
/// [_asDoubleOrNull].
class NwpPoint {
  final String runDate;
  final String runHour;
  final int forecastHour;

  /// UTC ISO-8601 with a `Z` suffix, as the backend sends it. Callers
  /// must parse and convert to local time for display rather than
  /// showing this raw string next to local times elsewhere in the app.
  final String validTime;

  final double? temp2mC;
  final double? relativeHumidity2mPct;
  final double? windSpeed10mKmh;
  final double? windDirection10mDeg;
  final double? windGustKmh;
  final double? precipRateMmh;
  final double? capeJPerKg;
  final double? cinJPerKg;
  final double? cloudCoverPct;
  final double? mslpHpa;

  const NwpPoint({
    required this.runDate,
    required this.runHour,
    required this.forecastHour,
    required this.validTime,
    this.temp2mC,
    this.relativeHumidity2mPct,
    this.windSpeed10mKmh,
    this.windDirection10mDeg,
    this.windGustKmh,
    this.precipRateMmh,
    this.capeJPerKg,
    this.cinJPerKg,
    this.cloudCoverPct,
    this.mslpHpa,
  });

  factory NwpPoint.fromJson(Map<String, dynamic> json) {
    return NwpPoint(
      runDate: json['run_date'] as String,
      runHour: json['run_hour'] as String,
      forecastHour: json['forecast_hour'] as int,
      validTime: json['valid_time'] as String,
      temp2mC: _asDoubleOrNull(json['temp_2m_c']),
      relativeHumidity2mPct: _asDoubleOrNull(json['relative_humidity_2m_pct']),
      windSpeed10mKmh: _asDoubleOrNull(json['wind_speed_10m_kmh']),
      windDirection10mDeg: _asDoubleOrNull(json['wind_direction_10m_deg']),
      windGustKmh: _asDoubleOrNull(json['wind_gust_kmh']),
      precipRateMmh: _asDoubleOrNull(json['precip_rate_mmh']),
      capeJPerKg: _asDoubleOrNull(json['cape_j_per_kg']),
      cinJPerKg: _asDoubleOrNull(json['cin_j_per_kg']),
      cloudCoverPct: _asDoubleOrNull(json['cloud_cover_pct']),
      mslpHpa: _asDoubleOrNull(json['mslp_hpa']),
    );
  }
}

/// Wraps `GET /nwp`.
///
/// The response can legitimately be an EMPTY array: `/nwp` reads from a
/// table filled by scheduled GFS ingestion, and if that has not run yet
/// there is nothing to return. An empty list is a normal, valid response —
/// not an error — and callers must render a clear "not available" state
/// rather than a panel that looks like calm conditions.
class NwpApi {
  final Dio _dio;

  NwpApi(this._dio);

  Future<List<NwpPoint>> fetchForecast(double lat, double lon) {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>(
        '/nwp',
        queryParameters: {'lat': lat, 'lon': lon},
      );
      return response.data!
          .map((entry) => NwpPoint.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }
}
