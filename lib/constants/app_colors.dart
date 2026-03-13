import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color black = Color.fromARGB(255, 0, 0, 0);         // Void Black
  static const Color darkGray = Color(0xFF1E1C24);      // Graphite
  static const Color ashGray = Color(0xFF8B82A7);       // Muted Lavender

  static const Color niorRed = Color(0xFF7B2FBE);       // Electric Violet — NoirScreen signature

  // Complementary Colors
  static const Color charcoal = Color(0xFF141318);      // Charcoal Noir
  static const Color silver = Color(0xFFF0EEF5);        // Soft White
  static const Color darkBlue = Color(0xFF2A2733);      // Deep Divide

  // Functional Colors
  static const Color success = Color(0xFF10B981);       // Emerald
  static const Color error = Color.fromARGB(255, 240, 32, 32);     // Crisp red
  static const Color warning = Color(0xFFF5A623);       // Neon Amber

  // Background Colors
  static const Color backgroundDark = Color.fromARGB(255, 0, 0, 0);  // Void Black
  static const Color backgroundCard = Color(0xFF141318);  // Charcoal Noir

  // Text Colors
  static const Color textWhite = Color(0xFFF0EEF5);     // Soft White
  static const Color textGray = Color(0xFF8B82A7);      // Muted Lavender
  static const Color textDarkGray = Color(0xFF2A2733);  // Deep Divide

  // Accent Colors
  static const Color accentGold = Color(0xFFF5A623);        // Neon Amber — buttons & CTAs
  static const Color accentVioletLight = Color(0xFF9B5FDE); // Violet glow — gradients & focus states
}