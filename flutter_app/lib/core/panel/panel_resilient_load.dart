import 'package:flutter/foundation.dart' show kIsWeb;

/// Estado UI padrão — listagens do painel igreja (offline-first invisível).
class PanelLoadUiState {
  const PanelLoadUiState({
    this.fetching = false,
    this.showingStaleCache = false,
    this.loadError,
  });

  final bool fetching;
  final bool showingStaleCache;
  final String? loadError;

  bool get hasBlockingError =>
      loadError != null && loadError!.trim().isNotEmpty;

  PanelLoadUiState copyWith({
    bool? fetching,
    bool? showingStaleCache,
    String? loadError,
    bool clearError = false,
  }) =>
      PanelLoadUiState(
        fetching: fetching ?? this.fetching,
        showingStaleCache: showingStaleCache ?? this.showingStaleCache,
        loadError: clearError ? null : (loadError ?? this.loadError),
      );
}

/// Regras sistémicas de carga — nunca apagar cache local por falha de rede.
abstract final class PanelResilientLoad {
  PanelResilientLoad._();

  static const Duration webQueryCap = Duration(seconds: 14);
  static const Duration webLoadingCap = Duration(seconds: 14);

  static Duration get queryCap => kIsWeb ? webQueryCap : const Duration(seconds: 90);

  /// Após fetch: preserva dados locais; erro bloqueante só sem cache.
  static PanelLoadUiState afterFetch<T>({
    required bool hadLocalData,
    required List<T> newItems,
    required bool fromCache,
    String? softError,
    bool forceFresh = false,
  }) {
    if (newItems.isNotEmpty) {
      return PanelLoadUiState(
        fetching: false,
        showingStaleCache: fromCache && !forceFresh,
        loadError: null,
      );
    }
    if (hadLocalData) {
      return const PanelLoadUiState(
        fetching: false,
        showingStaleCache: true,
        loadError: null,
      );
    }
    return PanelLoadUiState(
      fetching: false,
      showingStaleCache: false,
      loadError: softError,
    );
  }

  /// Após exceção: mantém UI se já havia dados.
  static PanelLoadUiState afterError({
    required bool hadLocalData,
    Object? error,
  }) {
    if (hadLocalData) {
      return const PanelLoadUiState(
        fetching: false,
        showingStaleCache: true,
        loadError: null,
      );
    }
    return PanelLoadUiState(
      fetching: false,
      showingStaleCache: false,
      loadError: error?.toString(),
    );
  }

  /// Seed local antes da rede — skeleton só se lista vazia.
  static bool shouldShowFetching({
    required bool listEmpty,
    bool forceRefresh = false,
  }) =>
      listEmpty && !forceRefresh;
}
