import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/admin_password_gate.dart';
import 'ui/app_lock_gate.dart';

class JewelleryApp extends StatelessWidget {
  const JewelleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
      //
      // The app lock lives here, ABOVE the Navigator, not inside `home`.
      // #037: pushed screens (Settings, a customer profile, the cashbook) sit
      // in the root navigator on top of `home`. A gate placed inside `home`
      // stayed underneath them, so backgrounding the app on one of those
      // screens left the shop fully visible. Wrapping the Navigator itself
      // means the lock covers whatever route is on screen.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final sys = mq.textScaler.scale(14) / 14;
        final base = (sys > 1.4 ? 1.4 : sys).clamp(0.9, 1.4);
        final effective = (state.fontScale * base).clamp(0.7, 1.9);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(effective)),
          child: AppLockGate(child: child!),
        );
      },
      // The gate first forces the shipped default admin password to be
      // replaced, then routes to Home/Login exactly as before.
      home: const AdminPasswordGate(),
    );
  }
}