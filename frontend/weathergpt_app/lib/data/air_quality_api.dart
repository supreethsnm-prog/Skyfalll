import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

double? _asDoubleOrNull(dynamic value) =>
    value == null ? null : (value as num).toDouble();

/// An air-quality observation for a point.
///
/// Every pollutant is nullable: Open-Meteo's air-quality model has sparser
/// coverage than its weather model, and a missing reading must stay null.
/// An "AQI 0" would read as pristine air rather than as no data.
class AirQuality {
  final double? usAqi;
  final double? pm25;
  final double? pm10;
  final String observedAt;

  const AirQuality({
    required this.observedAt,
    this.usAqi,
    this.pm25,
    this.pm10,
  });

  factory AirQuality.fromJson(Map<String, dynamic> json) {
    return AirQuality(
      observedAt: json['observed_at'] as String,
      usAqi: _asDoubleOrNull(json['us_aqi']),
      pm25: _asDoubleOrNull(json['pm2_5']),
      pm10: _asDoubleOrNull(json['pm10']),
    );
  }

  /// US EPA band for [usAqi]. Returns null when there is no reading, so
  /// callers omit the pill rather than labelling absent data "Good".
  String? get bandLabel {
    final aqi = usAqi;
    if (aqi == null) return null;
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for sensitive groups';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very unhealthy';
    return 'Hazardous';
  }
}

/// Wraps `GET /air-quality`.
class AirQualityApi {
  final Dio _dio;

  AirQualityApi(this._dio);

  Future<AirQuality> fetchCurrent(double lat, double lon) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/air-quality',
        queryParameters: {'lat': lat, 'lon': lon},
      );
      return AirQuality.fromJson(response.data!);
    });
  }
}
