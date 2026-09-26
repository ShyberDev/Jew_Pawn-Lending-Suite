import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

class JewelleryApp extends StatelessWidget {
  const JewelleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final loggedIn = state.loggedIn;
    final dark = state.darkMode;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB98A1F),
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: const Color(0xFFC9A227),
      surface: dark ? const Color(0xFF26231D) : const Color(0xFFFFFFFF),
    );
    return MaterialApp(
      title: 'Jewellery Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor:
            dark ? const Color(0xFF1B1915) : const Color(0xFFEFECE4),
        appBarTheme: AppBarTheme(
          backgroundColor:
              dark ? const Color(0xFF1B1915) : const Color(0xFFEFECE4),
          foregroundColor:
              dark ? const Color(0xFFF2EFE7) : const Color(0xFF2B2B2B),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor:
              dark ? const Color(0xFFF2EFE7) : const Color(0xFF2B2B2B),
          contentTextStyle: TextStyle(
              color: dark ? const Color(0xFF2B2B2B) : const Color(0xFFFFE9A8)),
        ),
      ),
      // Smart fit (zoom): cap the phone's own font/display size so huge phone
      // settings never overflow the screens, then apply the in-app Zoom
      // setting (Settings → Zoom, 0.8×–1.5×) on top. Layouts are sized for a
      // ~1.4× cap, so text stays readable without breaking out of bounds.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final sys = mq.textScaler.scale(14) / 14;
        final base = (sys > 1.4 ? 1.4 : sys).clamp(0.9, 1.4);
        final effective = (state.fontScale * base).clamp(0.7, 1.9);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(effective)),
          child: child!,
        );
      },
      home: loggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}