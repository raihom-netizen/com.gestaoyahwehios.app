import 'package:flutter/material.dart';

/// Paleta canónica WhatsApp — header, bolhas e fundos (Web / mobile).
abstract final class ChurchChatWhatsAppTheme {
  ChurchChatWhatsAppTheme._();

  static const Color header = Color(0xFF128C7E);
  static const Color headerDark = Color(0xFF075E54);
  static const Color outgoingBubble = Color(0xFFD9FDD3);
  static const Color incomingBubble = Color(0xFFFFFFFF);
  static const Color threadBackground = Color(0xFFECE5DD);
  static const Color hubBackground = Color(0xFFF0F2F5);
  static const Color inputBarBackground = Color(0xFFF0F2F5);
  static const Color activeRowBackground = Color(0xFFF0F2F5);
  static const Color chipSelected = Color(0xFF128C7E);
  static const Color chipUnselectedBg = Color(0xFFE9EDEF);
}

/// Chips horizontais — Tudo · Não lidas · Favoritas · Grupos (referência WhatsApp Web).
class ChurchChatWhatsAppFilterChips<T extends Enum> extends StatelessWidget {
  const ChurchChatWhatsAppFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.items,
    required this.labelFor,
  });

  final T selected;
  final ValueChanged<T> onSelected;
  final List<T> items;
  final String Function(T) labelFor;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  labelFor(item),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected == item
                        ? ChurchChatWhatsAppTheme.chipSelected
                        : const Color(0xFF54656F),
                  ),
                ),
                selected: selected == item,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                backgroundColor: ChurchChatWhatsAppTheme.chipUnselectedBg,
                selectedColor: const Color(0xFFE7F8F3),
                side: BorderSide(
                  color: selected == item
                      ? ChurchChatWhatsAppTheme.chipSelected.withValues(alpha: 0.35)
                      : Colors.transparent,
                ),
                onSelected: (_) => onSelected(item),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Painel direito vazio no split Web (antes de escolher conversa).
class ChurchChatWhatsAppSplitEmptyPane extends StatelessWidget {
  const ChurchChatWhatsAppSplitEmptyPane({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChurchChatWhatsAppTheme.hubBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 88,
                color: ChurchChatWhatsAppTheme.header.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 20),
              Text(
                'Chat Igreja',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Selecione uma conversa à esquerda para enviar e receber mensagens '
                'com o mesmo fluxo do WhatsApp — texto, fotos, vídeos, reações e apagar para si ou para todos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
