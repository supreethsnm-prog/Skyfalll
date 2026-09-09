/// 4dp grid. `screenMargin` is measured from the references (12dp side
/// margin for the floating chrome buttons); the rest is a conventional
/// scale built on the same grid.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Horizontal margin from the screen edge to floating chrome.
  static const double screenMargin = 12;
}
