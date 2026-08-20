import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:gestao_yahweh/services/church_relatorios_load_service.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/finance_opening_balance_service.dart';
import 'package:gestao_yahweh/services/post_save_background_coordinator.dart';

/// Sinal global leve: qualquer gravação/alteração em lançamentos financeiros
/// incrementa [revision] para painéis, gráficos e sheets que usam Future/cache.
abstract final class FinanceTransactionsHub {
  FinanceTransactionsHub._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Ids já apagados do Firestore nesta sessão.
  ///
  /// A exclusão remove o documento na hora, mas as listas do Financeiro na web
  /// não são listeners ao vivo — são `get` com poll (até 3 min). Sem isto, a
  /// linha continuava no ecrã depois de apagada e parecia que «não removeu».
  /// Quem pinta lista de lançamentos filtra por [foiApagado].
  static final Set<String> _apagados = <String>{};

  /// Marca um lançamento como apagado e acorda quem está a mostrar listas.
  static void marcarApagado(String docId) {
    final id = docId.trim();
    if (id.isEmpty) return;
    _apagados.add(id);
    revision.value += 1;
  }

  static bool foiApagado(String? docId) {
    final id = (docId ?? '').trim();
    return id.isNotEmpty && _apagados.contains(id);
  }

  /// Limpa o registo (ex.: ao trocar de igreja) — os ids não se repetem, mas
  /// não vale a pena manter o conjunto a crescer para sempre.
  static void limparApagados() => _apagados.clear();

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
        // Sem isto, quem recarregasse sem `forceRefresh` recebia a lista
        // velha do cache em RAM: o total do membro/fornecedor so mudava ao
        // fim do TTL ou com «Atualizar» a mao. Avisar os ecras e deixar o
        // cache com o que ja nao existe e meio caminho.
        ChurchFinanceLoadService.invalidateRam(u);
        ChurchRelatoriosLoadService.invalidateFinance(u);
        PostSaveBackgroundCoordinator.scheduleFinanceWidget(u);
      }
    });
  }
}
