import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

class JewelleryApp extends StatelessWidget {
  const JewelleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AppState>().loggedIn;
    return MaterialApp(
      title: 'Jewellery Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB98A1F),
        ).copyWith(
          primary: const Color(0xFFC9A227),
          surface: const Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFEFECE4),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEFECE4),
          foregroundColor: Color(0xFF2B2B2B),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF2B2B2B),
          contentTextStyle: TextStyle(color: Color(0xFFFFE9A8)),
        ),
      ),
      home: loggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
