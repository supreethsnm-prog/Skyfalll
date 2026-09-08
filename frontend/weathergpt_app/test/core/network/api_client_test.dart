import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/api_client.dart';
import 'package:weathergpt_app/core/network/app_error.dart';

void main() {
  final requestOptions = RequestOptions(path: '/weather');

  test('maps a connection timeout to NetworkTimeoutError', () {
    final err = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.connectionTimeout,
    );
    expect(mapDioException(err), isA<NetworkTimeoutError>());
  });

  test('maps a 500 response to ServerError with the status code', () {
    final err = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: requestOptions, statusCode: 500),
    );
    final mapped = mapDioException(err);
    expect(mapped, isA<ServerError>());
    expect((mapped as ServerError).statusCode, 500);
  });

  test('maps a connection error to NetworkConnectionError', () {
    final err = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.connectionError,
    );
    expect(mapDioException(err), isA<NetworkConnectionError>());
  });
}
