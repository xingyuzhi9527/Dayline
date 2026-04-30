import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const String fontFamily = 'Roboto';

  static const double display = 32;
  static const double headline = 24;
  static const double title = 18;
  static const double body = 16;
  static const double label = 14;
  static const double caption = 12;

  static TextTheme textTheme(Brightness brightness) {
    final textColor =
        brightness == Brightness.dark ? AppColors.darkInk : AppColors.ink;
    final mutedColor =
        brightness == Brightness.dark ? AppColors.darkInk : AppColors.muted;

    return TextTheme(
      displaySmall: TextStyle(
        color: textColor,
        fontFamily: fontFamily,
        fontSize: display,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        color: textColor,
        fontFamily: fontFamily,
        fontSize: headline,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontFamily: fontFamily,
        fontSize: title,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        fontFamily: fontFamily,
        fontSize: body,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        color: textColor,
        fontFamily: fontFamily,
        fontSize: label,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        color: mutedColor,
        fontFamily: fontFamily,
        fontSize: caption,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
    );
  }
}
