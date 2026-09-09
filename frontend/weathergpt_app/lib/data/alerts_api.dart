import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

class AlertSummary {
  final int id;
  final String severity;
  final String eventType;
  final String? areaDescription;
  final double? latitude;
  final double? longitude;

  const AlertSummary({
    required this.id,
    required this.severity,
    required this.eventType,
    required this.areaDescription,
    required this.latitude,
    required this.longitude,
  });

  factory AlertSummary.fromJson(Map<String, dynamic> json) {
    return AlertSummary(
      id: json['id'] as int,
      severity: json['severity'] as String,
      eventType: json['event_type'] as String,
      areaDescription: json['area_description'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// Wraps `GET /alerts`. Note: this endpoint returns EVERY alert
/// nationwide — it does not accept lat/lon filtering (a known,
/// pre-existing backend gap, not fixed by this branch). Distance
/// filtering happens client-side — see HomeController.
class AlertsApi {
  final Dio _dio;

  AlertsApi(this._dio);

  Future<List<AlertSummary>> fetchAlerts() {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>('/alerts');
      return response.data!
          .map((entry) => AlertSummary.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }
}
