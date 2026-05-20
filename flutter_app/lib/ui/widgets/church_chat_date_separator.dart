import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Rótulo «Hoje», «Ontem» ou data para separadores no chat.
String churchChatDateSeparatorLabel(DateTime messageLocal) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(
    messageLocal.year,
    messageLocal.month,
    messageLocal.day,
  );
  final diff = today.difference(msgDay).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Ontem';
  const months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  return '${messageLocal.day} ${months[messageLocal.month - 1]} ${messageLocal.year}';
}

bool churchChatNeedsDateSeparator({
  required DateTime? olderMessage,
  required DateTime currentMessage,
}) {
  if (olderMessage == null) return true;
  return olderMessage.year != currentMessage.year ||
      olderMessage.month != currentMessage.month ||
      olderMessage.day != currentMessage.day;
}

class ChurchChatDateSeparatorChip extends StatelessWidget {
  const ChurchChatDateSeparatorChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ThemeCleanPremium.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
