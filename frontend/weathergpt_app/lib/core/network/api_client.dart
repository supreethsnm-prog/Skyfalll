import 'package:dio/dio.dart';
import '../env/app_env.dart';
import 'app_error.dart';

/// Builds the single [Dio] client the app's data layer uses to reach the
/// FastAPI backend. Centralizes base URL, timeouts, and error mapping so
/// no call site needs to know about [DioException] directly.
Dio buildApiClient({String? baseUrl}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? AppEnv.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  dio.interceptors.add(_ErrorMappingInterceptor());
  return dio;
}

class _ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err.copyWith(error: mapDioException(err)));
  }
}

/// Exposed separately from the interceptor so it is directly unit-testable
/// without constructing a full request/response cycle.
AppError mapDioException(DioException err) {
  switch (err.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const NetworkTimeoutError();
    case DioExceptionType.connectionError:
      return const NetworkConnectionError();
    case DioExceptionType.badResponse:
      return ServerError(err.response?.statusCode ?? 0);
    default:
      return UnknownError(err.message ?? 'Unknown network error');
  }
}
