import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_contact_button_labels.dart';

/// Paleta canónica Yahweh Chat — header teal, bolhas e fundos (Web / mobile).
abstract final class ChurchChatWhatsAppTheme {
  ChurchChatWhatsAppTheme._();

  /// Teal Yahweh (#0D9488) — alinhado ao módulo Chat do shell.
  static const Color header = Color(0xFF0D9488);
  static const Color headerDark = Color(0xFF0F766E);
  static const Color outgoingBubble = Color(0xFFCCFBF1);
  static const Color incomingBubble = Color(0xFFFFFFFF);
  static const Color threadBackground = Color(0xFFF0FDFA);
  static const Color hubBackground = Color(0xFFF8FAFC);
  static const Color inputBarBackground = Color(0xFFF1F5F9);
  static const Color activeRowBackground = Color(0xFFECFEFF);
  static const Color chipSelected = Color(0xFF0D9488);
  static const Color chipUnselectedBg = Color(0xFFE2E8F0);
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
                selectedColor: const Color(0xFFCCFBF1),
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
                YahwehContactButtonLabels.yahwehChat,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Toque num departamento ou conversa privada à esquerda. '
                'Fotos, vídeos, voz e arquivos — tudo dentro do app.',
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
