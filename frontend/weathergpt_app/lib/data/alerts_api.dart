import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

class AlertSummary {
  final int id;
  final String severity;
  final String eventType;
  final String? areaDescription;
  final double? latitude;
  final double? longitude;

  /// The feed's own effective-start string, e.g. "Thu Sep 10 22:15:00 IST
  /// 2026" (SACHET's Java-style format, not ISO-8601) — kept as upstream
  /// text and shown verbatim rather than reparsed, since it is already
  /// human-readable and reparsing an unfamiliar format risks silently
  /// misreading a timezone.
  final String? effectiveStartTime;

  /// When WeatherGPT's own ingestion fetched this alert, ISO-8601 UTC —
  /// unlike [effectiveStartTime], reliably parseable, so this is what
  /// "alerts from the past week" filters and sorts by.
  final String? fetchedAt;

  const AlertSummary({
    required this.id,
    required this.severity,
    required this.eventType,
    required this.areaDescription,
    required this.latitude,
    required this.longitude,
    this.effectiveStartTime,
    this.fetchedAt,
  });

  factory AlertSummary.fromJson(Map<String, dynamic> json) {
    return AlertSummary(
      id: json['id'] as int,
      severity: json['severity'] as String,
      eventType: json['event_type'] as String,
      areaDescription: json['area_description'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      effectiveStartTime: json['effective_start_time'] as String?,
      fetchedAt: json['fetched_at'] as String?,
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
