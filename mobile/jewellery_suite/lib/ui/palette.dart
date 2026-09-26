import 'package:flutter/material.dart';

/// Jewellers Gold theme palette, shared across every screen.
const kBg = Color(0xFFEFECE4);
const kGold = Color(0xFFC9A227);
const kGoldDark = Color(0xFF9A7B10);
const kInk = Color(0xFF2B2B2B);

const kGreen = Color(0xFF2E7D32);
const kGreenSoft = Color(0xFFE8F0E7);
const kRed = Color(0xFFC62828);
const kRedSoft = Color(0xFFFBEAEA);
const kBlue = Color(0xFF1565C0);
const kBlueSoft = Color(0xFFE8F0FA);

// ---------------------------------------------------- dark-mode aware colours
// The shop screens are built from a light palette, so Dark mode needs these
// three helpers to swap surfaces / background / ink without every widget
// hard-coding a colour.
const _darkSurface = Color(0xFF1E1E1E);
const _darkBg = Color(0xFF121212);
const _darkInk = Color(0xFFECECEC);

/// True while Dark mode (Beta) is on.
bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Card surface: white in light mode, dark grey in dark mode.
Color surfaceOf(BuildContext context) =>
    isDark(context) ? _darkSurface : Colors.white;

/// Screen background: cream in light mode, near-black in dark mode.
Color bgOf(BuildContext context) => isDark(context) ? _darkBg : kBg;

/// Main text / icon colour: near-black in light mode, off-white in dark mode.
Color inkOf(BuildContext context) => isDark(context) ? _darkInk : kInk;

/// Muted text colour that stays readable on [surfaceOf].
Color mutedOf(BuildContext context) => isDark(context)
    ? _darkInk.withValues(alpha: .62)
    : kInk.withValues(alpha: .55);

/// Divider / hairline that works on both surfaces.
Color lineOf(BuildContext context) => isDark(context)
    ? Colors.white.withValues(alpha: .12)
    : kInk.withValues(alpha: .08);