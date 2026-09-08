/// Corner-radius scale with real hierarchy — small interactive controls
/// get a tighter radius than large surfaces, deliberately avoiding one
/// radius value applied to everything regardless of size.
class AppRadius {
  AppRadius._();

  static const double control = 4;
  static const double surface = 12;
  static const double sheet = 20;
}
