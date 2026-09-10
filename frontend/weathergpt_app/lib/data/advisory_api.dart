import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import 'alerts_api.dart';
import 'weather_api.dart';

/// Wraps `GET /advisory/agriculture`.
///
/// `advisories` is a list of plain STRINGS, not objects — each one a
/// complete sentence of advice with its IMD threshold quoted inline, ready
/// to render as-is. `crop` is nullable both in the request (unfiltered)
/// and in this response (the backend simply echoes back whatever it was
/// asked with, including null).
class AgricultureAdvisory {
  final double latitude;
  final double longitude;
  final String? crop;
  final String generatedAt;
  final List<String> advisories;
  final List<AlertSummary> activeAlerts;
  final List<ForecastDay> forecastBasis;

  const AgricultureAdvisory({
    required this.latitude,
    required this.longitude,
    required this.crop,
    required this.generatedAt,
    required this.advisories,
    required this.activeAlerts,
    required this.forecastBasis,
  });

  factory AgricultureAdvisory.fromJson(Map<String, dynamic> json) {
    return AgricultureAdvisory(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      crop: json['crop'] as String?,
      generatedAt: json['generated_at'] as String,
      advisories: (json['advisories'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      // Same shape AlertsApi already parses — reuse AlertSummary.fromJson
      // rather than writing a second parser for it.
      activeAlerts: (json['active_alerts'] as List<dynamic>)
          .map((e) => AlertSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      // forecast_basis is exactly the shape `/forecast` already returns
      // (backend/app/forecast/service.py serves both) — reuse
      // ForecastDay.fromJson rather than writing a second parser for it.
      forecastBasis: (json['forecast_basis'] as List<dynamic>)
          .map((e) => ForecastDay.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// The three urban hazard bands from `GET /advisory/urban`.
///
/// Each is documented as exactly `LOW` | `MODERATE` | `HIGH` | `SEVERE`,
/// but the backend can also emit `UNKNOWN` when it had no forecast to
/// compute a band from — so these are plain strings here, not an enum,
/// and any value outside the four documented bands must be treated as
/// unknown by the UI (see `capSeverityForRiskBand`) rather than rejected
/// at the parsing layer. Rejecting an unrecognised band would turn a
/// forward-compatible backend change into a crashed screen; rendering it
/// neutrally is the safer failure mode for a disaster-advisory app.
class UrbanRiskSummary {
  final String waterloggingRisk;
  final String heatRisk;
  final String windRisk;

  const UrbanRiskSummary({
    required this.waterloggingRisk,
    required this.heatRisk,
    required this.windRisk,
  });

  factory UrbanRiskSummary.fromJson(Map<String, dynamic> json) {
    return UrbanRiskSummary(
      waterloggingRisk: json['waterlogging_risk'] as String,
      heatRisk: json['heat_risk'] as String,
      windRisk: json['wind_risk'] as String,
    );
  }
}

/// Wraps `GET /advisory/urban`. See [AgricultureAdvisory] for the shared
/// shape notes (`advisories` as strings, alert/forecast reuse).
class UrbanAdvisory {
  final double latitude;
  final double longitude;
  final String generatedAt;
  final UrbanRiskSummary riskSummary;
  final List<String> advisories;
  final List<AlertSummary> activeAlerts;
  final List<ForecastDay> forecastBasis;

  const UrbanAdvisory({
    required this.latitude,
    required this.longitude,
    required this.generatedAt,
    required this.riskSummary,
    required this.advisories,
    required this.activeAlerts,
    required this.forecastBasis,
  });

  factory UrbanAdvisory.fromJson(Map<String, dynamic> json) {
    return UrbanAdvisory(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      generatedAt: json['generated_at'] as String,
      riskSummary:
          UrbanRiskSummary.fromJson(json['risk_summary'] as Map<String, dynamic>),
      advisories: (json['advisories'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      activeAlerts: (json['active_alerts'] as List<dynamic>)
          .map((e) => AlertSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      forecastBasis: (json['forecast_basis'] as List<dynamic>)
          .map((e) => ForecastDay.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Wraps `GET /advisory/agriculture` and `GET /advisory/urban`.
class AdvisoryApi {
  final Dio _dio;

  AdvisoryApi(this._dio);

  Future<AgricultureAdvisory> fetchAgriculture(
    double lat,
    double lon, {
    String? crop,
    int days = 5,
  }) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/advisory/agriculture',
        queryParameters: {
          'lat': lat,
          'lon': lon,
          'days': days,
          // Omitted entirely for "All" rather than sent as a literal
          // null — the backend treats an absent crop and a null crop the
          // same way, but leaving it out of the query string is cleaner
          // than dio serializing a "crop=null" pair.
          'crop': ?crop,
        },
      );
      return AgricultureAdvisory.fromJson(response.data!);
    });
  }

  Future<UrbanAdvisory> fetchUrban(double lat, double lon, {int days = 5}) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/advisory/urban',
        queryParameters: {'lat': lat, 'lon': lon, 'days': days},
      );
      return UrbanAdvisory.fromJson(response.data!);
    });
  }
}
