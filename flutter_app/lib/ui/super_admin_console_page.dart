import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// ✅ Painel Master (Super Admin)
/// - Lista todas as igrejas (collection: tenants)
/// - Permite marcar plano Free / ativa-desativa licença
///
/// Observação: esse painel não depende de custom claims; ele valida
/// o usuário logado pelo e-mail/CPF (você) e então libera as ações.
class SuperAdminConsolePage extends StatefulWidget {
  const SuperAdminConsolePage({super.key});

  @override
  State<SuperAdminConsolePage> createState() => _SuperAdminConsolePageState();
}

class _SuperAdminConsolePageState extends State<SuperAdminConsolePage> {
  final _qCtrl = TextEditingController();
  int _tab = 0;

  bool get _isSuper {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';
    // ✅ seu e-mail master
    return email == 'raihom@gmail.com';
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _setFree(
      DocumentReference<Map<String, dynamic>> ref, bool free) async {
    await ref.set(
      {
        'license': {
          'isFree': free,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _setActive(
      DocumentReference<Map<String, dynamic>> ref, bool active) async {
    await ref.set(
      {
        'license': {
          'active': active,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      },
      SetOptions(merge: true),
    );
  }

  CollectionReference<Map<String, dynamic>> get _plans =>
      FirebaseFirestore.instance
          .collection('config')
          .doc('plans')
          .collection('items');

  DocumentReference<Map<String, dynamic>> get _memberCardCfg =>
      FirebaseFirestore.instance.doc('config/memberCard');

  Future<void> _editMemberCardConfig(Map<String, dynamic> data) async {
    final titleCtrl = TextEditingController(
        text: (data['title'] ?? 'Gestao YAHWEH').toString());
    final subtitleCtrl = TextEditingController(
        text: (data['subtitle'] ?? 'Carteira digital da igreja').toString());
    final logoCtrl =
        TextEditingController(text: (data['logoUrl'] ?? '').toString());
    final bgCtrl =
        TextEditingController(text: (data['bgColor'] ?? '#0B2F6B').toString());
    final textCtrl = TextEditingController(
        text: (data['textColor'] ?? '#FFFFFF').toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Carteirinha digital (config global)'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Titulo'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subtitleCtrl,
                  decoration: const InputDecoration(labelText: 'Subtitulo'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: logoCtrl,
                  decoration: const InputDecoration(labelText: 'Logo URL'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bgCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Cor de fundo (hex)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: textCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Cor do texto (hex)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await _memberCardCfg.set(
                {
                  'title': titleCtrl.text.trim(),
                  'subtitle': subtitleCtrl.text.trim(),
                  'logoUrl': logoCtrl.text.trim(),
                  'bgColor': bgCtrl.text.trim(),
                  'textColor': textCtrl.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _seedDefaultPlans() async {
    final batch = FirebaseFirestore.instance.batch();

    void up(String id, Map<String, dynamic> data) {
      batch.set(_plans.doc(id), data, SetOptions(merge: true));
    }

    // ✅ Valores e limites base (podem ser editados no painel)
    up('inicial', {
      'name': 'Plano Inicial',
      'priceMonthly': 49.90,
      'membersMax': 100,
      'limits': {'admins': 2, 'leaders': 10, 'members': 100},
      'order': 1,
    });
    up('essencial', {
      'name': 'Plano Essencial',
      'priceMonthly': 59.90,
      'membersMax': 150,
      'limits': {'admins': 3, 'leaders': 15, 'members': 150},
      'order': 2,
    });
    up('intermediario', {
      'name': 'Plano Intermediario',
      'priceMonthly': 69.90,
      'membersMax': 250,
      'limits': {'admins': 4, 'leaders': 25, 'members': 250},
      'order': 3,
    });
    up('avancado', {
      'name': 'Plano Avancado',
      'priceMonthly': 89.90,
      'membersMax': 350,
      'limits': {'admins': 5, 'leaders': 35, 'members': 350},
      'order': 4,
    });
    up('profissional', {
      'name': 'Plano Profissional',
      'priceMonthly': 99.90,
      'membersMax': 400,
      'limits': {'admins': 6, 'leaders': 40, 'members': 400},
      'order': 5,
    });
    up('premium', {
      'name': 'Plano Premium',
      'priceMonthly': 169.90,
      'membersMax': 500,
      'limits': {'admins': 8, 'leaders': 60, 'members': 500},
      'order': 6,
    });
    up('premium_plus', {
      'name': 'Plano Premium Plus',
      'priceMonthly': 189.90,
      'membersMax': 600,
      'limits': {'admins': 10, 'leaders': 80, 'members': 600},
      'order': 7,
    });
    up('corporativo', {
      'name': 'Plano Corporativo',
      'priceMonthly': 0,
      'membersMax': 999999,
      'limits': {'admins': 999, 'leaders': 999, 'members': 999999},
      'order': 8,
      'note': 'Sob consulta',
    });

    await batch.commit();
  }

  Future<void> _editTenant(DocumentSnapshot<Map<String, dynamic>> d) async {
    final data = d.data() ?? {};
    final id = d.id;
    final nameCtrl = TextEditingController(
        text: (data['name'] ?? data['nome'] ?? id).toString());
    final logoCtrl =
        TextEditingController(text: (data['logoUrl'] ?? '').toString());
    final planCtrl = TextEditingController(
        text: (data['planId'] ?? data['plan'] ?? 'inicial').toString());
    final limits = (data['limits'] is Map)
        ? Map<String, dynamic>.from(data['limits'])
        : <String, dynamic>{};
    final adminsCtrl =
        TextEditingController(text: (limits['admins'] ?? 2).toString());
    final leadersCtrl =
        TextEditingController(text: (limits['leaders'] ?? 10).toString());
    final membersCtrl =
        TextEditingController(text: (limits['members'] ?? 100).toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Editar igreja: $id'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nome da igreja')),
                TextField(
                    controller: logoCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Logo URL (opcional)')),
                TextField(
                    controller: planCtrl,
                    decoration: const InputDecoration(
                        labelText: 'PlanId (inicial/essencial/...)')),
                const SizedBox(height: 12),
                const Text('Limites (pode alterar por igreja)',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: adminsCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Admins'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: leadersCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Leaders'))),
                ]),
                const SizedBox(height: 10),
                TextField(
                    controller: membersCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Members')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await d.reference.set(
                {
                  'name': nameCtrl.text.trim(),
                  'logoUrl': logoCtrl.text.trim(),
                  'planId': planCtrl.text.trim(),
                  'limits': {
                    'admins': int.tryParse(adminsCtrl.text.trim()) ?? 2,
                    'leaders': int.tryParse(leadersCtrl.text.trim()) ?? 10,
                    'members': int.tryParse(membersCtrl.text.trim()) ?? 100,
                  },
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  String _money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String _formatDate(dynamic raw) {
    if (raw is Timestamp) {
      final dt = raw.toDate();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    return (raw ?? '').toString();
  }

  Timestamp? _parseDate(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    final dt = DateTime.tryParse(t);
    if (dt == null) return null;
    return Timestamp.fromDate(dt);
  }

  Future<void> _openLicenseDialog(
    DocumentSnapshot<Map<String, dynamic>> d,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> plans,
  ) async {
    final data = d.data() ?? {};
    final lic = (data['license'] is Map)
        ? Map<String, dynamic>.from(data['license'])
        : <String, dynamic>{};
    final billing = (data['billing'] is Map)
        ? Map<String, dynamic>.from(data['billing'])
        : <String, dynamic>{};

    String selectedPlan =
        (data['planId'] ?? data['plan'] ?? 'inicial').toString();
    String selectedStatus = (lic['status'] ?? 'trial').toString().toLowerCase();
    String selectedPay =
        (billing['status'] ?? 'pending').toString().toLowerCase();
    bool active = (lic['active'] ?? true) == true;
    bool isFree = (lic['isFree'] ?? false) == true;

    final providerCtrl = TextEditingController(
        text: (billing['provider'] ?? 'mercado_pago').toString());
    final subscriptionCtrl = TextEditingController(
        text: (billing['subscriptionId'] ?? '').toString());
    final nextChargeCtrl =
        TextEditingController(text: _formatDate(billing['nextChargeAt']));
    final lastPaidCtrl =
        TextEditingController(text: _formatDate(billing['lastPaymentAt']));
    final trialEndsCtrl =
        TextEditingController(text: _formatDate(lic['trialEndsAt']));

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Licenca e pagamentos: ${d.id}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedPlan,
                  decoration: const InputDecoration(labelText: 'Plano ativo'),
                  items: plans
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.data()['name'] ?? p.id} (${p.id})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => selectedPlan = v ?? selectedPlan,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration:
                      const InputDecoration(labelText: 'Status da licenca'),
                  items: const [
                    DropdownMenuItem(value: 'trial', child: Text('trial')),
                    DropdownMenuItem(value: 'active', child: Text('active')),
                    DropdownMenuItem(value: 'blocked', child: Text('blocked')),
                  ],
                  onChanged: (v) => selectedStatus = v ?? selectedStatus,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        value: active,
                        onChanged: (v) => active = v,
                        title: const Text('Ativo'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SwitchListTile(
                        value: isFree,
                        onChanged: (v) => isFree = v,
                        title: const Text('Plano Free'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: trialEndsCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Trial ate (YYYY-MM-DD)'),
                ),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: selectedPay,
                  decoration:
                      const InputDecoration(labelText: 'Status do pagamento'),
                  items: const [
                    DropdownMenuItem(value: 'paid', child: Text('paid')),
                    DropdownMenuItem(value: 'pending', child: Text('pending')),
                    DropdownMenuItem(value: 'overdue', child: Text('overdue')),
                    DropdownMenuItem(
                        value: 'canceled', child: Text('canceled')),
                  ],
                  onChanged: (v) => selectedPay = v ?? selectedPay,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: providerCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Provider (ex: mercado_pago)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subscriptionCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Subscription ID'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: lastPaidCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Ultimo pagamento (YYYY-MM-DD)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: nextChargeCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Proxima cobranca (YYYY-MM-DD)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final nextCharge = _parseDate(nextChargeCtrl.text);
              final lastPaid = _parseDate(lastPaidCtrl.text);
              final trialEnds = _parseDate(trialEndsCtrl.text);

              await d.reference.set(
                {
                  'planId': selectedPlan,
                  'license': {
                    'status': selectedStatus,
                    'active': active,
                    'isFree': isFree,
                    if (trialEnds != null) 'trialEndsAt': trialEnds,
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                  'billing': {
                    'status': selectedPay,
                    'provider': providerCtrl.text.trim(),
                    'subscriptionId': subscriptionCtrl.text.trim(),
                    if (lastPaid != null) 'lastPaymentAt': lastPaid,
                    if (nextCharge != null) 'nextChargeAt': nextCharge,
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );

              if (trialEnds != null) {
                final subQs = await FirebaseFirestore.instance
                    .collection('subscriptions')
                    .where('igrejaId', isEqualTo: d.id)
                    .orderBy('createdAt', descending: true)
                    .limit(1)
                    .get();
                final payload = {
                  'igrejaId': d.id,
                  'planId': selectedPlan,
                  'status': selectedStatus.toUpperCase(),
                  'trialEndsAt': trialEnds,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                if (subQs.docs.isEmpty) {
                  await FirebaseFirestore.instance
                      .collection('subscriptions')
                      .add({
                    ...payload,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  await subQs.docs.first.reference.set(
                    payload,
                    SetOptions(merge: true),
                  );
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Painel Master')),
        body: const Center(child: Text('Faça login para acessar o painel.')),
      );
    }

    if (!_isSuper) {
      return Scaffold(
        appBar: AppBar(title: const Text('Painel Master')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Acesso negado. Este painel é exclusivo do SUPER ADMIN.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Painel Master (Licenças e Igrejas)'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
            child: const Text('Home'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SalesSummary(plans: _plans),
                const SizedBox(height: 12),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _memberCardCfg.snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data() ?? {};
                    final title = (data['title'] ?? 'Gestao YAHWEH').toString();
                    final subtitle =
                        (data['subtitle'] ?? 'Carteira digital da igreja')
                            .toString();
                    final logoUrl =
                        sanitizeImageUrl((data['logoUrl'] ?? '').toString());
                    return Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            if (logoUrl.isNotEmpty && isValidImageUrl(logoUrl))
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: SafeNetworkImage(
                                    imageUrl: logoUrl,
                                    fit: BoxFit.cover,
                                    width: 46,
                                    height: 46,
                                    errorWidget: Icon(Icons.business_rounded,
                                        color: Colors.grey.shade600, size: 28),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Carteirinha digital',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Titulo: $title'),
                                  Text('Subtitulo: $subtitle'),
                                ],
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: () => _editMemberCardConfig(data),
                              child: const Text('Editar'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Igrejas')),
                          ButtonSegment(value: 1, label: Text('Planos')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (s) =>
                            setState(() => _tab = s.first),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_tab == 1)
                      FilledButton.icon(
                        onPressed: _seedDefaultPlans,
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Criar/Atualizar planos'),
                      ),
                  ],
                ),
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qCtrl,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Buscar tenantId / nome…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Atualizar'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _tab == 1
                      ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _plans.orderBy('order').snapshots(),
                          builder: (context, snap) {
                            if (snap.hasError)
                              return Center(child: Text('Erro: ${snap.error}'));
                            if (!snap.hasData)
                              return const Center(
                                  child: CircularProgressIndicator());
                            final docs = snap.data!.docs;
                            if (docs.isEmpty) {
                              return const Center(
                                  child: Text(
                                      'Nenhum plano em config/plans/items. Clique em "Criar/Atualizar planos".'));
                            }

                            return ListView.separated(
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final d = docs[i];
                                final data = d.data();
                                final name = (data['name'] ?? d.id).toString();
                                final price =
                                    (data['priceMonthly'] ?? 0).toString();
                                final limits = (data['limits'] is Map)
                                    ? Map<String, dynamic>.from(data['limits'])
                                    : {};

                                return Card(
                                  elevation: 6,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18)),
                                  child: ListTile(
                                    title: Text(name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900)),
                                    subtitle: Text(
                                        'id: ${d.id}  •  preco: R\$ $price  •  admins: ${limits['admins']}  •  leaders: ${limits['leaders']}  •  members: ${limits['members']}'),
                                    trailing: FilledButton.tonal(
                                      onPressed: () async {
                                        final priceCtrl = TextEditingController(
                                            text: (data['priceMonthly'] ?? 0)
                                                .toString());
                                        final aCtrl = TextEditingController(
                                            text: (limits['admins'] ?? 2)
                                                .toString());
                                        final lCtrl = TextEditingController(
                                            text: (limits['leaders'] ?? 10)
                                                .toString());
                                        final mCtrl = TextEditingController(
                                            text: (limits['members'] ?? 100)
                                                .toString());
                                        await showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title:
                                                Text('Editar plano: ${d.id}'),
                                            content: SizedBox(
                                              width: 520,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextField(
                                                      controller: priceCtrl,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      decoration:
                                                          const InputDecoration(
                                                              labelText:
                                                                  'Preco mensal (ex: 69.90)')),
                                                  const SizedBox(height: 10),
                                                  Row(children: [
                                                    Expanded(
                                                        child: TextField(
                                                            controller: aCtrl,
                                                            keyboardType:
                                                                TextInputType
                                                                    .number,
                                                            decoration:
                                                                const InputDecoration(
                                                                    labelText:
                                                                        'Admins'))),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                        child: TextField(
                                                            controller: lCtrl,
                                                            keyboardType:
                                                                TextInputType
                                                                    .number,
                                                            decoration:
                                                                const InputDecoration(
                                                                    labelText:
                                                                        'Leaders'))),
                                                  ]),
                                                  const SizedBox(height: 10),
                                                  TextField(
                                                      controller: mCtrl,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      decoration:
                                                          const InputDecoration(
                                                              labelText:
                                                                  'Members')),
                                                ],
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child:
                                                      const Text('Cancelar')),
                                              FilledButton(
                                                onPressed: () async {
                                                  await d.reference.set(
                                                    {
                                                      'priceMonthly': double
                                                              .tryParse(priceCtrl
                                                                  .text
                                                                  .trim()
                                                                  .replaceAll(
                                                                      ',',
                                                                      '.')) ??
                                                          0,
                                                      'limits': {
                                                        'admins': int.tryParse(
                                                                aCtrl.text
                                                                    .trim()) ??
                                                            2,
                                                        'leaders': int.tryParse(
                                                                lCtrl.text
                                                                    .trim()) ??
                                                            10,
                                                        'members': int.tryParse(
                                                                mCtrl.text
                                                                    .trim()) ??
                                                            100,
                                                      },
                                                      'updatedAt': FieldValue
                                                          .serverTimestamp(),
                                                    },
                                                    SetOptions(merge: true),
                                                  );
                                                  if (mounted)
                                                    Navigator.pop(context);
                                                },
                                                child: const Text('Salvar'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: const Text('Editar'),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        )
                      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _plans.orderBy('order').snapshots(),
                          builder: (context, plansSnap) {
                            if (plansSnap.hasError)
                              return Center(
                                  child: Text('Erro: ${plansSnap.error}'));
                            if (!plansSnap.hasData)
                              return const Center(
                                  child: CircularProgressIndicator());
                            final plans = plansSnap.data!.docs;

                            return StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('igrejas')
                                  .snapshots(),
                              builder: (context, snap) {
                                if (snap.hasError) {
                                  return Center(
                                      child: Text('Erro: ${snap.error}'));
                                }
                                if (!snap.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }

                                final q = _qCtrl.text.trim().toLowerCase();
                                final docs = snap.data!.docs.where((d) {
                                  if (q.isEmpty) return true;
                                  final id = d.id.toLowerCase();
                                  final name = (d.data()['name'] ??
                                          d.data()['nome'] ??
                                          '')
                                      .toString()
                                      .toLowerCase();
                                  return id.contains(q) || name.contains(q);
                                }).toList();

                                if (docs.isEmpty) {
                                  return const Center(
                                      child: Text(
                                          'Nenhuma igreja encontrada em tenants.'));
                                }

                                String planName(String id) {
                                  for (final p in plans) {
                                    if (p.id == id)
                                      return (p.data()['name'] ?? p.id)
                                          .toString();
                                  }
                                  return id;
                                }

                                return ListView.separated(
                                  itemCount: docs.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final d = docs[i];
                                    final data = d.data();
                                    final id = d.id;
                                    final name =
                                        (data['name'] ?? data['nome'] ?? id)
                                            .toString();
                                    final slug =
                                        (data['slug'] ?? data['alias'] ?? id)
                                            .toString()
                                            .trim();
                                    final lic = (data['license'] is Map)
                                        ? Map<String, dynamic>.from(
                                            data['license'])
                                        : <String, dynamic>{};
                                    final billing = (data['billing'] is Map)
                                        ? Map<String, dynamic>.from(
                                            data['billing'])
                                        : <String, dynamic>{};
                                    final active =
                                        (lic['active'] ?? true) == true;
                                    final isFree =
                                        (lic['isFree'] ?? false) == true;
                                    final status =
                                        (lic['status'] ?? 'trial').toString();
                                    final planId = (data['planId'] ??
                                            data['plan'] ??
                                            'inicial')
                                        .toString();
                                    final payStatus =
                                        (billing['status'] ?? 'pending')
                                            .toString();

                                    return Card(
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusMd)),
                                      shadowColor: Colors.transparent,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusMd),
                                          color:
                                              ThemeCleanPremium.cardBackground,
                                          boxShadow: ThemeCleanPremium
                                              .softUiCardShadow,
                                          border: Border.all(
                                              color: const Color(0xFFE8EDF3)),
                                        ),
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: active
                                                ? const Color(0xFFE8F5E9)
                                                : const Color(0xFFFFEBEE),
                                            child: Icon(
                                                active
                                                    ? Icons.check
                                                    : Icons.block,
                                                color: active
                                                    ? Colors.green
                                                    : Colors.red),
                                          ),
                                          title: Text(name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900)),
                                          subtitle: Text(
                                              'tenantId: $id  •  plano: ${planName(planId)}  •  licenca: $status  •  pagamento: $payStatus  •  ${isFree ? 'FREE' : 'PAGO/TRIAL'}'),
                                          trailing: Wrap(
                                            spacing: 8,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              IconButton.filledTonal(
                                                tooltip:
                                                    'Abrir site público (espelho)',
                                                onPressed: slug.isEmpty
                                                    ? null
                                                    : () async {
                                                        final url = AppConstants
                                                            .publicChurchHomeUrlForChurch(
                                                          slug,
                                                          church: data,
                                                        );
                                                        final u =
                                                            Uri.parse(url);
                                                        if (await canLaunchUrl(
                                                            u)) {
                                                          await launchUrl(u,
                                                              mode: LaunchMode
                                                                  .externalApplication);
                                                        }
                                                      },
                                                icon: const Icon(
                                                    Icons.open_in_new_rounded),
                                              ),
                                              OutlinedButton(
                                                onPressed: () => _editTenant(d),
                                                child: const Text('Editar'),
                                              ),
                                              OutlinedButton(
                                                onPressed: () =>
                                                    _openLicenseDialog(
                                                        d, plans),
                                                child: const Text('Licenca'),
                                              ),
                                              OutlinedButton(
                                                onPressed: () => _setFree(
                                                    d.reference, !isFree),
                                                child: Text(isFree
                                                    ? 'Remover Free'
                                                    : 'Definir Free'),
                                              ),
                                              FilledButton.tonal(
                                                onPressed: () => _setActive(
                                                    d.reference, !active),
                                                child: Text(active
                                                    ? 'Desativar'
                                                    : 'Ativar'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesSummary extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> plans;
  const _SalesSummary({required this.plans});

  String _money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: plans.orderBy('order').snapshots(),
      builder: (context, plansSnap) {
        if (!plansSnap.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final planPrice = <String, double>{};
        for (final p in plansSnap.data!.docs) {
          final data = p.data();
          final price = (data['priceMonthly'] ?? 0).toString();
          planPrice[p.id] = double.tryParse(price) ?? 0;
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('igrejas').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final docs = snap.data!.docs;
            final total = docs.length;
            int active = 0;
            int free = 0;
            int trial = 0;
            int blocked = 0;
            int paid = 0;
            int overdue = 0;
            double mrr = 0;

            for (final d in docs) {
              final data = d.data();
              final lic = (data['license'] is Map)
                  ? Map<String, dynamic>.from(data['license'])
                  : <String, dynamic>{};
              final billing = (data['billing'] is Map)
                  ? Map<String, dynamic>.from(data['billing'])
                  : <String, dynamic>{};

              final isActive = (lic['active'] ?? true) == true;
              final isFree = (lic['isFree'] ?? false) == true;
              final status =
                  (lic['status'] ?? 'trial').toString().toLowerCase();
              final payStatus =
                  (billing['status'] ?? 'pending').toString().toLowerCase();
              final planId =
                  (data['planId'] ?? data['plan'] ?? 'inicial').toString();

              if (isActive)
                active += 1;
              else
                blocked += 1;
              if (isFree) free += 1;
              if (status == 'trial') trial += 1;
              if (status == 'blocked') blocked += 1;
              if (payStatus == 'paid') paid += 1;
              if (payStatus == 'overdue') overdue += 1;

              if (isActive && !isFree && payStatus == 'paid') {
                mrr += planPrice[planId] ?? 0;
              }
            }

            final maxStatus = [paid, overdue, trial, blocked, free, active]
                .fold<int>(1, (p, v) => v > p ? v : p);

            return Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resumo de vendas e licencas',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _StatCard(
                            label: 'Igrejas',
                            value: total.toString(),
                            color: Colors.blue),
                        _StatCard(
                            label: 'Ativas',
                            value: active.toString(),
                            color: Colors.green),
                        _StatCard(
                            label: 'Trial',
                            value: trial.toString(),
                            color: Colors.orange),
                        _StatCard(
                            label: 'Free',
                            value: free.toString(),
                            color: Colors.indigo),
                        _StatCard(
                            label: 'Inadimplentes',
                            value: overdue.toString(),
                            color: Colors.red),
                        _StatCard(
                            label: 'MRR Estimado',
                            value: _money(mrr),
                            color: Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _BarRow(
                        label: 'Pagos',
                        value: paid,
                        max: maxStatus,
                        color: Colors.green),
                    _BarRow(
                        label: 'Inadimplentes',
                        value: overdue,
                        max: maxStatus,
                        color: Colors.red),
                    _BarRow(
                        label: 'Trial',
                        value: trial,
                        max: maxStatus,
                        color: Colors.orange),
                    _BarRow(
                        label: 'Bloqueados',
                        value: blocked,
                        max: maxStatus,
                        color: Colors.grey),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;
  const _BarRow(
      {required this.label,
      required this.value,
      required this.max,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final w = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
              width: 120,
              child:
                  Text(label, style: const TextStyle(color: Colors.black54))),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5EAF3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: w.clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 32,
              child: Text(value.toString(), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
