import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'busca_global_widget.dart';
import 'grafico_ultra_moderno.dart';
import 'igreja_menu_lateral_dinamico.dart';
import 'pages/members_page.dart';
import 'pages/departments_page.dart';
import 'pages/events_manager_page.dart';
import 'pages/mural_page.dart';
import 'pages/notifications_page.dart';
import 'pages/my_schedules_page.dart';
import 'pages/schedules_page.dart';
import 'pages/finance_page.dart';
import 'pages/member_card_page.dart';
import 'pages/usuarios_permissoes_page.dart';
import 'pages/aprovar_membros_pendentes_page.dart';

class IgrejaPainelPage extends StatefulWidget {
  const IgrejaPainelPage({super.key});

  @override
  State<IgrejaPainelPage> createState() => _IgrejaPainelPageState();
}

class _IgrejaPainelPageState extends State<IgrejaPainelPage> {
  int _menuIndex = 0;
  bool _loading = false;
  bool _menuCollapsed = false;
  int _membros = 0, _homens = 0, _mulheres = 0, _criancas = 0, _departamentos = 0;
  double _totalOfertas = 0, _totalDespesas = 0;
  List<Map<String, dynamic>> _aniversariantes = [];
  List<Map<String, dynamic>> _lideres = [];
  List<Map<String, dynamic>> _avisos = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RawKeyboard.instance.addListener(_handleKeyEvent);
      _load();
    });
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_handleKeyEvent);
    super.dispose();
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      final isCtrlK = (event.isControlPressed || event.isMetaPressed) && event.logicalKey.keyLabel.toLowerCase() == 'k';
      if (isCtrlK) _abrirBuscaGlobal();
    }
  }

  void _abrirBuscaGlobal() {
    showDialog(context: context, builder: (_) => const BuscaGlobalWidget());
  }

  Future<void> _abrirModulo(int index) async {
    if (index == 0) return; // Painel = fica na própria tela
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String? tenantId;
    String role = 'user';
    String cpf = '';
    try {
      final token = await user.getIdTokenResult(true);
      tenantId = (token.claims?['igrejaId'] ?? token.claims?['tenantId'] ?? '').toString().trim();
      role = (token.claims?['role'] ?? 'user').toString().toLowerCase();
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      cpf = (userDoc.data()?['cpf'] ?? '').toString().trim();
    } catch (_) {}
    if (tenantId == null || tenantId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acesso aos módulos exige login com igreja. Use o app da igreja ou acesse pela tela de login da sua igreja.')),
        );
      }
      return;
    }
    if (!mounted) return;
    switch (index) {
      case 1:
        Navigator.push(context, MaterialPageRoute(builder: (_) => MembersPage(tenantId: tenantId!, role: role)));
        break;
      case 2:
        Navigator.push(context, MaterialPageRoute(builder: (_) => DepartmentsPage(tenantId: tenantId!, role: role)));
        break;
      case 3:
        Navigator.push(context, MaterialPageRoute(builder: (_) => EventsManagerPage(tenantId: tenantId!, role: role)));
        break;
      case 4:
        // Aniversariantes: fica no painel (já exibido)
        setState(() => _menuIndex = 0);
        break;
      case 5:
        // Avisos: pode abrir Mural
        Navigator.push(context, MaterialPageRoute(builder: (_) => MuralPage(tenantId: tenantId!, role: role)));
        break;
      case 6:
        // Liderança: pode abrir Membros filtrado ou manter painel
        Navigator.push(context, MaterialPageRoute(builder: (_) => MembersPage(tenantId: tenantId!, role: role)));
        break;
      case 7:
        // Relatórios: FinancePage tem gráficos
        Navigator.push(context, MaterialPageRoute(builder: (_) => FinancePage(tenantId: tenantId!, role: role)));
        break;
      case 8:
        Navigator.push(context, MaterialPageRoute(builder: (_) => UsuariosPermissoesPage(tenantId: tenantId!, gestorRole: role)));
        break;
      case 9:
        Navigator.push(context, MaterialPageRoute(builder: (_) => AprovarMembrosPendentesPage(tenantId: tenantId!, gestorRole: role)));
        break;
      default:
        setState(() => _menuIndex = index);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final membrosSnap = await FirebaseFirestore.instance.collection('membros').get();
    final depsSnap = await FirebaseFirestore.instance.collection('departamentos').get();
    final avisosSnap = await FirebaseFirestore.instance.collection('avisos').orderBy('data', descending: true).limit(5).get();
    final ofertasSnap = await FirebaseFirestore.instance.collection('financeiro').where('tipo', isEqualTo: 'oferta').get();
    final despesasSnap = await FirebaseFirestore.instance.collection('financeiro').where('tipo', isEqualTo: 'despesa').get();
    final hoje = DateTime.now();
    _membros = membrosSnap.size;
    _homens = membrosSnap.docs.where((d) => d['sexo'] == 'M').length;
    _mulheres = membrosSnap.docs.where((d) => d['sexo'] == 'F').length;
    _criancas = membrosSnap.docs.where((d) => (d['idade'] ?? 0) < 13).length;
    _departamentos = depsSnap.size;
    _totalOfertas = ofertasSnap.docs.fold(0.0, (a, b) => a + (b['valor'] ?? 0));
    _totalDespesas = despesasSnap.docs.fold(0.0, (a, b) => a + (b['valor'] ?? 0));
    _aniversariantes = membrosSnap.docs.where((d) {
      final data = d['dataNascimento'];
      if (data is Timestamp) {
        final dt = data.toDate();
        return dt.month == hoje.month && dt.day == hoje.day;
      }
      return false;
    }).map((d) => d.data()).toList();
    _lideres = membrosSnap.docs.where((d) => d['lider'] == true).map((d) => d.data()).toList();
    _avisos = avisosSnap.docs.map((d) => d.data()).toList();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return Scaffold(
          backgroundColor: const Color(0xFFF0F7FF),
          body: Row(
            children: [
              if (!isMobile || !_menuCollapsed)
                IgrejaMenuLateralDinamico(
                  selectedIndex: _menuIndex,
                  onItemSelected: (i) {
                    if (i == 0) {
                      setState(() => _menuIndex = 0);
                    } else {
                      _abrirModulo(i);
                    }
                  },
                  isCollapsed: _menuCollapsed,
                  onToggleCollapse: () => setState(() => _menuCollapsed = !_menuCollapsed),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Painel Master', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26, color: Color(0xFF0D47A1), letterSpacing: -0.5)),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.search_rounded, color: Color(0xFF0D47A1), size: 26),
                                  tooltip: 'Busca global (Ctrl+K)',
                                  onPressed: _abrirBuscaGlobal,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            // KPIs
                            Wrap(
                              spacing: 18,
                              runSpacing: 18,
                              children: [
                                _MetricCard(label: 'Membros', value: _membros, icon: Icons.people),
                                _MetricCard(label: 'Homens', value: _homens, icon: Icons.male),
                                _MetricCard(label: 'Mulheres', value: _mulheres, icon: Icons.female),
                                _MetricCard(label: 'Crianças', value: _criancas, icon: Icons.child_care),
                                _MetricCard(label: 'Departamentos', value: _departamentos, icon: Icons.groups),
                                _MetricCardMoney(label: r'Ofertas (R$)', value: _totalOfertas, icon: Icons.attach_money),
                                _MetricCardMoney(label: r'Despesas (R$)', value: _totalDespesas, icon: Icons.money_off),
                              ],
                            ),
                            const SizedBox(height: 32),
                            // Gráficos
                            Row(
                              children: [
                                Expanded(child: GraficoUltraModerno(
                                  valores: const [10, 12, 15, 18, 22, 25, 30, 35, 40, 45, 50, 60],
                                  labels: const ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'],
                                  titulo: 'Crescimento de Membros',
                                )),
                                const SizedBox(width: 32),
                                Expanded(child: GraficoUltraModerno(
                                  valores: const [5, 8, 12, 20, 18, 22, 30, 28, 35, 40, 38, 45],
                                  labels: const ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'],
                                  titulo: 'Ofertas Mensais',
                                )),
                              ],
                            ),
                            const SizedBox(height: 32),
                            // Cards de relatórios e atalhos
                            Wrap(
                              spacing: 18,
                              runSpacing: 18,
                              children: [
                                _AtalhoCard(label: 'Relatório de Membros', icon: Icons.people, onTap: () {}),
                                _AtalhoCard(label: 'Relatório Financeiro', icon: Icons.bar_chart, onTap: () {}),
                                _AtalhoCard(label: 'Exportar Dados', icon: Icons.file_download, onTap: () {}),
                                _AtalhoCard(label: 'Gerenciar Usuários', icon: Icons.verified_user, onTap: () {}),
                                _AtalhoCard(label: 'Configurações', icon: Icons.settings, onTap: () {}),
                              ],
                            ),
                            const SizedBox(height: 32),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _aniversariantesWidget()),
                                const SizedBox(width: 24),
                                Expanded(child: _lideresWidget()),
                                const SizedBox(width: 24),
                                Expanded(child: _avisosWidget()),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: isMobile
              ? FloatingActionButton(
                  onPressed: () => setState(() => _menuCollapsed = !_menuCollapsed),
                  child: Icon(_menuCollapsed ? Icons.menu : Icons.close),
                  backgroundColor: const Color(0xFF1565C0),
                )
              : null,
        );
      },
    );
  }

  Widget _aniversariantesWidget() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: Colors.blue.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aniversariantes de hoje', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._aniversariantes.map((m) => Text(m['nome'] ?? '')),
          ],
        ),
      ),
    );
  }

  Widget _lideresWidget() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: Colors.blue.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Destaque de Líderes', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._lideres.take(5).map((m) => Text(m['nome'] ?? '')),
          ],
        ),
      ),
    );
  }

  Widget _avisosWidget() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: Colors.blue.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Avisos do Painel', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._avisos.map((a) => Text(a['mensagem'] ?? '')),
          ],
        ),
      ),
    );
  }

  Widget _graficoCrescimento() {
    // Exemplo mock: crescimento por mês
    final meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    final valores = [10, 12, 15, 18, 22, 25, 30, 35, 40, 45, 50, 60];
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < meses.length; i++) FlSpot(i.toDouble(), valores[i].toDouble()),
            ],
            isCurved: true,
            color: Colors.blue,
            barWidth: 4,
            dotData: FlDotData(show: false),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) => Text(meses[v.toInt() % 12]),
            ),
          ),
        ),
      ),
    );
  }
}


class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const _MetricCard({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200, width: 1)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF0D47A1).withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: const Color(0xFF0D47A1), size: 28),
            ),
            const SizedBox(height: 14),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(value.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1))),
          ],
        ),
      ),
    );
  }
}

class _MetricCardMoney extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  const _MetricCardMoney({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200, width: 1)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF2E7D32).withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: const Color(0xFF2E7D32), size: 28),
            ),
            const SizedBox(height: 14),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text('R\$ ${value.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32))),
          ],
        ),
      ),
    );
  }
}

class _AtalhoCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _AtalhoCard({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF0D47A1), size: 30),
              const SizedBox(height: 10),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A1A))),
            ],
          ),
        ),
      ),
    );
  }
}
