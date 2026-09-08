/// Typed errors the rest of the app pattern-matches on, instead of
/// handling a raw DioException at every call site.
sealed class AppError {
  const AppError();
}

class NetworkTimeoutError extends AppError {
  const NetworkTimeoutError();
}

class NetworkConnectionError extends AppError {
  const NetworkConnectionError();
}

class ServerError extends AppError {
  final int statusCode;
  const ServerError(this.statusCode);
}

class UnknownError extends AppError {
  final String message;
  const UnknownError(this.message);
}
