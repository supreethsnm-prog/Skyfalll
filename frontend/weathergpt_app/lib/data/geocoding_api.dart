import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/app_error.dart';

class GeocodeResult {
  final String displayName;
  final double latitude;
  final double longitude;
  final String? country;
  final String? state;

  const GeocodeResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.country,
    required this.state,
  });

  factory GeocodeResult.fromJson(Map<String, dynamic> json) {
    return GeocodeResult(
      displayName: json['display_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      country: json['country'] as String?,
      state: json['state'] as String?,
    );
  }
}

/// Wraps `GET /geocode`. A 404 (no match) is a normal, expected
/// outcome — not an error — so [search] returns null rather than
/// throwing for that specific case.
class GeocodingApi {
  final Dio _dio;

  GeocodingApi(this._dio);

  Future<GeocodeResult?> search(String query) async {
    try {
      return await guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/geocode',
          queryParameters: {'q': query},
        );
        return GeocodeResult.fromJson(response.data!);
      });
    } on ServerError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Names a coordinate, for showing the device's own location on Home.
  ///
  /// Returns null on 404 — a point with no place name (mid-ocean, say) is
  /// a legitimate answer, not a failure. Mirrors [search]'s handling.
  Future<GeocodeResult?> reverse(double lat, double lon) async {
    try {
      return await guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/reverse-geocode',
          queryParameters: {'lat': lat, 'lon': lon},
        );
        return GeocodeResult.fromJson(response.data!);
      });
    } on ServerError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
