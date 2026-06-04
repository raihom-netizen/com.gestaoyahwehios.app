import 'package:flutter/material.dart';

/// Rodapé padrão «Carregar mais» — paginação lazy (§17 prompt mestre).
class LazyLoadMoreFooter extends StatelessWidget {
  const LazyLoadMoreFooter({
    super.key,
    required this.onLoadMore,
    this.label = 'Carregar mais',
    this.loading = false,
    this.visible = true,
  });

  final VoidCallback onLoadMore;
  final String label;
  final bool loading;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(label),
              ),
      ),
    );
  }
}
