import 'dart:async';

import 'package:flutter/foundation.dart';

/// Estado interno da sincronização em background (nunca exibir "syncing" na UI).
enum SyncServiceState {
  idle,
  syncing,
  success,
  error,
}

/// Sincronização silenciosa estilo WhatsApp/Nubank — background only.
///
/// - [syncing]: nada na tela
/// - [success]: SnackBar breve «Alterações salvas»
/// - [error]: SnackBar «Falha ao sincronizar. Tentando novamente.»
abstract final class SyncService {
  SyncService._();

  static final ValueNotifier<SyncServiceState> state =
      ValueNotifier<SyncServiceState>(SyncServiceState.idle);

  static int _syncDepth = 0;
  static Timer? _successDebounce;
  static bool _pendingSuccessFeedback = false;
  static bool _hadError = false;

  static bool get isSyncing => state.value == SyncServiceState.syncing;

  /// Início de flush/sync em background — sem feedback visual.
  static void beginSync() {
    _syncDepth++;
    if (state.value != SyncServiceState.syncing) {
      state.value = SyncServiceState.syncing;
    }
  }

  /// Fim com sucesso — feedback só se houve trabalho na fila.
  static void endSyncSuccess({bool showFeedback = false}) {
    if (_syncDepth > 0) _syncDepth--;
    if (_syncDepth > 0) return;
    if (showFeedback) {
      _pendingSuccessFeedback = true;
      _scheduleSuccessFeedback();
    } else if (!_hadError) {
      state.value = SyncServiceState.idle;
    }
  }

  /// Falha — SnackBar temporário; retry automático pela fila.
  static void endSyncError() {
    if (_syncDepth > 0) _syncDepth--;
    _hadError = true;
    _pendingSuccessFeedback = false;
    _successDebounce?.cancel();
    state.value = SyncServiceState.error;
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (state.value == SyncServiceState.error) {
        _hadError = false;
        state.value = SyncServiceState.idle;
      }
    });
  }

  /// Gravação local/online concluída — «Alterações salvas» (debounced).
  static void notifyUserActionSaved() {
    _pendingSuccessFeedback = true;
    _scheduleSuccessFeedback();
  }

  static void _scheduleSuccessFeedback() {
    _successDebounce?.cancel();
    _successDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!_pendingSuccessFeedback) return;
      _pendingSuccessFeedback = false;
      _hadError = false;
      state.value = SyncServiceState.success;
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (state.value == SyncServiceState.success) {
          state.value = SyncServiceState.idle;
        }
      });
    });
  }
}
