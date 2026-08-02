import 'package:flutter/material.dart';

import 'package:gestao_yahweh/constants/commitment_presets.dart';

String hexFromCommitmentColor(Color color) {
  final v = color.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class CommitmentQuickIconsRow extends StatelessWidget {
  const CommitmentQuickIconsRow({
    super.key,
    required this.currentName,
    required this.enabled,
    required this.onPick,
  });

  final String currentName;
  final bool enabled;
  final ValueChanged<CommitmentPreset> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kCommitmentQuickPresets.map((p) {
        return InkWell(
          onTap: enabled ? () => onPick(p) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: p.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(p.icon, color: p.color, size: 18),
                const SizedBox(width: 6),
                Text(p.name, style: TextStyle(fontSize: 11, color: p.color)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

Future<CommitmentPreset?> showCommitmentDescriptionPicker({
  required BuildContext context,
  required String uid,
  String initialQuery = '',
}) async {
  return showModalBottomSheet<CommitmentPreset>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final q = initialQuery.trim().toLowerCase();
      final items = kCommitmentPresets
          .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
          .toList();
      return SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (_, i) {
            final p = items[i];
            return ListTile(
              leading: Icon(p.icon, color: p.color),
              title: Text(p.name),
              onTap: () => Navigator.pop(ctx, p),
            );
          },
        ),
      );
    },
  );
}
