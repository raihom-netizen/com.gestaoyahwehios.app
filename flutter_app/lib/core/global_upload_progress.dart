import 'dart:async';

import 'package:flutter/foundation.dart';

/// Upload em segundo plano: barra de progresso persistente (não bloqueia navegação).
class GlobalUploadProgress {
  GlobalUploadProgress._();
  static final GlobalUploadProgress instance = GlobalUploadProgress._();

  final ValueNotifier<GlobalUploadProgressState?> state =
      ValueNotifier<GlobalUploadProgressState?>(null);

  Timer? _watchdog;
  static const Duration _staleAfter = Duration(minutes: 14);

  void start(String label, {int? totalItems}) {
    _watchdog?.cancel();
    state.value = GlobalUploadProgressState(
      label: label,
      progress: 0,
      currentItem: totalItems != null && totalItems > 0 ? 0 : null,
      totalItems: totalItems,
    );
    _watchdog = Timer(_staleAfter, end);
  }

  void startBatch({
    required String itemLabel,
    required int totalItems,
  }) {
    start(itemLabel, totalItems: totalItems);
  }

  void update(double progress) {
    final s = state.value;
    if (s == null) return;
    state.value = s.copyWith(progress: progress.clamp(0.0, 1.0));
  }

  void updateBatch({
    required int currentItem,
    required int totalItems,
    required double slotProgress01,
  }) {
    final s = state.value;
    if (s == null) return;
    final overall = totalItems <= 0
        ? slotProgress01.clamp(0.0, 1.0)
        : ((currentItem - 1) + slotProgress01.clamp(0.0, 1.0)) /
            totalItems;
    state.value = s.copyWith(
      currentItem: currentItem.clamp(1, totalItems),
      totalItems: totalItems,
      progress: overall.clamp(0.0, 1.0),
    );
  }

  void end() {
    _watchdog?.cancel();
    _watchdog = null;
    state.value = null;
  }
}

class GlobalUploadProgressState {
  final String label;
  final double progress;
  final int? currentItem;
  final int? totalItems;

  const GlobalUploadProgressState({
    required this.label,
    required this.progress,
    this.currentItem,
    this.totalItems,
  });

  /// Ex.: «Imagem 2/5 — 72%» (percepção de velocidade).
  String get displayLabel {
    final pct = (progress * 100).round().clamp(0, 100);
    if (currentItem != null &&
        totalItems != null &&
        totalItems! > 0 &&
        currentItem! > 0) {
      return '$label $currentItem/$totalItems — $pct%';
    }
    if (progress > 0 && progress < 1) {
      return '$label — $pct%';
    }
    return label;
  }

  GlobalUploadProgressState copyWith({
    String? label,
    double? progress,
    int? currentItem,
    int? totalItems,
  }) {
    return GlobalUploadProgressState(
      label: label ?? this.label,
      progress: progress ?? this.progress,
      currentItem: currentItem ?? this.currentItem,
      totalItems: totalItems ?? this.totalItems,
    );
  }
}
