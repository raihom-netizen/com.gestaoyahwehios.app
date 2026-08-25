import 'package:flutter/material.dart';

/// Ações de um compromisso da Agenda: **ver detalhes, alterar e excluir**.
///
/// Os três ícones são o mesmo contrato em toda a Agenda — resumo do dia,
/// prévia do dia e cards do mês. Vão em botões redondos com fundo tingido
/// porque, cinzentos e sem fundo, ninguém percebia que eram clicáveis.
class AgendaPreviewActions extends StatelessWidget {
  const AgendaPreviewActions({
    super.key,
    required this.onDetails,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  final VoidCallback onDetails;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Só ícones — para o card estreito do resumo do dia.
  final bool compact;

  static const Color _ver = Color(0xFF1D4ED8);
  static const Color _editar = Color(0xFF7C3AED);
  static const Color _excluir = Color(0xFFDC2626);

  Widget _botao({
    required IconData icone,
    required String dica,
    required Color cor,
    required VoidCallback aoTocar,
  }) {
    return Tooltip(
      message: dica,
      child: Material(
        color: cor.withValues(alpha: 0.10),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icone, size: 18, color: cor),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acoes = <Widget>[
      _botao(
        icone: Icons.visibility_rounded,
        dica: 'Ver detalhes',
        cor: _ver,
        aoTocar: onDetails,
      ),
      if (canEdit)
        _botao(
          icone: Icons.edit_rounded,
          dica: 'Alterar',
          cor: _editar,
          aoTocar: onEdit,
        ),
      if (canEdit)
        _botao(
          icone: Icons.delete_rounded,
          dica: 'Excluir',
          cor: _excluir,
          aoTocar: onDelete,
        ),
    ];

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < acoes.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            acoes[i],
          ],
        ],
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: onDetails,
          style: TextButton.styleFrom(foregroundColor: _ver),
          icon: const Icon(Icons.visibility_rounded, size: 17),
          label: const Text('Ver detalhes'),
        ),
        ...acoes.skip(1),
      ],
    );
  }
}
