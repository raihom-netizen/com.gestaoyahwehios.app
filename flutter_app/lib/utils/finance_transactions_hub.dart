import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:gestao_yahweh/services/finance_opening_balance_service.dart';
import 'package:gestao_yahweh/services/post_save_background_coordinator.dart';

/// Sinal global leve: qualquer gravação/alteração em lançamentos financeiros
/// incrementa [revision] para painéis, gráficos e sheets que usam Future/cache.
abstract final class FinanceTransactionsHub {
  FinanceTransactionsHub._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Timer? _debounce;
  static int _burstCount = 0;
  static String? _pendingUid;
  static DateTime? _pendingEffectiveDate;
  static bool _pendingInvalidateOpening = true;

  /// Chamado após criar, editar, excluir ou confirmar lançamentos.
  /// Debounce curto (~80ms) para Agenda/Escalas refletirem na hora;
  /// efeitos pesados (saldo abertura / widget) ficam no mesmo tick coalescido.
  static void notifyMutated({
    String? uid,
    DateTime? effectiveDate,
    bool invalidateOpeningBalance = true,
  }) {
    _burstCount++;
    if (uid != null && uid.isNotEmpty) _pendingUid = uid;
    if (effectiveDate != null) _pendingEffectiveDate = effectiveDate;
    if (!invalidateOpeningBalance) _pendingInvalidateOpening = false;

    _debounce?.cancel();
    // Antes: 520ms — pendentes demoravam a aparecer/sumir na Agenda.
    _debounce = Timer(const Duration(milliseconds: 80), () {
      final count = _burstCount;
      _burstCount = 0;
      revision.value += count;

      final u = _pendingUid;
      final date = _pendingEffectiveDate;
      final inv = _pendingInvalidateOpening;
      _pendingUid = null;
      _pendingEffectiveDate = null;
      _pendingInvalidateOpening = true;

      if (inv && u != null && u.isNotEmpty) {
        if (date != null) {
          FinanceOpeningBalanceService.invalidateIfBefore(u, date);
        } else {
          FinanceOpeningBalanceService.invalidateForUser(u);
        }
      }
      if (u != null && u.isNotEmpty) {
        PostSaveBackgroundCoordinator.scheduleFinanceWidget(u);
      }
    });
  }
}
