import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

/// The result of an exact string translation via Bhashini NMT (IndicTrans2).
class TranslationResult {
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;

  const TranslationResult({
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    return TranslationResult(
      translatedText: json['translated_text'] as String,
      sourceLanguage: json['source_language'] as String,
      targetLanguage: json['target_language'] as String,
    );
  }
}

/// Client for the FastAPI `GET /translate` endpoint.
///
/// Used for exact translations of alerts, advisories, and UI labels
/// where numbers and meteorological terminology must not drift.
class TranslateApi {
  final Dio _dio;

  TranslateApi(this._dio);

  Future<TranslationResult> translate({
    required String text,
    required String source,
    required String target,
  }) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/translate',
        queryParameters: {
          'text': text,
          'source': source,
          'target': target,
        },
      );
      return TranslationResult.fromJson(response.data!);
    });
  }
}

final translateApiProvider =
    Provider<TranslateApi>((ref) => TranslateApi(buildApiClient()));
