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
    case DioExceptionType.transformTimeout:
      return const NetworkTimeoutError();
    case DioExceptionType.connectionError:
      return const NetworkConnectionError();
    case DioExceptionType.badResponse:
      return ServerError(err.response?.statusCode ?? 0);
    default:
      return UnknownError(err.message ?? 'Unknown network error');
  }
}

/// Runs [call] through the shared error-mapping contract: any DioException
/// (already annotated with an AppError by the interceptor) is unwrapped and
/// rethrown as that AppError; any other exception (e.g. a JSON decode
/// failure) is wrapped as an UnknownError. Every future API call in the app
/// should go through this rather than catching DioException directly.
Future<T> guardApi<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    if (e.error is AppError) {
      throw e.error as AppError;
    }
    throw UnknownError(e.message ?? 'Unknown network error');
  } catch (e) {
    throw UnknownError(e.toString());
  }
}
