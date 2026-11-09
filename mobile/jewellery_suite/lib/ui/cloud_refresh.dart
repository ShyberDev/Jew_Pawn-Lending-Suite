import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Reloads one screen's own data when the cloud mirror pulls rows from another
/// phone.
///
/// Only the local queries re-run: the route, the scroll offset, the search text
/// and any open sheet are left alone. The mixin listens to
/// [AppState.cloudRevision] rather than to [AppState] itself, so an unrelated
/// `notifyListeners()` (a toggle, a font-size change, a toast) does not re-query
/// seven jewellery tables.
mixin CloudRefreshMixin<T extends StatefulWidget> on State<T> {
  ValueNotifier<int>? _revision;
  int _seen = 0;
  bool _reloading = false;

  /// Re-read this screen's rows and `setState`. Implemented by the screen.
  Future<void> reloadFromCloud();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.read<AppState>().cloudRevision;
    if (identical(revision, _revision)) return;
    _revision?.removeListener(_onCloudPull);
    _revision = revision..addListener(_onCloudPull);
    _seen = revision.value;
  }

  void _onCloudPull() {
    final revision = _revision;
    if (revision == null || revision.value == _seen || _reloading) return;
    _seen = revision.value;
    _reloading = true;
    // A failed query must not escape a notifier callback; the screen keeps the
    // rows it already shows and the next pull retries.
    reloadFromCloud().catchError((Object _) {}).whenComplete(() {
      _reloading = false;
    });
  }

  @override
  void dispose() {
    _revision?.removeListener(_onCloudPull);
    super.dispose();
  }
}
