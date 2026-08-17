import 'package:flutter/material.dart';

class AgendaPreviewActions extends StatelessWidget {
  const AgendaPreviewActions({
    super.key,
    required this.onDetails,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });
  final VoidCallback onDetails;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    children: [
      TextButton.icon(
        onPressed: onDetails,
        icon: const Icon(Icons.visibility_outlined, size: 17),
        label: const Text('Ver detalhes'),
      ),
      if (canEdit)
        IconButton(
          tooltip: 'Editar',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      if (canEdit)
        IconButton(
          tooltip: 'Excluir',
          onPressed: onDelete,
          color: Colors.red,
          icon: const Icon(Icons.delete_outline),
        ),
    ],
  );
}
