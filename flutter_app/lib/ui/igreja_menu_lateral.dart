import 'package:flutter/material.dart';

class IgrejaMenuLateral extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  const IgrejaMenuLateral({super.key, required this.selectedIndex, required this.onItemSelected});

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
    ];
    return Container(
      width: 220,
      color: const Color(0xFF1565C0),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.church, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text('Menu Igreja', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 24),
          for (var i = 0; i < items.length; i++)
            ListTile(
              leading: Icon(items[i]['icon'] as IconData, color: selectedIndex == i ? Colors.yellow : Colors.white),
              title: Text(items[i]['label'] as String, style: TextStyle(color: selectedIndex == i ? Colors.yellow : Colors.white)),
              selected: selectedIndex == i,
              selectedTileColor: Colors.blue[900],
              onTap: () => onItemSelected(i),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
