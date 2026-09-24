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
        colorSchemeSeed: const Color(0xFF8A6D1F),
        useMaterial3: true,
      ),
      home: loggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
