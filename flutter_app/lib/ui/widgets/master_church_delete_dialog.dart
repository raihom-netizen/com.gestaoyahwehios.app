import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/master_church_delete_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Confirmação + exclusão total de uma igreja.
///
/// Ponto **único** desta ação. Havia antes um botão «Exclusão total no banco»
/// que apagava coleção a coleção a partir do cliente: as regras do Firestore
/// negam esse varrimento (`permission-denied`), e mesmo que passassem nunca
/// tocavam no Storage. A exclusão real corre numa Cloud Function com o Admin
/// SDK — ver [MasterChurchDeleteService].
///
/// Devolve `true` quando a igreja foi mesmo apagada.
Future<bool> confirmAndDeleteChurch({
  required BuildContext context,
  required String tenantId,
  required String churchName,
}) async {
  final ctrl = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final match = ctrl.text.trim() == tenantId.trim();
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          title: Row(
            children: [
              Icon(
                Icons.delete_forever_rounded,
                color: ThemeCleanPremium.error,
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Excluir igreja')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Isto apaga DEFINITIVAMENTE "$churchName":\n\n'
                  '• todos os dados no Firestore (membros, financeiro, '
                  'eventos, escalas, documentos — tudo abaixo da igreja)\n'
                  '• todos os ficheiros no Storage (fotos, vídeos, PDFs, logo)\n'
                  '• o site público e o link de cadastro de membros\n\n'
                  'Não é possível desfazer. As contas de login não são '
                  'apagadas (a mesma pessoa pode pertencer a outra igreja).',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Para confirmar, escreva o ID da igreja:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  tenantId,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.error,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'ID da igreja',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error,
              ),
              onPressed: match ? () => Navigator.pop(ctx, true) : null,
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Excluir tudo'),
            ),
          ],
        );
      },
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  // Progresso bloqueante: apagar uma igreja grande leva algum tempo e não pode
  // parecer que nada aconteceu.
  unawaitedShowProgress(context);
  try {
    final res = await MasterChurchDeleteService.deleteChurch(
      tenantId: tenantId,
      confirmTenantId: tenantId,
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // fecha o progresso
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Igreja excluída — ${res.storageFilesDeleted} ficheiro(s) '
          'removido(s) do Storage.',
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível excluir: $e'),
          backgroundColor: ThemeCleanPremium.error,
          duration: const Duration(seconds: 8),
        ),
      );
    }
    return false;
  }
}

/// Diálogo de progresso não fechável enquanto a exclusão corre.
void unawaitedShowProgress(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'A excluir a igreja…',
                style: TextStyle(
                  fontSize: 13,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
