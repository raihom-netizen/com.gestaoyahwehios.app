import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'busca_global_widget.dart';
import 'grafico_ultra_moderno.dart';
import 'igreja_menu_lateral_dinamico.dart';
import 'pages/members_page.dart';
import 'pages/departments_page.dart';
import 'pages/events_manager_page.dart';
import 'pages/mural_page.dart';
import 'pages/finance_page.dart';
import 'pages/usuarios_permissoes_page.dart';
import 'pages/aprovar_membros_pendentes_page.dart';

/// Painel alternativo com menu lateral (não é o shell principal [`IgrejaCleanShell`];
/// mantido para testes / rotas futuras). Dados em `igrejas/{tenantId}/`.
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

  static String _nomeMembro(Map<String, dynamic> m) =>
      (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '').toString().trim();

  static String _sexoMembro(Map<String, dynamic> m) =>
      (m['sexo'] ?? m['SEXO'] ?? '').toString().trim().toUpperCase();

  static int? _idadeMembro(Map<String, dynamic> m) {
    final raw = m['idade'] ?? m['IDADE'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static DateTime? _nascimentoMembro(Map<String, dynamic> m) {
    final raw = m['dataNascimento'] ?? m['DATA_NASCIMENTO'];
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  static bool _isLider(Map<String, dynamic> m) {
    final l = m['lider'] ?? m['LIDER'] ?? m['ehLider'];
    if (l is bool) return l;
    final s = l?.toString().toLowerCase() ?? '';
    return s == 'true' || s == '1' || s == 'sim';
  }

  static double _financeEntrada(Map<String, dynamic> m) {
    final tipo = (m['type'] ?? m['tipo'] ?? 'entrada').toString().toLowerCase();
    final valorRaw = m['amount'] ?? m['valor'] ?? 0;
    final valor = valorRaw is num ? valorRaw.toDouble() : double.tryParse(valorRaw.toString()) ?? 0;
    if (tipo.contains('entrada') || tipo == 'receita' || tipo.contains('oferta')) return valor;
    return 0;
  }

  static double _financeSaida(Map<String, dynamic> m) {
    final tipo = (m['type'] ?? m['tipo'] ?? '').toString().toLowerCase();
    if (tipo == 'transferencia') return 0;
    final valorRaw = m['amount'] ?? m['valor'] ?? 0;
    final valor = valorRaw is num ? valorRaw.toDouble() : double.tryParse(valorRaw.toString()) ?? 0;
    if (tipo.contains('entrada') || tipo == 'receita' || tipo.contains('oferta')) return 0;
    return valor;
  }

  Future<void> _abrirModulo(int index) async {
    if (index == 0) return; // Painel = fica na própria tela
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String? tenantId;
    String role = 'user';
    try {
      final token = await user.getIdTokenResult(true);
      tenantId = (token.claims?['igrejaId'] ?? token.claims?['tenantId'] ?? '').toString().trim();
      role = (token.claims?['role'] ?? 'user').toString().toLowerCase();
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
    String? tenantId;
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        final t = await u.getIdTokenResult(true);
        tenantId = (t.claims?['igrejaId'] ?? t.claims?['tenantId'] ?? '').toString().trim();
      }
    } catch (_) {}

    if (tenantId == null || tenantId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final base = FirebaseFirestore.instance.collection('igrejas').doc(tenantId);
    try {
      final snaps = await Future.wait([
        base.collection('membros').get(),
        base.collection('departamentos').get(),
        base.collection('finance').limit(500).get(),
      ]);

      final membrosSnap = snaps[0];
      final depsSnap = snaps[1];
      final financeSnap = snaps[2];

      QuerySnapshot<Map<String, dynamic>> avisosSnap;
      try {
        avisosSnap = await base
            .collection(ChurchTenantPostsCollections.avisos)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get();
      } catch (_) {
        avisosSnap = await base.collection(ChurchTenantPostsCollections.avisos).limit(5).get();
      }

      final hoje = DateTime.now();
      _membros = membrosSnap.size;
      _homens = membrosSnap.docs.where((d) => _sexoMembro(d.data()) == 'M').length;
      _mulheres = membrosSnap.docs.where((d) => _sexoMembro(d.data()) == 'F').length;
      _criancas = membrosSnap.docs.where((d) {
        final id = _idadeMembro(d.data());
        if (id != null) return id < 13;
        return false;
      }).length;
      _departamentos = depsSnap.size;
      _totalOfertas = financeSnap.docs.fold(0.0, (a, b) => a + _financeEntrada(b.data()));
      _totalDespesas = financeSnap.docs.fold(0.0, (a, b) => a + _financeSaida(b.data()));
      _aniversariantes = membrosSnap.docs.where((d) {
        final dt = _nascimentoMembro(d.data());
        if (dt == null) return false;
        return dt.month == hoje.month && dt.day == hoje.day;
      }).map((d) => d.data()).toList();
      _lideres = membrosSnap.docs.where((d) => _isLider(d.data())).map((d) => d.data()).toList();
      _avisos = avisosSnap.docs.map((d) => d.data()).toList();
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
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
                                const Text('Painel da Igreja', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26, color: Color(0xFF0D47A1), letterSpacing: -0.5)),
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
                                _MetricCardMoney(label: r'Ofertas / entradas (R$)', value: _totalOfertas, icon: Icons.attach_money),
                                _MetricCardMoney(label: r'Despesas / saídas (R$)', value: _totalDespesas, icon: Icons.money_off),
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
                  backgroundColor: const Color(0xFF1565C0),
                  child: Icon(_menuCollapsed ? Icons.menu : Icons.close),
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
      shadowColor: Colors.blue.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aniversariantes de hoje', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._aniversariantes.map((m) => Text(_nomeMembro(m))),
          ],
        ),
      ),
    );
  }

  Widget _lideresWidget() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: Colors.blue.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Destaque de Líderes', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._lideres.take(5).map((m) => Text(_nomeMembro(m))),
          ],
        ),
      ),
    );
  }

  Widget _avisosWidget() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: Colors.blue.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Avisos do Painel', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._avisos.map((a) => Text((a['mensagem'] ?? a['titulo'] ?? a['body'] ?? '').toString())),
          ],
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
              decoration: BoxDecoration(color: const Color(0xFF0D47A1).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
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
              decoration: BoxDecoration(color: const Color(0xFF0D47A1).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: const Color(0xFF0D47A1), size: 28),
            ),
            const SizedBox(height: 14),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1))),
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
          width: 200,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF0D47A1)),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}
