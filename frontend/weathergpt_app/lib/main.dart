import 'package:flutter/material.dart';

void main() {
  runApp(const WeatherGptApp());
}

class WeatherGptApp extends StatelessWidget {
  const WeatherGptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('WeatherGPT')),
      ),
    );
  }
}
