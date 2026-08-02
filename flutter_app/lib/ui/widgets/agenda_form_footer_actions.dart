import 'package:flutter/material.dart';

class AgendaFormFooterActions extends StatelessWidget {
  const AgendaFormFooterActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
    this.isBusy = false,
    this.busyLabel = 'Salvando…',
    this.saveIcon = Icons.save_rounded,
  });

  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;
  final bool isBusy;
  final String busyLabel;
  final IconData saveIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(onPressed: isBusy ? null : onCancel, child: const Text('Cancelar')),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: isBusy ? null : onSave,
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(saveIcon),
            label: Text(isBusy ? busyLabel : saveLabel),
          ),
        ),
      ],
    );
  }
}
