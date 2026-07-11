import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Filtro moderno — um ou mais departamentos (folha inferior com checkboxes).
class MemberDepartmentMultiFilterField extends StatelessWidget {
  const MemberDepartmentMultiFilterField({
    super.key,
    required this.departments,
    required this.selectedIds,
    required this.onChanged,
    this.borderRadius = 16,
  });

  final List<({String id, String name})> departments;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final double borderRadius;

  static String summary(
    Set<String> selectedIds,
    List<({String id, String name})> departments,
  ) {
    if (selectedIds.isEmpty) return 'Todos os departamentos';
    if (selectedIds.length == 1) {
      final id = selectedIds.first;
      for (final d in departments) {
        if (d.id == id) return d.name;
      }
      return '1 departamento';
    }
    return '${selectedIds.length} departamentos selecionados';
  }

  static Future<Set<String>?> showPicker(
    BuildContext context, {
    required List<({String id, String name})> departments,
    required Set<String> initial,
    String title = 'Filtrar por departamento',
  }) {
    if (departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum departamento cadastrado nesta igreja.'),
        ),
      );
      return Future.value(null);
    }
    return showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FAFC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var temp = {...initial};
        return StatefulBuilder(
          builder: (ctx, setS) {
            final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.paddingOf(ctx).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.2,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Selecione um ou mais departamentos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setS(() {
                            temp = departments.map((d) => d.id).toSet();
                          }),
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: const Text('Marcar todos'),
                        ),
                        TextButton.icon(
                          onPressed: () => setS(() => temp.clear()),
                          icon: const Icon(Icons.clear_all_rounded, size: 18),
                          label: const Text('Limpar'),
                        ),
                      ],
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final d in departments)
                            CheckboxListTile(
                              value: temp.contains(d.id),
                              onChanged: (v) => setS(() {
                                if (v == true) {
                                  temp.add(d.id);
                                } else {
                                  temp.remove(d.id);
                                }
                              }),
                              title: Text(
                                d.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              secondary: CircleAvatar(
                                radius: 16,
                                backgroundColor: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.12),
                                child: Icon(
                                  Icons.groups_rounded,
                                  size: 16,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, temp),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary,
                            ),
                            child: const Text('Aplicar filtro'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = departments.isNotEmpty;
    final hasSelection = selectedIds.isNotEmpty;
    final radius = BorderRadius.circular(borderRadius);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () async {
                final picked = await showPicker(
                  context,
                  departments: departments,
                  initial: selectedIds,
                );
                if (picked != null) onChanged(picked);
              }
            : null,
        borderRadius: radius,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Departamentos',
            hintText: enabled
                ? 'Toque para selecionar um ou mais'
                : 'Carregando ou sem departamentos…',
            prefixIcon: Icon(
              Icons.account_tree_rounded,
              size: 20,
              color: hasSelection
                  ? ThemeCleanPremium.primary
                  : Colors.grey.shade600,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasSelection)
                  IconButton(
                    tooltip: 'Limpar filtro de departamento',
                    onPressed: () => onChanged({}),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: Colors.grey.shade600),
                  ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade600),
                const SizedBox(width: 4),
              ],
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: radius),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: hasSelection
                    ? ThemeCleanPremium.primary.withValues(alpha: 0.45)
                    : Colors.grey.shade300,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          child: Text(
            summary(selectedIds, departments),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: enabled
                  ? (hasSelection
                      ? ThemeCleanPremium.primary
                      : Colors.grey.shade800)
                  : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}
