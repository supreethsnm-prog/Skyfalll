import '../core/network/app_error.dart';

/// User-facing copy for an [AppError].
///
/// Lives here rather than on `AppError` itself because
/// `lib/core/network/app_error.dart` is a preserved integration file this
/// redesign must not modify — and because presentation copy does not
/// belong on a transport-layer type anyway.
///
/// Rules these strings follow: say what happened and what to do about it,
/// in the interface's voice. No apologies, no exception class names, no
/// status codes shown to a person who cannot act on them.
String errorMessageFor(AppError error) {
  return switch (error) {
    NetworkTimeoutError() =>
      'The weather service took too long to respond. It may be busy.',
    NetworkConnectionError() =>
      "Can't reach the weather service. Check your connection.",
    // 5xx is the service's problem and waiting helps; 4xx is ours and it
    // will not fix itself, so the two must not give the same advice.
    ServerError(:final statusCode) when statusCode >= 500 =>
      'The weather service is having trouble. Try again shortly.',
    ServerError() => 'The app made a request the weather service refused.',
    UnknownError() => 'Something went wrong loading the weather.',
  };
}
