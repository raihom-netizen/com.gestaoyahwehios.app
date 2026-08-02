import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:gestao_yahweh/ui/pages/anexo_viewer_page.dart';

/// Exibe o preview do anexo (PDF/imagem) em painel na mesma tela — não abre outra rota.
/// Painel desliza de baixo com o preview (como módulo Relatórios); "Voltar" fecha o painel e mantém o usuário no mesmo lugar.
/// Padrão: Financeiro, Painel, Relatórios, Agenda, etc.
void mostrarAnexoNaMesmaTela(BuildContext context, {required String url, String fileName = 'Comprovante'}) {
  if (url.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há anexo para este lançamento.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final trimmed = url.trim();
  // Mobile/desktop: começa o download já — em paralelo com a animação do bottom sheet (perceção mais rápida).
  final Future<http.Response>? prefetch = (!kIsWeb && trimmed.isNotEmpty) ? http.get(Uri.parse(trimmed)) : null;
  try {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (_, _) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnexoViewerScreen(url: url, fileName: fileName, prefetchResponse: prefetch),
        ),
      ),
    );
  } catch (e, st) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o anexo. Tente novamente.'),
          backgroundColor: Color(0xFFB00020),
        ),
      );
    }
    debugPrint('mostrarAnexoNaMesmaTela: $e\n$st');
  }
}
