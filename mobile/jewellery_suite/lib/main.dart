import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/db_setup_stub.dart' if (dart.library.js_interop) 'data/db_setup_web.dart';
import 'data/demo_seed.dart';
import 'data/local_db.dart';
import 'state/app_state.dart';

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
    final db = LocalDb();
    await db.init();
    final state = AppState(db);
    await state.load();
    // Offline preview mode (auth/sync deferred): seed realistic sample data
    // on first launch and skip the server login, so the app is fully
    // explorable anywhere — no server involved.
    final demoV = await db.getSetting('demo_version');
    final villages = await db.db.query('villages');
    if (villages.isEmpty || demoV != '3') {
      await seedDemo(db);
      await db.setSetting('demo_version', '3');
      debugPrint('PREVIEW: demo data seeded');
    }
    state.loggedIn = true;
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
