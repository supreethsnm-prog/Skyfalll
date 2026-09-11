import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/translate_api.dart';

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  group('TranslationResult.fromJson', () {
    test('parses translated text, source, and target', () {
      final result = TranslationResult.fromJson({
        'translated_text': 'भारी बारिश की संभावना',
        'source_language': 'en',
        'target_language': 'hi',
      });

      expect(result.translatedText, 'भारी बारिश की संभावना');
      expect(result.sourceLanguage, 'en');
      expect(result.targetLanguage, 'hi');
    });
  });

  group('TranslateApi', () {
    test('calls /translate with query parameters and parses result', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        expect(options.path, '/translate');
        expect(options.queryParameters['text'], 'Heavy rainfall expected');
        expect(options.queryParameters['source'], 'en');
        expect(options.queryParameters['target'], 'hi');
        return ResponseBody.fromString(
          '{"translated_text": "भारी बारिश की संभावना", "source_language": "en", "target_language": "hi"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final api = TranslateApi(dio);
      final result = await api.translate(
        text: 'Heavy rainfall expected',
        source: 'en',
        target: 'hi',
      );

      expect(result.translatedText, 'भारी बारिश की संभावना');
      expect(result.sourceLanguage, 'en');
      expect(result.targetLanguage, 'hi');
    });

    test('rethrows AppError on server error', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          '{"detail": "provider down"}',
          503,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final api = TranslateApi(dio);
      expect(
        () => api.translate(text: 'Hello', source: 'en', target: 'hi'),
        throwsA(isA<AppError>()),
      );
    });
  });
}
