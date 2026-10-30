import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/app_lock.dart';
import 'otp_flow.dart';
import 'palette.dart';
import 'secret_dialogs.dart';

/// Wraps the signed-in app with the optional PIN / Daily MPIN lock.
///
/// When the lock is off this is a pass-through. In **always** mode it covers
/// the app after launch and after every trip to the background (dialer,
/// camera, share sheet). In **daily** mode (the Daily MPIN) it asks once per
/// calendar day and then lets the shop work all day.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _checking = true;
  bool _enabled = false;
  bool _locked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Only "every time" locks on background; the daily MPIN stays open for
      // the rest of the day.
      _lockIfAlways();
    } else if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _lockIfAlways() async {
    if (!mounted) return;
    final db = context.read<AppState>().db;
    final mode = await AppLock.mode(db);
    if (!mounted) return;
    if (mode == AppLock.always && await AppLock.isEnabled(db)) {
      setState(() => _locked = true);
    }
  }

  /// Re-reads the mode whenever the app comes back to the foreground, so
  /// turning the lock on/off in Password Settings takes effect immediately.
  Future<void> _refresh() async {
    if (!mounted) return;
    final db = context.read<AppState>().db;
    final enabled = await AppLock.isEnabled(db);
    final locked = await AppLock.shouldLock(db);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = locked;
      _checking = false;
    });
  }

  Future<void> _check() async {
    if (!mounted) return;
    final db = context.read<AppState>().db;
    final enabled = await AppLock.isEnabled(db);
    final locked = await AppLock.shouldLock(db);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = locked;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        backgroundColor: bgOf(context),
        body: const Center(child: CircularProgressIndicator(color: kGold)),
      );
    }
    if (_enabled && _locked) {
      // A TextField needs an Overlay ancestor for its selection handles. This
      // gate sits ABOVE the app's Navigator, so give the lock screen its own.
      return Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => _LockScreen(
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
        ],
      );
    }
    return widget.child;
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _pin = TextEditingController();
  final _focus = FocusNode();
  bool _checking = false;
  bool _daily = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _readMode();
  }

  Future<void> _readMode() async {
    final mode = await AppLock.mode(context.read<AppState>().db);
    if (mounted) setState(() => _daily = mode == AppLock.daily);
  }

  @override
  void dispose() {
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final db = context.read<AppState>().db;
    final ok = await AppLock.verify(db, _pin.text);
    if (!mounted) return;
    if (ok) {
      await AppLock.markUnlocked(db);
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _error = 'Wrong PIN. Try again.';
      _pin.clear();
    });
    _focus.requestFocus();
  }

  Future<void> _forgotPin() async {
    final state = context.read<AppState>();
    final db = state.db;
    final mode = await AppLock.mode(db);
    if (!mounted) return;
    final verified = await confirmWithOtp(
      context,
      state,
      purpose: 'pin_reset',
      title: 'Forgot $mode'.replaceAll('Forgot daily', 'Forgot Daily MPIN'),
      subtitle: 'Reset the screen lock with a one-time code.',
    );
    if (!verified || !mounted) return;
    final pin = await askNewPinDialog(context,
        title: _daily ? 'Set a new Daily MPIN' : 'Set a new PIN');
    if (pin == null) return;
    await AppLock.setPin(db, pin);
    await AppLock.setMode(db, mode == AppLock.off ? AppLock.always : mode);
    await AppLock.markUnlocked(db);
    if (mounted) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: kGold.withValues(alpha: .16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_outline,
                        size: 38, color: kGoldDark),
                  ),
                  const SizedBox(height: 16),
                  Text(
                      _daily
                          ? 'Enter your Daily MPIN'
                          : 'Jewellery Suite is locked',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: inkOf(context))),
                  const SizedBox(height: 6),
                  Text(
                      _daily
                          ? 'Asked once a day — the shop stays open until tomorrow.'
                          : 'Enter your PIN to open the shop.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: mutedOf(context))),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pin,
                    focusNode: _focus,
                    autofocus: true,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                        fontSize: 24,
                        letterSpacing: 10,
                        fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      errorText: _error,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _unlock,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.lock_open),
                      label: Text(_checking ? 'Checking…' : 'Unlock'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _checking ? null : _forgotPin,
                    icon: const Icon(Icons.help_outline, size: 17),
                    label: const Text('Forgot PIN?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
