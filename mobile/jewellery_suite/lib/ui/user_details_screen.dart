import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'palette.dart';
import 'photo_local.dart';
import 'widgets.dart';

/// Home menu → User Details. The shopkeeper's own profile: photo shown on the
/// home button, plus phone / email / name for the app.
class UserDetailsScreen extends StatefulWidget {
  const UserDetailsScreen({super.key});

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  String? _photo;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _name = TextEditingController(text: s.userName);
    _phone = TextEditingController(text: s.userPhone);
    _email = TextEditingController(text: s.userEmail);
    _photo = s.userPhoto.isEmpty ? null : s.userPhoto;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final path = await pickAndStoreImage(ImageSource.gallery);
    if (path == null) return;
    await context.read<AppState>().setUserField('user_photo', path);
    if (mounted) setState(() => _photo = path);
  }

  Future<void> _removePhoto() async {
    await context.read<AppState>().setUserField('user_photo', '');
    if (mounted) setState(() => _photo = null);
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    await state.setUserField('user_name', _name.text.trim());
    await state.setUserField('user_phone', _phone.text.trim());
    await state.setUserField('user_email', _email.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('User details saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('User Details'),
        actions: [
          TextButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: InkWell(
              onTap: _pickPhoto,
              borderRadius: BorderRadius.circular(80),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: kGold.withValues(alpha: .16),
                    backgroundImage:
                        _photo != null ? photoProvider(_photo!) : null,
                    child: _photo == null
                        ? const Icon(Icons.person_outline,
                            size: 52, color: kGoldDark)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: kGoldDark,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_outlined,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Remove photo'),
              onPressed: _removePhoto,
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(title: 'Details', children: [
            TextField(
              controller: _name,
              decoration: fieldDecoration('Your name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: fieldDecoration('Phone number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: fieldDecoration('Email'),
            ),
            const SizedBox(height: 4),
            const Text(
              'The photo here shows on the Home button. Phone / email / name '
              'are used across the app (your customer records are separate).',
              style: TextStyle(fontSize: 11, color: Color(0xFF8A6D14)),
            ),
          ]),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}