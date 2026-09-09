import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/weather_icon.dart';

void main() {
  test('maps clear sky (0) to a sunny icon', () {
    expect(weatherIconFor(0), Icons.wb_sunny_outlined);
  });

  test('maps thunderstorm codes (95-99) to a thunderstorm icon', () {
    expect(weatherIconFor(95), Icons.thunderstorm_outlined);
    expect(weatherIconFor(99), Icons.thunderstorm_outlined);
  });

  test('falls back to a help icon for an unrecognized code', () {
    expect(weatherIconFor(-1), Icons.help_outline);
  });
}
