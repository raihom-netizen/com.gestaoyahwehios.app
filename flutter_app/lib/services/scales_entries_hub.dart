import 'dart:async';

import 'package:flutter/foundation.dart';

import 'scales_month_prefetch_cache.dart';

/// Sinal leve após criar/editar/excluir lançamentos em Escalas.
abstract final class ScalesEntriesHub {
  ScalesEntriesHub._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Timer? _debounce;
  static int _burst = 0;
  static String? _pendingUid;
  static DateTime? _pendingMonth;

  static void notifyMutated({String? uid, DateTime? month}) {
    _burst++;
    if (uid != null && uid.isNotEmpty) _pendingUid = uid;
    if (month != null) _pendingMonth = month;

    // Calendário: sinal imediato (sem debounce) para pintar o dia ao gravar.
    revision.value += _burst;
    _burst = 0;

    if (uid != null && uid.isNotEmpty && month != null) {
      ScalesMonthPrefetchCache.invalidateMonth(uid, month);
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () {
      final u = _pendingUid;
      final m = _pendingMonth;
      _pendingUid = null;
      _pendingMonth = null;
      if (u != null && u.isNotEmpty && m != null) {
        unawaited(ScalesMonthPrefetchCache.prefetchMonth(u, m));
      }
    });
  }
}
