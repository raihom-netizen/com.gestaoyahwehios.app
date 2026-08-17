import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

class MasterChurchNoticeButton extends StatelessWidget {
  const MasterChurchNoticeButton({
    super.key,
    required this.churchId,
    required this.canEdit,
  });

  final String churchId;
  final bool canEdit;

  Future<void> _openComposer(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    try {
      final send = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enviar aviso ao gestor'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Título'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: body,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Mensagem'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (send != true) return;
      final titleText = title.text.trim();
      final bodyText = body.text.trim();
      if (titleText.isEmpty || bodyText.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar(
              'Informe o título e a mensagem do aviso.',
            ),
          );
        }
        return;
      }
      await ChurchUiCollections.avisos(churchId).add({
        'titulo': titleText,
        'title': titleText,
        'conteudo': bodyText,
        'content': bodyText,
        'publicado': true,
        'ativo': true,
        'origem': 'painel_master',
        'tenantId': churchId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Aviso enviado ao gestor.'),
        );
      }
    } finally {
      title.dispose();
      body.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: canEdit ? () => _openComposer(context) : null,
    tooltip: 'Enviar aviso ao gestor',
    icon: const Icon(Icons.campaign_rounded),
  );
}
