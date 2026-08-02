import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CompromissoPasteIconButton extends StatelessWidget {
  const CompromissoPasteIconButton({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Colar',
      icon: const Icon(Icons.content_paste_rounded),
      onPressed: () async {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim();
        if (text == null || text.isEmpty) return;
        controller.text = text;
        onChanged();
      },
    );
  }
}

class CompromissoContactIconActions extends StatelessWidget {
  const CompromissoContactIconActions({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return CompromissoPasteIconButton(controller: controller, onChanged: onChanged);
  }
}
