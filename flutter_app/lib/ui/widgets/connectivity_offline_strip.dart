import 'package:flutter/material.dart';

/// Sincronização silenciosa — sem faixa fixa no topo do painel.
///
/// Feedback via [SyncFeedbackListener] + progresso contextual em uploads explícitos.
class ConnectivityOfflineStrip extends StatelessWidget {
  const ConnectivityOfflineStrip({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
