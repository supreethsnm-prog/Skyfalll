import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// One climate/weather-disaster headline for the Discover tab.
class NewsItem {
  final String title;
  final String? source;
  final String link;
  final String? publishedAt;

  const NewsItem({
    required this.title,
    required this.source,
    required this.link,
    required this.publishedAt,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      title: json['title'] as String,
      source: json['source'] as String?,
      link: json['link'] as String,
      publishedAt: json['published_at'] as String?,
    );
  }
}

/// Wraps `GET /news/climate`.
class NewsApi {
  final Dio _dio;

  NewsApi(this._dio);

  Future<List<NewsItem>> fetchClimateNews() {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>('/news/climate');
      return response.data!
          .map((entry) => NewsItem.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }
}
