import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'palette.dart';
import 'settings_screen.dart' show comingSoon;

/// Home menu → About App. Shows the app name, APK (app) size and the total
/// app-data usage on the phone (database + photos/images), plus the legal /
/// support list.
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  static const appVersion = '1.0.8';
  static const apkSizeMb = 63;

  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('About App')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.diamond_outlined,
                  size: 40, color: kGoldDark),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('Jewellery Suite',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
          ),
          const Center(
            child: Text('Version $appVersion',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFF8A6D14))),
          ),
          const SizedBox(height: 20),
          _card(context, [
            _row('App size (APK)', '≈ $apkSizeMb MB'),
            _rightFuture('App data (your records)', state.appDataBytes(),
                (v) => _fmtBytes(v)),
          ]),
          const SizedBox(height: 14),
          _card(context, [
            _tile(context, Icons.description_outlined, 'Policies'),
            _tile(context, Icons.code, 'Open Source Licences'),
            _tile(context, Icons.privacy_tip_outlined, 'Privacy & Policy'),
            _tile(context, Icons.feedback_outlined, 'Feedback & Suggestions'),
            _tile(context, Icons.gavel_outlined, 'Terms & Conditions'),
          ]),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(children: children),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: kInk)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: kGoldDark)),
        ],
      ),
    );
  }

  Widget _rightFuture(String label, Future<int> future,
      String Function(int) fmt) {
    return FutureBuilder<int>(
      future: future,
      builder: (context, snap) {
        final value = snap.data ?? 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: kInk)),
              ),
              snap.connectionState == ConnectionState.waiting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(fmt(value),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: kGoldDark)),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20, color: kGoldDark),
      title: Text(title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => comingSoon(context),
    );
  }
}