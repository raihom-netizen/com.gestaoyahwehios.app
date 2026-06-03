import 'package:flutter/foundation.dart';

/// Separação UI ↔ dados (padrão Provider/ChangeNotifier) — falhas de rede não travam ecrãs.
///
/// Mantém [lastGood] para exibir cache enquanto revalida em background.
class ResilientDataNotifier<T> extends ChangeNotifier {
  T? _data;
  T? _lastGood;
  Object? _error;
  bool _loading = false;

  T? get data => _data;
  T? get lastGood => _lastGood;
  Object? get error => _error;
  bool get loading => _loading;
  bool get hasStaleFallback => _error != null && _lastGood != null;

  /// Carrega [fetch]; em erro mantém [lastGood] se [keepStaleOnError].
  Future<void> load(
    Future<T> Function() fetch, {
    bool keepStaleOnError = true,
    bool silent = false,
  }) async {
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final fresh = await fetch();
      _data = fresh;
      _lastGood = fresh;
      _error = null;
    } catch (e) {
      _error = e;
      if (keepStaleOnError && _lastGood != null) {
        _data = _lastGood;
      }
    } finally {
      if (!silent) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void applyLocal(T value) {
    _data = value;
    _lastGood = value;
    _error = null;
    notifyListeners();
  }

  void clear() {
    _data = null;
    _lastGood = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
