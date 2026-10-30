import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/db_setup_stub.dart' if (dart.library.js_interop) 'data/db_setup_web.dart';
import 'data/local_db.dart';
import 'state/app_state.dart';
import 'util/app_version.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never show a blank white screen: surface widget errors as readable text.
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFFFDF6EC),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('⚠ App error',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              SelectableText('${details.exception}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
  try {
    await setupDatabase();
    // Read the version out of the installed APK before anything can display
    // it, so the drawer, About screen and bug reports all agree.
    await AppVersion.load();
    final db = LocalDb();
    await db.init();
    final state = AppState(db);
    await state.load();
    // Production data must never be mixed with, or recreated from, sample
    // records. Sample data used to be re-seeded automatically whenever the
    // villages table happened to be empty (e.g. right after the last khata
    // was deleted), which pushed fake pawn loans into the shop's real
    // totals. seedDemo() is now an explicit, developer-only entry point.
    //
    // Whether the shop opens straight away is decided by AppState.load(): a
    // saved session, the offline choice, or a phone that already holds the
    // ledger opens the shop; a brand-new phone sees Login / Create account.
    runApp(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const JewelleryApp(),
      ),
    );
  } catch (e, st) {
    debugPrint('STARTUP FAIL: $e\n$st');
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'Startup error:\n$e\n\n$st',
              style: const TextStyle(fontSize: 13, color: Color(0xFFB00020)),
            ),
          ),
        ),
      ),
    ));
  }
}
