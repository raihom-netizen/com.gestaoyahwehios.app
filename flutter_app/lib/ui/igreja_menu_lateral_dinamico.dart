import 'package:flutter/material.dart';

class IgrejaMenuLateralDinamico extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  const IgrejaMenuLateralDinamico({super.key, required this.selectedIndex, required this.onItemSelected, this.isCollapsed = false, required this.onToggleCollapse});

  @override
  Widget build(BuildContext context) {
    final items = [
      {'icon': Icons.dashboard, 'label': 'Painel'},
      {'icon': Icons.people, 'label': 'Membros'},
      {'icon': Icons.groups, 'label': 'Departamentos'},
      {'icon': Icons.event, 'label': 'Eventos'},
      {'icon': Icons.cake, 'label': 'Aniversariantes'},
      {'icon': Icons.announcement, 'label': 'Avisos'},
      {'icon': Icons.leaderboard, 'label': 'Liderança'},
      {'icon': Icons.bar_chart, 'label': 'Relatórios'},
      {'icon': Icons.verified_user, 'label': 'Permissões'},
      {'icon': Icons.pending_actions, 'label': 'Aprovar Membros'},
    ];
    final width = isCollapsed ? 64.0 : 220.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isMobile ? (isCollapsed ? 0 : width) : width,
          decoration: const BoxDecoration(
            color: Color(0xFF0D47A1),
            boxShadow: [BoxShadow(color: Color(0x20000000), blurRadius: 12, offset: Offset(2, 0))],
          ),
          child: isMobile && isCollapsed
              ? null
              : Column(
                  children: [
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.church, color: Colors.white, size: isCollapsed ? 28 : 40),
                    ),
                    if (!isCollapsed) ...[
                      const SizedBox(height: 14),
                      const Text('Menu Igreja', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: 0.3)),
                      const SizedBox(height: 20),
                    ],
                    for (var i = 0; i < items.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        child: Material(
                          color: selectedIndex == i ? Colors.white.withOpacity(0.18) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: Icon(items[i]['icon'] as IconData, color: Colors.white, size: 22),
                            title: isCollapsed ? null : Text(items[i]['label'] as String, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                            selected: selectedIndex == i,
                            onTap: () => onItemSelected(i),
                            minLeadingWidth: 0,
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: Icon(isCollapsed ? Icons.chevron_right : Icons.chevron_left, color: Colors.white70, size: 26),
                      tooltip: isCollapsed ? 'Expandir menu' : 'Recolher menu',
                      onPressed: onToggleCollapse,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
        );
      },
    );
  }
}
