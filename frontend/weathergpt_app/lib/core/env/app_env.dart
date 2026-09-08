/// Backend base URL, supplied at build/run time via
/// `--dart-define=API_BASE_URL=<url>`.
///
/// Defaults to `http://10.0.2.2:8000` — the special address the Android
/// emulator maps to the host machine's `127.0.0.1`, where the FastAPI
/// backend runs during development. Override it explicitly for:
///   - a real device on the same LAN:
///       `--dart-define=API_BASE_URL=http://<lan-ip>:8000`
///   - Chrome/web or Windows desktop:
///       `--dart-define=API_BASE_URL=http://127.0.0.1:8000`
class AppEnv {
  AppEnv._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
