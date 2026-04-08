import 'package:flutter/foundation.dart';

/// Upload em segundo plano: barra de progresso persistente (não bloqueia navegação).
class GlobalUploadProgress {
  GlobalUploadProgress._();
  static final GlobalUploadProgress instance = GlobalUploadProgress._();

  final ValueNotifier<GlobalUploadProgressState?> state =
      ValueNotifier<GlobalUploadProgressState?>(null);

  void start(String label) {
    state.value = GlobalUploadProgressState(label: label, progress: 0);
  }

  void update(double progress) {
    final s = state.value;
    if (s == null) return;
    state.value = s.copyWith(progress: progress.clamp(0.0, 1.0));
  }

  void end() {
    state.value = null;
  }
}

class GlobalUploadProgressState {
  final String label;
  final double progress;

  const GlobalUploadProgressState({
    required this.label,
    required this.progress,
  });

  GlobalUploadProgressState copyWith({String? label, double? progress}) {
    return GlobalUploadProgressState(
      label: label ?? this.label,
      progress: progress ?? this.progress,
    );
  }
}
