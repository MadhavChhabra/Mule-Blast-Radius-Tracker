import 'package:flutter/foundation.dart';

import 'util/file_upload.dart' as web_util;

/// The two or three APIs a developer actually owns. Kept in the browser rather than the estate,
/// because it is a personal working set, not a property of the org's graph.
class Pins extends ChangeNotifier {
  static final Pins instance = Pins._();

  Pins._() {
    final raw = web_util.loadStoredSetting('pinnedApis');
    if (raw != null && raw.isNotEmpty) {
      _pinned.addAll(raw.split(',').where((s) => s.trim().isNotEmpty));
    }
  }

  final List<String> _pinned = [];

  List<String> get pinned => List.unmodifiable(_pinned);

  bool isPinned(String api) => _pinned.contains(api);

  void toggle(String api) {
    if (!_pinned.remove(api)) {
      _pinned.insert(0, api);
    }
    web_util.storeSetting('pinnedApis', _pinned.join(','));
    notifyListeners();
  }
}

/// What appeared or vanished in the estate since this browser last looked. Kept client-side: it is
/// "since *you* last looked", which is a different question from "since the last sync ran".
class EstateDelta {
  final List<String> added;
  final List<String> removed;
  const EstateDelta(this.added, this.removed);

  bool get isEmpty => added.isEmpty && removed.isEmpty;

  static const _key = 'seenApis';

  /// Compares the current node set against the remembered one without updating it, so the delta
  /// survives a page refresh until the user explicitly acknowledges it.
  static EstateDelta since(Iterable<String> currentApis) {
    final seen = web_util.loadStoredSetting(_key);
    if (seen == null) {
      return const EstateDelta([], []);
    }
    final before = seen.split(',').where((s) => s.isNotEmpty).toSet();
    final now = currentApis.toSet();
    if (before.isEmpty) {
      return const EstateDelta([], []);
    }
    return EstateDelta(
      now.difference(before).toList()..sort(),
      before.difference(now).toList()..sort(),
    );
  }

  static void remember(Iterable<String> currentApis) {
    web_util.storeSetting(_key, currentApis.join(','));
  }
}

/// Which estate node is focused, shared so the shell's top bar can *become* the focus bar rather
/// than having the canvas draw a second bar underneath it.
class FocusState extends ChangeNotifier {
  static final FocusState instance = FocusState._();
  FocusState._();

  String? _api;
  int _hops = 0;
  int _nodes = 0;

  String? get api => _api;
  int get hops => _hops;
  int get nodes => _nodes;
  bool get active => _api != null;

  void set(String? api, {int hops = 0, int nodes = 0}) {
    if (_api == api && _hops == hops && _nodes == nodes) return;
    _api = api;
    _hops = hops;
    _nodes = nodes;
    notifyListeners();
  }

  /// Callbacks the bar invokes; owned by the canvas because it holds the direction state.
  VoidCallback? onClose;
  VoidCallback? onOpenHub;
}
