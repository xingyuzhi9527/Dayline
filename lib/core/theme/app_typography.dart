import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const String bodyFontFamily = 'Manrope';
  static const String displayFontFamily = 'Newsreader';

  static const double display = 32;
  static const double headline = 24;
  static const double title = 18;
  static const double body = 16;
  static const double label = 14;
  static const double caption = 12;

  static TextTheme textTheme(Brightness brightness) {
    final textColor = brightness == Brightness.dark
        ? AppColors.darkInk
        : AppColors.ink;
    final mutedColor = brightness == Brightness.dark
        ? AppColors.darkInk
        : AppColors.muted;

    return TextTheme(
      displaySmall: TextStyle(
        color: textColor,
        fontFamily: displayFontFamily,
        fontSize: display,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        color: textColor,
        fontFamily: displayFontFamily,
        fontSize: headline,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontFamily: bodyFontFamily,
        fontSize: title,
        fontWeight: FontWeight.w600,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        fontFamily: bodyFontFamily,
        fontSize: body,
        fontWeight: FontWeight.w400,
        height: 1.6,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        color: textColor,
        fontFamily: bodyFontFamily,
        fontSize: label,
        fontWeight: FontWeight.w700,
        height: 1.4,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        color: mutedColor,
        fontFamily: bodyFontFamily,
        fontSize: caption,
        fontWeight: FontWeight.w400,
        height: 1.4,
        letterSpacing: 0,
      ),
    );
  }
}
