import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Estado padronizado de módulos do painel — evita tela branca e spinner infinito.
enum BlindPanelLoadPhase {
  idle,
  loading,
  ready,
  empty,
  error,
}

class BlindPanelLoadState<T> {
  const BlindPanelLoadState({
    this.phase = BlindPanelLoadPhase.idle,
    this.data,
    this.errorMessage,
  });

  final BlindPanelLoadPhase phase;
  final T? data;
  final String? errorMessage;

  bool get isLoading => phase == BlindPanelLoadPhase.loading;
  bool get hasError => phase == BlindPanelLoadPhase.error;
  bool get isEmpty => phase == BlindPanelLoadPhase.empty;
  bool get isReady => phase == BlindPanelLoadPhase.ready;

  BlindPanelLoadState<T> copyWith({
    BlindPanelLoadPhase? phase,
    T? data,
    String? errorMessage,
  }) =>
      BlindPanelLoadState(
        phase: phase ?? this.phase,
        data: data ?? this.data,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

/// Corpo de lista/módulo com estados loading, erro, vazio e conteúdo.
class BlindPanelBody extends StatelessWidget {
  const BlindPanelBody({
    super.key,
    required this.phase,
    required this.ready,
    this.loading,
    this.emptyMessage = 'Nenhum registro encontrado.',
    this.errorMessage,
    this.onRetry,
  });

  final BlindPanelLoadPhase phase;
  final Widget ready;
  final Widget? loading;
  final String emptyMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case BlindPanelLoadPhase.loading:
      case BlindPanelLoadPhase.idle:
        return SizedBox.expand(
          child: loading ??
              const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        );
      case BlindPanelLoadPhase.error:
        return SizedBox.expand(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 44, color: Colors.orange.shade700),
                  const SizedBox(height: 12),
                  Text(
                    errorMessage?.trim().isNotEmpty == true
                        ? errorMessage!.trim()
                        : 'Erro de conexão ao carregar dados.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      case BlindPanelLoadPhase.empty:
        return SizedBox.expand(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: ThemeCleanPremium.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      case BlindPanelLoadPhase.ready:
        return ready;
    }
  }
}
