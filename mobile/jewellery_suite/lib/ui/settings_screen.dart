import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'about_app_screen.dart';
import 'palette.dart';
import 'photo_local.dart';
import 'widgets.dart';

/// "Coming in a later release" — unconfigured settings never crash the app.
void comingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      content: Text('Coming in a later release'),
      duration: Duration(seconds: 1),
    ));
}

/// More → Settings. First card is the Zoom / smart-fit adjustment, then
/// appearance, QR codes and the rest of the system settings.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'Display',
            children: [
              _ZoomCard(),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dark mode (Beta)'),
                subtitle: const Text('Beta — try it, some screens may not be fully dark yet'),
                value: state.darkMode,
                onChanged: (v) => state.setDarkMode(v),
              ),
            ],
          ),
          SectionCard(
            title: 'Payments',
            children: [
              _tile(context,
                  icon: Icons.qr_code_2,
                  title: 'QR codes',
                  subtitle: 'Bank / UPI QR codes for the shop',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const QrCodesScreen()))),
            ],
          ),
          SectionCard(
            title: 'App',
            children: [
              _tile(context, icon: Icons.language, title: 'Languages',
                  onTap: () => comingSoon(context)),
              _tile(context, icon: Icons.notifications_outlined,
                  title: 'Notifications', onTap: () => comingSoon(context)),
              _tile(context, icon: Icons.alarm, title: 'Reminders',
                  onTap: () => comingSoon(context)),
              _tile(context, icon: Icons.fingerprint, title: 'Biometric & screen lock',
                  onTap: () => comingSoon(context)),
              _tile(context, icon: Icons.lock_outline, title: 'Change password',
                  onTap: () => comingSoon(context)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.admin_panel_settings_outlined,
                    color: kGoldDark),
                title: const Text('Ask password for delete / release',
                    style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('Admin — stop accidental deletes'),
                value: state.adminConfirm,
                onChanged: (v) => state.setAdminConfirm(v),
              ),
              _tile(context,
                  icon: Icons.info_outline,
                  title: 'About App',
                  subtitle: 'Version, app size & app data',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutAppScreen()))),
              _tile(context, icon: Icons.support_agent, title: 'Help & support',
                  onTap: () => comingSoon(context)),
            ],
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: kGoldDark),
      title: Text(title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor.withValues(alpha: .8))),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

/// Zoom in / out / smart fit. Drives [AppState.fontScale] which is applied
/// app-wide through the MaterialApp text scaler cap.
class _ZoomCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scale = state.fontScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.zoom_in, size: 18, color: kGoldDark),
            const SizedBox(width: 8),
            const Text('Zoom',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${(scale * 100).round()}%',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: kGoldDark)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Adjust text size for your screen. Works with the phone\'s own '
          'display & font settings without overflowing the screen (smart fit).',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF8A6D14)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: scale > 0.8
                  ? () => state.setFontScale(scale - 0.05)
                  : null,
            ),
            Expanded(
              child: Slider(
                value: scale,
                min: 0.8,
                max: 1.5,
                divisions: 14,
                label: '${(scale * 100).round()}%',
                onChanged: (v) => state.setFontScale(v),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: scale < 1.5
                  ? () => state.setFontScale(scale + 0.05)
                  : null,
            ),
          ],
        ),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.smartphone, size: 16),
              label: const Text('Smart fit (100%)'),
              onPressed: () => state.setFontScale(1.0),
            ),
          ],
        ),
        // Live preview.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Preview — customer name ₹10,000 · Loan',
            style: TextStyle(fontSize: 13 * scale),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Bank / UPI QR codes — swipe left/right between them (like PhonePe).
class QrCodesScreen extends StatefulWidget {
  const QrCodesScreen({super.key});

  @override
  State<QrCodesScreen> createState() => _QrCodesScreenState();
}

class _QrCodesScreenState extends State<QrCodesScreen> {
  List<Map<String, Object?>> _codes = [];
  int _index = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final codes = await context.read<AppState>().qrCodes();
    if (mounted) setState(() => _codes = codes);
  }

  Future<void> _add() async {
    final path = await pickAndStoreImage(ImageSource.gallery);
    if (path == null) return;
    final nameCtl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR code name'),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          decoration: fieldDecoration('e.g. PhonePe / Bank of India'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, nameCtl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    final name = (label == null || label.isEmpty) ? 'QR ${_codes.length + 1}' : label;
    await context.read<AppState>().addQrCode(name, path);
    await _load();
  }

  Future<void> _delete(int id) async {
    final ok = await confirmDialog(context, 'Remove this QR code?',
        title: 'Remove QR');
    if (!ok) return;
    await context.read<AppState>().deleteQrCode(id);
    final codes = await context.read<AppState>().qrCodes();
    if (!mounted) return;
    setState(() {
      _codes = codes;
      if (_codes.isNotEmpty && _index >= _codes.length) {
        _index = _codes.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(title: const Text('QR codes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add QR'),
      ),
      body: _codes.isEmpty
          ? const Center(
              child: Text('No QR codes yet.\nTap "Add QR" to add your bank / UPI QR code.'),
          )
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _codes.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final code = _codes[i];
                      final id = code['id'] as int;
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(code['label']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surfaceOf(context),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withValues(alpha: .12),
                                      blurRadius: 16, offset: const Offset(0, 6)),
                                ],
                              ),
                              child: photoThumb(
                                code['path']?.toString(),
                                width: 260, height: 260, fit: BoxFit.contain,
                                fallback: const Icon(Icons.qr_code_2,
                                    size: 200, color: Colors.black26),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Remove this QR'),
                              onPressed: () => _delete(id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _codes.length; i++)
                      Container(
                        width: i == _index ? 18 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _index ? kGoldDark : kInk.withValues(alpha: .25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}