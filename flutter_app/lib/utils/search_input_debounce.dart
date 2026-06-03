import 'dart:async';

import 'package:flutter/foundation.dart';

/// Debounce padrão (500 ms) antes de filtrar lista ou consultar Firestore.
const Duration kSearchInputDebounceDelay = Duration(milliseconds: 500);

/// Agenda atualização de texto de busca sem reconstruir a árvore a cada tecla.
class SearchInputDebounce {
  SearchInputDebounce({
    this.delay = kSearchInputDebounceDelay,
    required this.onDebounced,
  });

  final Duration delay;
  final ValueChanged<String> onDebounced;
  Timer? _timer;

  void schedule(String raw) {
    _timer?.cancel();
    final value = raw;
    _timer = Timer(delay, () => onDebounced(value));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}

/// Helper para [State]: `scheduleSearch(() => setState(() => _q = ...))`.
mixin SearchDebounceStateMixin<T extends StatefulWidget> on State<T> {
  Timer? _searchDebounceTimer;

  void scheduleSearchUpdate(VoidCallback apply) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(kSearchInputDebounceDelay, () {
      if (mounted) apply();
    });
  }

  void cancelSearchDebounce() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
  }

  @override
  void dispose() {
    cancelSearchDebounce();
    super.dispose();
  }
}
