import 'package:flutter/material.dart';

/// Temporary stand-in for a bottom-nav destination not yet built.
/// Replaced screen-by-screen in later phases (Home in Phase 1, Chat in
/// Phase 2, Forecast/More in Phase 3).
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title — coming soon',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
