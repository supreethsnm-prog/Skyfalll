/// Radii and fixed element sizes measured from the reference
/// screenshots — see the spec's §3 table.
class AppRadius {
  AppRadius._();

  /// Dropdown and attach menus.
  static const double menu = 16;

  /// User message bubbles.
  static const double bubble = 18;

  /// Glass panels on Home.
  static const double panel = 24;

  /// Code blocks.
  static const double codeBlock = 12;

  // --- Measured element sizes (not radii, but fixed by the reference) ---

  /// Every round chrome affordance: hamburger, new-chat, search,
  /// overflow, avatar. Uniform by design.
  static const double iconButton = 40;

  /// Composer pill height; it is fully rounded, so its radius is half.
  static const double composerHeight = 40;

  /// Dropdown menu width.
  static const double menuWidth = 191;

  /// User bubbles never exceed this fraction of the screen width.
  static const double bubbleMaxWidthFactor = 0.72;
}
