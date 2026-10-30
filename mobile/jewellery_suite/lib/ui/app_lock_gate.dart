import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/app_lock.dart';
import 'palette.dart';

/// Wraps the signed-in app with an optional PIN lock.
///
/// When the lock is off this is a pass-through. When it is on, the shop stays
/// covered after launch and after every trip to the background (dialer,
/// camera, share sheet), which is exactly when a phone left on the counter is
/// most exposed.
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
      // Lock unconditionally: the PIN may have been switched on since this
      // gate was built (see _refreshEnabled below).
      if (mounted) setState(() => _locked = true);
    } else if (state == AppLifecycleState.resumed) {
      _refreshEnabled();
    }
  }

  /// Re-reads the switch whenever the app comes back to the foreground.
  ///
  /// The gate is above the Navigator, so it outlives the Settings screen where
  /// the PIN is turned on or off. Without this, enabling the PIN would not
  /// take effect until the next cold start, and disabling it would leave the
  /// gate armed.
  Future<void> _refreshEnabled() async {
    if (!mounted) return;
    final enabled = await AppLock.isEnabled(context.read<AppState>().db);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      if (!enabled) _locked = false;
      _checking = false;
    });
  }

  Future<void> _check() async {
    if (!mounted) return;
    final enabled = await AppLock.isEnabled(context.read<AppState>().db);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = enabled;
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
      // gate sits ABOVE the app's Navigator (so it covers every pushed route),
      // which means the Navigator's Overlay is not an ancestor of the lock
      // screen. Give the lock screen its own Overlay.
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
  String? _error;

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
                  Text('Jewellery Suite is locked',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: inkOf(context))),
                  const SizedBox(height: 6),
                  Text('Enter your PIN to open the shop.',
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
                        fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w700),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
