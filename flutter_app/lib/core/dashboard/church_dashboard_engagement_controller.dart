import 'package:flutter/foundation.dart';

/// Estado compartilhado do dashboard (filtros de engajamento / aniversariantes).
/// Mantido leve — sem GetX/Provider obrigatórios; o painel usa [ListenableBuilder].
class ChurchDashboardEngagementController extends ChangeNotifier {
  /// 0 = Hoje, 1 = Esta semana, 2 = Mês corrente
  int birthdayFilterTab = 0;

  void setBirthdayTab(int v) {
    if (v < 0 || v > 2 || v == birthdayFilterTab) return;
    birthdayFilterTab = v;
    notifyListeners();
  }
}
