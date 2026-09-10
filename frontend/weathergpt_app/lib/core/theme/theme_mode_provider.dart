import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// **Currently unwired, on purpose.** Nothing imports this file: the app
/// is dark-only for now and `main.dart` hardcodes [ThemeMode.dark]. It is
/// kept because light mode is a stated goal, but be aware that wiring
/// this alone is not enough — `AppTheme` has no light palette yet, and
/// the sky gradients and their foreground picker assume a dark chrome.
/// Treat this as a placeholder for that work, not as a switch someone
/// forgot to flip.
///
/// Holds the app's current [ThemeMode]. Starts at [ThemeMode.system] so
/// the app defers to the device setting by default; [toggle] lets the
/// component gallery (and, later, a real settings screen) flip between
/// light and dark for design review without touching device settings.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Flips between light and dark. Starting from [ThemeMode.system] this
  /// resolves to dark on the first toggle, since the current state is
  /// compared against [ThemeMode.dark] rather than tracking the
  /// system's resolved brightness.
  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
