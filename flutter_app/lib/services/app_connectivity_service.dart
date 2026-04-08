import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitora rede (Wi‑Fi / dados / ethernet). Não prova “internet até o Google” —
/// cobre o caso usual de avião / sem sinal. Firestore já persiste e sincroniza escritas offline.
class AppConnectivityService {
  AppConnectivityService._();
  static final AppConnectivityService instance = AppConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _onlineCtrl =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = true;

  bool get isOnline => _online;

  Stream<bool> get onlineStream => _onlineCtrl.stream;

  static bool _listIndicatesOnline(List<ConnectivityResult> list) {
    if (list.isEmpty) return true;
    return list.any((r) => r != ConnectivityResult.none);
  }

  Future<void> start() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _setOnline(_listIndicatesOnline(initial));
    } catch (_) {
      _setOnline(true);
    }
    await _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((list) {
      _setOnline(_listIndicatesOnline(list));
    });
  }

  void _setOnline(bool online) {
    if (online == _online) return;
    _online = online;
    if (!_onlineCtrl.isClosed) _onlineCtrl.add(online);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _onlineCtrl.close();
  }
}
