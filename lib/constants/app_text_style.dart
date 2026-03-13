import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static const TextStyle header1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: AppColors.textWhite,
    letterSpacing: 1.5,
  );

  static const TextStyle header2 = TextStyle(
    fontFamily: 'BebasNeue',
    fontSize: 36,
    fontWeight: FontWeight.normal,
    color: AppColors.textWhite,
    letterSpacing: 1.2,
  );

  static const TextStyle header3 = TextStyle(
    fontFamily: 'BebasNeue',
    fontSize: 28,
    fontWeight: FontWeight.normal,
    color: AppColors.textWhite,
    letterSpacing: 1.0,
  );

  // Body Text (Inter)
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.normal,
    color: AppColors.textWhite,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textWhite,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textGray,
  );

  // Bold Text (Inter Bold)
  static const TextStyle bodyBold = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textWhite,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textDarkGray,
  );

  // Button Text
  static const TextStyle button = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textWhite,
    letterSpacing: 0.5,
  );
}