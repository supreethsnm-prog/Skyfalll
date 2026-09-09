/// Radii and fixed element sizes for the reference-matched chrome.
///
/// Most values here were measured pixel-by-pixel from the reference
/// screenshots and appear in the spec's §3 table; each is marked
/// `Measured`. Two — [panel] and [codeBlock] — could not be measured
/// (no reference frame shows a clean, unoccluded edge) and are design
/// choices consistent with the measured set; each is marked `Chosen`.
/// Keep that distinction accurate: a measured value may not be changed
/// without re-sampling, a chosen one may be revised on judgement.
class AppRadius {
  AppRadius._();

  /// Dropdown and attach menus. Measured.
  static const double menu = 16;

  /// User message bubbles. Measured.
  static const double bubble = 18;

  /// Glass panels on Home. Chosen — not measured.
  static const double panel = 24;

  /// Code blocks. Chosen — not measured.
  static const double codeBlock = 12;

  // --- Measured element sizes (not radii, but fixed by the reference) ---

  /// Every round chrome affordance: hamburger, new-chat, search,
  /// overflow, avatar — and the attach menu's icon wells. Uniform by
  /// design, and uniform in the reference. Measured.
  static const double iconButton = 40;

  /// Composer pill height; it is fully rounded, so its radius is half.
  /// Measured.
  static const double composerHeight = 40;

  /// Dropdown menu width. Measured.
  static const double menuWidth = 191;

  /// User bubbles never exceed this fraction of the screen width.
  /// Measured.
  static const double bubbleMaxWidthFactor = 0.72;
}
