import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';

/// Política de módulos do painel — carregar sob demanda (menos RAM / arranque rápido).
///
/// Padrão Controle Total + nav rápida:
/// - **Web:** IndexedStack com **ativo + anterior** (troca de aba sem remount frio).
/// - **Mobile:** ativo + anterior + painel — troca de aba instantânea.
/// - **Desktop:** IndexedStack com páginas visitadas (LRU).
abstract final class ChurchShellLazyModulePolicy {
  ChurchShellLazyModulePolicy._();

  /// Índice do dashboard no shell.
  static const int dashboardIndex = ChurchShellIndices.painel;

  /// Atalhos do rodapé mobile — fixos + extras (Doação, Visitantes, Orações…).
  static const Set<int> mobileFooterIndices = {
    ChurchShellIndices.painel,
    ChurchShellIndices.agenda,
    ChurchShellIndices.membros,
    ChurchShellIndices.muralAvisos,
    ChurchShellIndices.muralEventos,
    ChurchShellIndices.chatIgreja,
    ChurchShellIndices.doacao,
    ChurchShellIndices.visitantes,
    ChurchShellIndices.pedidosOracao,
    ChurchShellIndices.minhaEscala,
    ChurchShellIndices.utilitarios,
  };

  /// Módulos pesados fora do rodapé — não pré-montar no arranque.
  static const Set<int> heavyModuleIndices = {
    ChurchShellIndices.departamentos,
    ChurchShellIndices.financeiro,
    ChurchShellIndices.patrimonio,
    ChurchShellIndices.fornecedores,
  };

  /// Compat ? preferir [retainLimitForPlatform].
  static const int kMaxRetainedMaterializedModules = 8;

  /// Desktop **real** (Windows/Linux/macOS) — não confundir com [isDesktop],
  /// que é só a largura da janela (um tablet deitado também é «desktop»).
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Web: 2 (ativo+anterior) | Desktop nativo: 3 | Mobile: 3 | Tablet largo: 8.
  ///
  /// No Windows o Firestore é o SDK C++ e cada módulo vivo mantém listeners
  /// que passam pela thread de plataforma — segurar 8 módulos montados era o
  /// que deixava o app «Não está respondendo» com o uso normal.
  static int retainLimitForPlatform({required bool isDesktop}) {
    if (kIsWeb) return 2;
    if (isDesktopPlatform) return 3;
    if (isDesktop) return 8;
    return 3;
  }

  /// Índices a manter vivos após troca de aba (padrão CT + nav rápida Web).
  static Set<int> retainSet({
    required int currentIdx,
    required int previousIdx,
    required bool isDesktop,
  }) {
    if (kIsWeb) {
      // Ativo + anterior — troca de módulo instantânea sem remount frio.
      return {currentIdx, previousIdx};
    }
    if (isDesktop) {
      return {currentIdx, previousIdx, dashboardIndex};
    }
    // Mobile: painel + ativo + anterior — nav instantânea no rodapé.
    return {dashboardIndex, currentIdx, previousIdx};
  }

  /// Evicta páginas antigas do [pageCache].
  static void evictStaleModules({
    required List<Widget?> pageCache,
    required int activeIndex,
    required List<int> lruIndices,
    int? maxRetain,
  }) {
    final limit = maxRetain ??
        (kIsWeb ? 2 : kMaxRetainedMaterializedModules);
    if (lruIndices.length <= limit) return;
    while (lruIndices.length > limit) {
      final evict = lruIndices.removeAt(0);
      if (evict == activeIndex || evict == dashboardIndex) {
        lruIndices.add(evict);
        if (lruIndices.length <= limit) break;
        continue;
      }
      if (evict >= 0 && evict < pageCache.length) {
        pageCache[evict] = null;
      }
    }
  }

  /// Prefetch ao passar o rato **nunca** no desktop nativo: no Windows o
  /// cursor cruza a barra lateral inteira a cada movimento e disparava a carga
  /// Firestore de Membros, Departamentos, Financeiro, Património e
  /// Fornecedores ao mesmo tempo — Android/iOS não têm hover, por isso só o
  /// Windows travava. Lá o prefetch acontece só ao abrir o módulo.
  static bool shouldPrefetchOnHover(int index) =>
      !kIsWeb && !isDesktopPlatform && heavyModuleIndices.contains(index);

  static bool keepMountedOnMobile(int index) => isMobileFooterTab(index);

  static bool isMobileFooterTab(int index) =>
      mobileFooterIndices.contains(index);
}
