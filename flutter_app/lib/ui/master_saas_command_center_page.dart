import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/core/saas_plan_limits.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

/// Torre de comando SaaS — clientes (igrejas), licenças, white-label e visão de negócio.
class MasterSaasCommandCenterPage extends StatefulWidget {
  const MasterSaasCommandCenterPage({super.key});

  @override
  State<MasterSaasCommandCenterPage> createState() =>
      _MasterSaasCommandCenterPageState();
}

class _MasterSaasCommandCenterPageState extends State<MasterSaasCommandCenterPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _searchCtrl = TextEditingController();
  static const String _all = '__all__';
  String _filterUf = _all;
  String _filterCidade = '';
  String _filterSaasTier = _all;
  final Map<String, int> _memberCountCache = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _saasIconChip(
    Color accent,
    IconData icon, {
    double dim = 34,
    double iconSz = 18,
  }) {
    return Container(
      width: dim,
      height: dim,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Colors.white, accent, 0.2)!.withValues(alpha: 0.95),
            Color.lerp(accent, YahwehDesignSystem.chipIconGradientEnd, 0.4)!
                .withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(YahwehDesignSystem.radiusSm),
        border: Border.all(
          color: Color.lerp(accent, Colors.white, 0.32)!.withValues(alpha: 0.52),
        ),
        boxShadow: [
          ...YahwehDesignSystem.softCardShadow,
          BoxShadow(
            color: accent.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSz),
    );
  }

  Future<void> _audit(String action, String details) async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('auditoria').add({
        'acao': action,
        'resource': 'master_saas_command',
        'details': details,
        'usuario': u?.email ?? u?.uid ?? 'master',
        'uid': u?.uid,
        'data': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  String _ufOf(Map<String, dynamic> m) =>
      (m['estado'] ?? m['uf'] ?? m['ESTADO'] ?? '').toString().trim();

  String _cidadeOf(Map<String, dynamic> m) =>
      (m['cidade'] ?? m['municipio'] ?? m['city'] ?? '').toString().trim();

  bool _passesClientFilters(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String q,
  ) {
    final data = doc.data();
    if (_filterUf != _all && _ufOf(data).toLowerCase() != _filterUf.toLowerCase()) {
      return false;
    }
    if (_filterCidade.isNotEmpty) {
      final c = _cidadeOf(data).toLowerCase();
      if (!c.contains(_filterCidade.toLowerCase())) return false;
    }
    if (_filterSaasTier != _all) {
      final t = SaasPlanLimits.tierFromChurch(data) ?? '';
      if (t != _filterSaasTier) return false;
    }
    if (q.isNotEmpty) {
      final nome = '${data['nome'] ?? data['name'] ?? ''}'.toLowerCase();
      final slug = '${data['slug'] ?? ''}'.toLowerCase();
      if (!nome.contains(q) && !slug.contains(q) && !doc.id.toLowerCase().contains(q)) {
        return false;
      }
    }
    return true;
  }

  Color _licenseColor(SubscriptionGuardState g) {
    if (g.adminBlocked || g.blocked) return const Color(0xFFDC2626);
    if (g.inGrace || g.statusAssinatura == 'overdue') return const Color(0xFFD97706);
    return const Color(0xFF16A34A);
  }

  Future<int> _loadMemberCount(String tenantId) async {
    if (_memberCountCache.containsKey(tenantId)) {
      return _memberCountCache[tenantId]!;
    }
    try {
      final agg = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('membros')
          .count()
          .get();
      final n = agg.count ?? 0;
      _memberCountCache[tenantId] = n;
      return n;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openWhiteLabelSheet(String tenantId, Map<String, dynamic> data) async {
    final saas = data['saas'] is Map ? Map<String, dynamic>.from(data['saas'] as Map) : <String, dynamic>{};
    final domainsCtrl = TextEditingController(
      text: (saas['authorizedDomains'] is List)
          ? (saas['authorizedDomains'] as List).map((e) => e.toString()).join(', ')
          : (saas['authorizedDomains'] ?? '').toString(),
    );
    final notesCtrl = TextEditingController(text: (saas['integrationNotes'] ?? '').toString());
    final mapsKeyCtrl = TextEditingController(text: (saas['mapsApiKey'] ?? '').toString());
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('White-label & integrações — $tenantId',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(
                controller: domainsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Domínios autorizados (vírgula)',
                  hintText: 'app.igreja.org, www.igreja.org',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mapsKeyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Chave Maps / APIs (uso interno — Firestore restrito ao master)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notas (Firebase próprio, bundle iOS, etc.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      final list = domainsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await FirebaseFirestore.instance.collection('igrejas').doc(tenantId).set({
        'saas': {
          'authorizedDomains': list,
          'integrationNotes': notesCtrl.text.trim(),
          'mapsApiKey': mapsKeyCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      await _audit('saas_white_label_update', 'tenant=$tenantId domains=${list.length}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Configurações SaaS salvas.'),
        );
      }
    }
    domainsCtrl.dispose();
    notesCtrl.dispose();
    mapsKeyCtrl.dispose();
  }

  Future<void> _setSaasTier(String tenantId, String tier) async {
    await FirebaseFirestore.instance.collection('igrejas').doc(tenantId).set({
      'saasTier': tier,
      'saas': {'tier': tier, 'updatedAt': FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
    await _audit('saas_tier_change', 'tenant=$tenantId tier=$tier');
    if (mounted) setState(() {});
  }

  Future<void> _supportAccessFlow(String tenantId, Map<String, dynamic> data) async {
    final email = (data['gestorEmail'] ?? data['email'] ?? data['gestor_email'] ?? '').toString().trim();
    await _audit('master_support_access_intent', 'tenant=$tenantId gestorEmail=$email');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suporte à igreja'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Não há login automático seguro sem Cloud Function dedicada. Use uma destas opções:',
                style: TextStyle(height: 1.35),
              ),
              const SizedBox(height: 12),
              Text('Tenant: $tenantId', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText('Gestor: $email'),
              ],
              const SizedBox(height: 12),
              const Text(
                '1) Entre com usuário de gestor da igreja.\n'
                '2) Ou use o Firebase Console / função de impersonação quando disponível.',
                style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          if (email.isNotEmpty)
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: email));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('E-mail do gestor copiado.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar e-mail'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      primary: false,
      appBar: isMobile
          ? null
          : AppBar(
              title: const Text('Torre de comando SaaS'),
              bottom: TabBar(
                controller: _tab,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _saasIconChip(
                          ChurchShellAccentTokens.masterSaasClientes,
                          Icons.apartment_rounded,
                        ),
                        const SizedBox(width: 8),
                        const Text('Clientes'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _saasIconChip(
                          ChurchShellAccentTokens.masterSaasNegocio,
                          Icons.trending_up_rounded,
                        ),
                        const SizedBox(width: 8),
                        const Text('Negócio'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Material(
                color: ThemeCleanPremium.primary,
                child: TabBar(
                  controller: _tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: ThemeCleanPremium.navSidebarAccent,
                  tabs: [
                    Tab(
                      icon: _saasIconChip(
                        ChurchShellAccentTokens.masterSaasClientes,
                        Icons.apartment_rounded,
                        dim: 30,
                        iconSz: 16,
                      ),
                      text: 'Clientes',
                    ),
                    Tab(
                      icon: _saasIconChip(
                        ChurchShellAccentTokens.masterSaasNegocio,
                        Icons.trending_up_rounded,
                        dim: 30,
                        iconSz: 16,
                      ),
                      text: 'Negócio',
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _buildClientsTab(),
                  _buildBusinessTab(brl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientsTab() {
    return Column(
      children: [
        Padding(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar nome ou ID…',
                  prefixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: _saasIconChip(
                        ThemeCleanPremium.primary,
                        Icons.search_rounded,
                        dim: 36,
                        iconSz: 18,
                      ),
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 100,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'UF',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      value: _filterUf,
                      items: [
                        const DropdownMenuItem(value: _all, child: Text('Todas')),
                        ...['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO']
                            .map((u) => DropdownMenuItem(value: u, child: Text(u))),
                      ],
                      onChanged: (v) => setState(() => _filterUf = v ?? _all),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Cidade contém',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _filterCidade = v),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Plano SaaS',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      value: _filterSaasTier,
                      items: [
                        const DropdownMenuItem(value: _all, child: Text('Todos')),
                        const DropdownMenuItem(value: SaasPlanLimits.kBronze, child: Text('Bronze')),
                        const DropdownMenuItem(value: SaasPlanLimits.kPrata, child: Text('Prata')),
                        const DropdownMenuItem(value: SaasPlanLimits.kOuro, child: Text('Ouro')),
                      ],
                      onChanged: (v) => setState(() => _filterSaasTier = v ?? _all),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('igrejas').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final q = _searchCtrl.text.trim().toLowerCase();
              final docs = snap.data!.docs.where((d) => _passesClientFilters(d, q)).toList()
                ..sort((a, b) {
                  final na = '${a.data()['nome'] ?? a.data()['name'] ?? a.id}'.toLowerCase();
                  final nb = '${b.data()['nome'] ?? b.data()['name'] ?? b.id}'.toLowerCase();
                  return na.compareTo(nb);
                });
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  ThemeCleanPremium.pagePadding(context).left,
                  0,
                  ThemeCleanPremium.pagePadding(context).right,
                  24,
                ),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final doc = docs[i];
                  final data = doc.data();
                  final guard = SubscriptionGuard.evaluate(church: data);
                  final tier = SaasPlanLimits.tierFromChurch(data);
                  final cap = SaasPlanLimits.memberCapForTier(tier);
                  final nome = (data['nome'] ?? data['name'] ?? doc.id).toString();
                  final cidade = _cidadeOf(data);
                  final uf = _ufOf(data);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ExpansionTile(
                      leading: _saasIconChip(
                        _licenseColor(guard),
                        Icons.church_rounded,
                        dim: 40,
                        iconSz: 20,
                      ),
                      title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'ID: ${doc.id}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey.shade800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copiar ID da igreja',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.copy_rounded,
                                    size: 18, color: Colors.grey.shade600),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: doc.id));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ThemeCleanPremium.successSnackBar(
                                        'ID copiado. Notícias, eventos e escalas usam este vínculo.'),
                                  );
                                },
                              ),
                            ],
                          ),
                          Text(
                            [cidade, uf].where((s) => s.isNotEmpty).join(' · ') +
                                ' · ${guard.masterBadgeLabel} · ${SaasPlanLimits.labelForTier(tier)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: FutureBuilder<int>(
                            future: _loadMemberCount(doc.id),
                            builder: (context, countSnap) {
                              final n = countSnap.data ?? 0;
                              final pct = cap == null || cap <= 0 ? 0.0 : (n / cap).clamp(0.0, 1.0);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Membros: $n${cap != null ? ' / $cap' : ' (sem teto SaaS)'}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (cap != null) ...[
                                    const SizedBox(height: 6),
                                    LinearPercentIndicator(
                                      lineHeight: 10,
                                      percent: pct,
                                      progressColor: pct >= 0.95
                                          ? Colors.orange.shade700
                                          : ThemeCleanPremium.primary,
                                      backgroundColor: Colors.grey.shade200,
                                      barRadius: const Radius.circular(8),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _MasterMicroButton(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _openWhiteLabelSheet(doc.id, data),
                                            icon: const Icon(Icons.language_rounded,
                                                size: 18),
                                            label: const Text('Domínios / API'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _MasterMicroButton(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _supportAccessFlow(doc.id, data),
                                            icon: const Icon(
                                                Icons.support_agent_rounded,
                                                size: 18),
                                            label: const Text('Suporte'),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                      labelText: 'Plano SaaS',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    value: (tier != null &&
                                            [SaasPlanLimits.kBronze, SaasPlanLimits.kPrata, SaasPlanLimits.kOuro]
                                                .contains(tier))
                                        ? tier
                                        : SaasPlanLimits.kOuro,
                                    items: const [
                                      DropdownMenuItem(
                                        value: SaasPlanLimits.kBronze,
                                        child: Text('Bronze'),
                                      ),
                                      DropdownMenuItem(
                                        value: SaasPlanLimits.kPrata,
                                        child: Text('Prata'),
                                      ),
                                      DropdownMenuItem(
                                        value: SaasPlanLimits.kOuro,
                                        child: Text('Ouro'),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) _setSaasTier(doc.id, v);
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessTab(NumberFormat brl) {
    return FutureBuilder<_MasterBizSnapshot>(
      future: _loadBizSnapshot(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Erro: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final m = snap.data!;
        return ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            Text(
              'Visão de negócio',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'MRR aqui é aproximado pela média dos últimos 30 dias de vendas confirmadas. Ajuste no seu BI quando integrar assinaturas.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
            ),
            const SizedBox(height: 20),
            _metricCard(
              'Receita confirmada (30 dias)',
              brl.format(m.revenue30d),
              Icons.payments_rounded,
              kChurchShellNavEntries[20].accent,
            ),
            _metricCard(
              'MRR estimado',
              brl.format(m.mrrEstimate),
              Icons.repeat_rounded,
              ThemeCleanPremium.primary,
            ),
            _metricCard(
              'Churn (90 dias) — assinaturas inativas/canceladas',
              '${m.churn90}',
              Icons.trending_down_rounded,
              YahwehDesignSystem.error,
            ),
            _metricCard(
              'Igrejas na base',
              '${m.totalChurches}',
              Icons.church_rounded,
              kChurchShellNavEntries[19].accent,
            ),
            _metricCard(
              'Membros (soma nas igrejas consultadas)',
              '${m.totalMembersSample}',
              Icons.people_rounded,
              kChurchShellNavEntries[2].accent,
            ),
            if (m.monthlyBars.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Receita por mês (vendas aprovadas)',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
              const SizedBox(height: 12),
              ...m.monthlyBars.map((e) {
                final maxV = m.maxMonthly > 0 ? m.maxMonthly : 1.0;
                final p = (e.value / maxV).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 72, child: Text(e.key, style: const TextStyle(fontSize: 12))),
                      Expanded(
                        child: LinearPercentIndicator(
                          lineHeight: 14,
                          percent: p,
                          center: Text(
                            brl.format(e.value),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                          progressColor: ThemeCleanPremium.primary,
                          backgroundColor: Colors.grey.shade200,
                          barRadius: const Radius.circular(8),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 24),
            ListTile(
              leading: _saasIconChip(
                kChurchShellNavEntries[17].accent,
                Icons.campaign_rounded,
                dim: 40,
                iconSz: 20,
              ),
              title: const Text('Aviso global / manutenção'),
              subtitle: const Text(
                'Use no menu lateral: Sistema → Aviso global / Manutenção (banner em todas as igrejas).',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _MasterPremiumMetricCard(
        title: title,
        value: value,
        icon: icon,
        color: c,
      ),
    );
  }

  Future<_MasterBizSnapshot> _loadBizSnapshot() async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final start30 = now.subtract(const Duration(days: 30));
    final start90 = now.subtract(const Duration(days: 90));

    double revenue30d = 0;
    final byMonth = <String, double>{};
    int churn90 = 0;
    int totalChurches = 0;
    int membersSum = 0;

    bool countableSale(Map<String, dynamic> d) {
      final s = (d['status'] ?? '').toString().toLowerCase();
      return s == 'approved' || s == 'paid' || s == 'accredited';
    }

    DateTime? parseDyn(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse(v?.toString() ?? '');
    }

    try {
      final churches = await db.collection('igrejas').get();
      totalChurches = churches.docs.length;
      for (final d in churches.docs.take(60)) {
        try {
          final c = await db.collection('igrejas').doc(d.id).collection('membros').count().get();
          membersSum += c.count ?? 0;
        } catch (_) {}
      }
    } catch (_) {}

    try {
      final sales = await db.collection('sales').get();
      for (final d in sales.docs) {
        if (!countableSale(d.data())) continue;
        final dt = parseDyn(d.data()['paidAt'] ?? d.data()['createdAt'] ?? d.data()['date']);
        if (dt == null) continue;
        final amtRaw = d.data()['amount'] ?? d.data()['transaction_amount'] ?? 0;
        final val = amtRaw is num ? amtRaw.toDouble() : double.tryParse(amtRaw.toString()) ?? 0;
        if (dt.isAfter(start30)) revenue30d += val;
        if (dt.isAfter(now.subtract(const Duration(days: 180)))) {
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          byMonth[key] = (byMonth[key] ?? 0) + val;
        }
      }
    } catch (_) {}

    try {
      final subs = await db.collection('subscriptions').get();
      final bad = {'cancelled', 'canceled', 'inactive', 'expired'};
      for (final d in subs.docs) {
        final st = (d.data()['status'] ?? '').toString().toLowerCase();
        if (!bad.contains(st)) continue;
        final u = parseDyn(
          d.data()['cancelledAt'] ??
              d.data()['canceledAt'] ??
              d.data()['updatedAt'] ??
              d.data()['currentPeriodEnd'],
        );
        if (u != null && u.isAfter(start90)) churn90++;
      }
    } catch (_) {}

    final last6 = <MapEntry<String, double>>[];
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      last6.add(MapEntry(k, byMonth[k] ?? 0));
    }
    final maxM = last6.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);

    return _MasterBizSnapshot(
      revenue30d: revenue30d,
      mrrEstimate: revenue30d,
      churn90: churn90,
      totalChurches: totalChurches,
      totalMembersSample: membersSum,
      monthlyBars: last6,
      maxMonthly: maxM,
    );
  }
}

class _MasterBizSnapshot {
  final double revenue30d;
  final double mrrEstimate;
  final int churn90;
  final int totalChurches;
  final int totalMembersSample;
  final List<MapEntry<String, double>> monthlyBars;
  final double maxMonthly;

  _MasterBizSnapshot({
    required this.revenue30d,
    required this.mrrEstimate,
    required this.churn90,
    required this.totalChurches,
    required this.totalMembersSample,
    required this.monthlyBars,
    required this.maxMonthly,
  });
}

class _MasterMicroButton extends StatefulWidget {
  final Widget child;
  const _MasterMicroButton({required this.child});

  @override
  State<_MasterMicroButton> createState() => _MasterMicroButtonState();
}

class _MasterMicroButtonState extends State<_MasterMicroButton> {
  bool _hover = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    final scale = _press ? 0.985 : (_hover ? 1.01 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _press = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => setState(() => _press = true),
        onTapUp: (_) => setState(() => _press = false),
        onTapCancel: () => setState(() => _press = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          child: AnimatedOpacity(
            opacity: _press ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _MasterPremiumMetricCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MasterPremiumMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  State<_MasterPremiumMetricCard> createState() =>
      _MasterPremiumMetricCardState();
}

class _MasterPremiumMetricCardState extends State<_MasterPremiumMetricCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(YahwehDesignSystem.radiusMd),
          border: Border.all(
            color: _hover
                ? widget.color.withValues(alpha: 0.32)
                : const Color(0xFFE2E8F0),
            width: _hover ? 1.6 : 1.0,
          ),
          boxShadow: [
            ...ThemeCleanPremium.softUiCardShadow,
            if (_hover)
              BoxShadow(
                color: widget.color.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(Colors.white, widget.color, 0.2)!
                        .withValues(alpha: 0.95),
                    Color.lerp(
                            widget.color, YahwehDesignSystem.chipIconGradientEnd, 0.4)!
                        .withValues(alpha: 0.9),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(YahwehDesignSystem.radiusMd - 2),
                border: Border.all(
                  color: Color.lerp(widget.color, Colors.white, 0.32)!
                      .withValues(alpha: 0.52),
                ),
                boxShadow: [
                  ...YahwehDesignSystem.softCardShadow,
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
