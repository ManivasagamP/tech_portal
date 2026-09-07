import 'package:flutter/material.dart';

/// Literal Tailwind palette used by the web technician portal.
/// The portal never renders the eco-green token layer, so these are the source of truth.
abstract final class AppColors {
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray800 = Color(0xFF1F2937);
  static const gray900 = Color(0xFF111827);

  static const blue50 = Color(0xFFEFF6FF);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const blue700 = Color(0xFF1D4ED8);
  static const blue900 = Color(0xFF1E3A8A);

  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);

  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red800 = Color(0xFF991B1B);
  static const red700 = Color(0xFFB91C1C);

  static const green50 = Color(0xFFF0FDF4);
  static const green100 = Color(0xFFDCFCE7);
  static const green200 = Color(0xFFBBF7D0);
  static const green500 = Color(0xFF22C55E);
  static const green600 = Color(0xFF16A34A);
  static const green700 = Color(0xFF15803D);

  static const emerald50 = Color(0xFFECFDF5);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);

  static const orange50 = Color(0xFFFFF7ED);
  static const orange100 = Color(0xFFFFEDD5);
  static const orange200 = Color(0xFFFED7AA);
  static const orange400 = Color(0xFFFB923C);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const orange800 = Color(0xFF9A3412);
  static const orange700 = Color(0xFFC2410C);
  static const orange900 = Color(0xFF7C2D12);

  /// Dark "chrome" tones for the header/toolbar — the classic-software layer
  /// that sits on top of the light, card-based body.
  static const ink = Color(0xFF15171C);
  static const inkElevated = Color(0xFF1D2027);
  static const inkBorder = Color(0x1AFFFFFF);

  static const yellow100 = Color(0xFFFEF9C3);
  static const yellow200 = Color(0xFFFEF08A);
  static const yellow600 = Color(0xFFCA8A04);
  static const yellow700 = Color(0xFFA16207);

  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber800 = Color(0xFF92400E);
  static const amber900 = Color(0xFF78350F);

  static const rose50 = Color(0xFFFFF1F2);
  static const rose200 = Color(0xFFFECDD3);
  static const rose600 = Color(0xFFE11D48);
  static const rose800 = Color(0xFF9F1239);
  static const rose900 = Color(0xFF881337);

  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate950 = Color(0xFF020617);

  static const purple100 = Color(0xFFF3E8FF);
  static const purple500 = Color(0xFFA855F7);
  static const purple600 = Color(0xFF9333EA);
  static const purple700 = Color(0xFF7E22CE);
  static const pink500 = Color(0xFFEC4899);
}
