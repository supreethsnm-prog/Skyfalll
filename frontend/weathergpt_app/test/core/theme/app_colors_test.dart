import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';

void main() {
  test('alertSeverity maps known CAP levels to their colors', () {
    expect(AppColors.alertSeverity('Extreme'), const Color(0xFF8F2836));
    expect(AppColors.alertSeverity('severe'), const Color(0xFFC23B4B));
    expect(AppColors.alertSeverity('MODERATE'), const Color(0xFFD98E2B));
    expect(AppColors.alertSeverity('minor'), const Color(0xFFF3D9AE));
  });

  test('alertSeverity falls back to Moderate for an unrecognized or missing value', () {
    expect(AppColors.alertSeverity('Unknown'), const Color(0xFFD98E2B));
    expect(AppColors.alertSeverity(null), const Color(0xFFD98E2B));
  });
}
