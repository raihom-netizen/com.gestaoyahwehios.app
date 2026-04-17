part of 'admin_panel_page.dart';

/// Lista de igrejas no painel master — métricas, filtros, gestão de licença e exclusão total.
class _IgrejasTab extends StatefulWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;
  final bool canEdit;

  const _IgrejasTab({
    required this.query,
    required this.onQueryChanged,
    required this.canEdit,
  });

  @override
  State<_IgrejasTab> createState() => _IgrejasTabState();
}

class _IgrejasTabState extends State<_IgrejasTab> {
  String _filterStatus = '';
  String _filterPlano = '';
  String _paymentFilter = '';
  late final TextEditingController _searchCtrl;
  Future<List<_BenchmarkTenant>>? _benchmarkFuture;
  String _benchmarkKey = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _IgrejasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query && widget.query != _searchCtrl.text) {
      _searchCtrl.text = widget.query;
      _searchCtrl.selection =
          TextSelection.collapsed(offset: _searchCtrl.text.length);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _passesFilters(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final q = widget.query.trim().toLowerCase();
    if (_filterStatus.isNotEmpty) {
      final st = (data['status'] ?? 'ativa').toString();
      if (st != _filterStatus) return false;
    }
    if (_filterPlano.isNotEmpty) {
      final p =
          (data['plano'] ?? data['planId'] ?? '').toString().toLowerCase();
      if (_filterPlano == 'free') {
        if (p != 'free') return false;
      } else {
        if (p == 'free' || p.isEmpty) return false;
      }
    }
    if (_paymentFilter.isNotEmpty) {
      final guard = SubscriptionGuard.evaluate(church: data);
      final matches = switch (_paymentFilter) {
        'active' =>
          !guard.blocked && !guard.inGrace && guard.masterBadgeLabel != 'FREE',
        'grace' => guard.inGrace || guard.statusAssinatura == 'overdue',
        'blocked' => guard.blocked || guard.adminBlocked,
        _ => true,
      };
      if (!matches) return false;
    }
    if (q.isNotEmpty) {
      final nome = '${data['nome'] ?? data['name'] ?? ''}'.toLowerCase();
      final slug = '${data['slug'] ?? data['alias'] ?? ''}'.toLowerCase();
      final docId = doc.id.toLowerCase();
      if (!nome.contains(q) && !slug.contains(q) && !docId.contains(q))
        return false;
    }
    return true;
  }

  Color _paymentChipColor(SubscriptionGuardState s) {
    if (s.adminBlocked || s.blocked) return const Color(0xFFDC2626);
    if (s.inGrace || s.statusAssinatura == 'overdue')
      return const Color(0xFFD97706);
    return const Color(0xFF16A34A);
  }

  bool _isMediaUrlValid(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('gs://');
  }

  bool _hasInstitutionalVideo(Map<String, dynamic> ig) {
    final candidates = [
      ig['institutionalVideoUrl'],
      ig['videoInstitucionalUrl'],
      ig['videoUrl'],
      ig['institutionalVideoStoragePath'],
      ig['videoInstitucionalPath'],
      ig['videoStoragePath'],
    ];
    return candidates.any((e) => e != null && e.toString().trim().isNotEmpty);
  }

  Future<List<_BenchmarkTenant>> _loadBenchmark(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final last30 = Timestamp.fromDate(now.subtract(const Duration(days: 30)));
    final out = <_BenchmarkTenant>[];
    for (final d in docs.take(12)) {
      final churchId = d.id;
      final churchName =
          (d.data()['nome'] ?? d.data()['name'] ?? churchId).toString();
      try {
        final membrosCol =
            db.collection('igrejas').doc(churchId).collection('membros');
        final publicTotalAgg = await membrosCol
            .where('PUBLIC_SIGNUP', isEqualTo: true)
            .count()
            .get();
        final approvedAgg = await membrosCol
            .where('PUBLIC_SIGNUP', isEqualTo: true)
            .where('status', isEqualTo: 'ativo')
            .count()
            .get();
        final approvalDocs = await membrosCol
            .where('PUBLIC_SIGNUP', isEqualTo: true)
            .where('status', isEqualTo: 'ativo')
            .limit(120)
            .get();
        final newsAgg = await db
            .collection('igrejas')
            .doc(churchId)
            .collection('noticias')
            .where('publicSite', isEqualTo: true)
            .where('createdAt', isGreaterThanOrEqualTo: last30)
            .count()
            .get();

        final totalPublic = publicTotalAgg.count ?? 0;
        final approved = approvedAgg.count ?? 0;
        final conversion =
            totalPublic == 0 ? 0.0 : (approved / totalPublic).toDouble();

        int samples = 0;
        double totalHours = 0;
        for (final m in approvalDocs.docs) {
          final map = m.data();
          final created = map['CRIADO_EM'];
          final approvedAt = map['aprovadoEm'];
          if (created is Timestamp && approvedAt is Timestamp) {
            final h =
                approvedAt.toDate().difference(created.toDate()).inMinutes /
                    60.0;
            if (h >= 0) {
              totalHours += h;
              samples++;
            }
          }
        }
        final avgHours = samples == 0 ? null : (totalHours / samples);
        out.add(_BenchmarkTenant(
          churchId: churchId,
          churchName: churchName,
          conversionRate: conversion,
          siteEngagement30d: newsAgg.count ?? 0,
          avgApprovalHours: avgHours,
          totalPublicSignups: totalPublic,
        ));
      } catch (_) {}
    }
    out.sort((a, b) => b.conversionRate.compareTo(a.conversionRate));
    return out;
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return digits.startsWith('55') ? digits : '55$digits';
  }

  Uri? _tenantChargeWhatsappUri(Map<String, dynamic> ig, String igrejaId) {
    final nome = (ig['nome'] ?? ig['name'] ?? igrejaId).toString().trim();
    final phoneRaw = (ig['whatsappIgreja'] ??
            ig['whatsapp'] ??
            ig['telefone'] ??
            ig['telefoneIgreja'] ??
            ig['gestorTelefone'] ??
            ig['whatsappGestor'] ??
            '')
        .toString()
        .trim();
    final phone = _normalizePhone(phoneRaw);
    if (phone.isEmpty) return null;
    final msg = Uri.encodeComponent(
      'Olá, paz e graça! Aqui é da equipe Gestão YAHWEH.\n'
      'Identificamos pendência da licença da igreja "$nome".\n'
      'Podemos te ajudar com a regularização agora mesmo.',
    );
    return Uri.parse('https://wa.me/$phone?text=$msg');
  }

  Future<void> _openChargeWhatsapp(
    BuildContext context,
    Map<String, dynamic> ig,
    String igrejaId,
  ) async {
    final uri = _tenantChargeWhatsappUri(ig, igrejaId);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
            'Sem telefone/WhatsApp cadastrado para cobrança.'),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
            'Não foi possível abrir o WhatsApp.'),
      );
    }
  }

  Future<void> _abrirGestaoLicenca(
    BuildContext context, {
    required String igrejaId,
    required String nome,
    required Map<String, dynamic> ig,
  }) async {
    final billing = BillingLicenseService();
    final lic = ig['license'] is Map
        ? Map<String, dynamic>.from(ig['license'] as Map)
        : <String, dynamic>{};
    final adminBlocked =
        ig['adminBlocked'] == true || lic['adminBlocked'] == true;
    final isFree = lic['isFree'] == true ||
        (ig['plano'] ?? '').toString().toLowerCase() == 'free';
    String planoSel = (ig['planId'] ?? ig['plano'] ?? 'essencial').toString();
    if (!planosOficiais.any((p) => p.id == planoSel))
      planoSel = planosOficiais.first.id;
    DateTime? venc = ig['licenseExpiresAt'] is Timestamp
        ? (ig['licenseExpiresAt'] as Timestamp).toDate()
        : null;
    String ciclo = (ig['billingCycle'] ?? 'monthly').toString();
    if (ciclo != 'annual') ciclo = 'monthly';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.cardBackground,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusLg),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      Text('ID: $igrejaId',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 16),
                      Text('Plano manual',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: ThemeCleanPremium.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: planoSel,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: planosOficiais
                            .map((p) => DropdownMenuItem(
                                value: p.id, child: Text(p.name)))
                            .toList(),
                        onChanged: widget.canEdit
                            ? (v) => setModal(() => planoSel = v ?? planoSel)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text('Ciclo (informação)',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: ThemeCleanPremium.onSurfaceVariant)),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Mensal'),
                              selected: ciclo == 'monthly',
                              onSelected: widget.canEdit
                                  ? (sel) {
                                      if (sel)
                                        setModal(() => ciclo = 'monthly');
                                    }
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Anual'),
                              selected: ciclo == 'annual',
                              onSelected: widget.canEdit
                                  ? (sel) {
                                      if (sel) setModal(() => ciclo = 'annual');
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Data de vencimento da licença'),
                        subtitle: Text(venc != null
                            ? DateFormat('dd/MM/yyyy').format(venc!)
                            : 'Não definida'),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_month_rounded),
                          onPressed: widget.canEdit
                              ? () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: venc ??
                                        DateTime.now()
                                            .add(const Duration(days: 30)),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2040),
                                  );
                                  if (d != null) setModal(() => venc = d);
                                }
                              : null,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.canEdit
                            ? () => setModal(() => venc = null)
                            : null,
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        label: const Text('Remover data de vencimento'),
                      ),
                      const Divider(height: 28),
                      if (!isFree)
                        FilledButton.tonalIcon(
                          onPressed: widget.canEdit
                              ? () async {
                                  try {
                                    await billing.setTenantFreeMaster(igrejaId);
                                    if (context.mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        ThemeCleanPremium.successSnackBar(
                                            'Igreja marcada como FREE.'),
                                      );
                                      setState(() {});
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text('$e'),
                                            backgroundColor:
                                                ThemeCleanPremium.error),
                                      );
                                    }
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.money_off_csred_rounded),
                          label: const Text('Marcar igreja como FREE'),
                        )
                      else
                        Text(
                          'Esta igreja está em modo FREE. Use "Aplicar plano" para cobrança normal.',
                          style: TextStyle(
                              fontSize: 13,
                              color: ThemeCleanPremium.onSurfaceVariant),
                        ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bloquear igreja (master)'),
                        subtitle:
                            const Text('Gestor vê apenas tela de renovação'),
                        value: adminBlocked,
                        onChanged: widget.canEdit
                            ? (v) async {
                                try {
                                  await billing.setTenantAdminBlocked(
                                      igrejaId, v);
                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      ThemeCleanPremium.successSnackBar(v
                                          ? 'Igreja bloqueada.'
                                          : 'Bloqueio removido.'),
                                    );
                                    setState(() {});
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('$e'),
                                          backgroundColor:
                                              ThemeCleanPremium.error),
                                    );
                                  }
                                }
                              }
                            : null,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: widget.canEdit
                            ? () async {
                                try {
                                  await billing.setTenantPlanAndLicenseExpiry(
                                    igrejaId,
                                    planoSel,
                                    licenseExpiresAt: venc,
                                    billingCycle: ciclo,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      ThemeCleanPremium.successSnackBar(
                                          'Plano e licença atualizados.'),
                                    );
                                    setState(() {});
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('$e'),
                                          backgroundColor:
                                              ThemeCleanPremium.error),
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Aplicar plano / vencimento'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: widget.canEdit
                            ? () async {
                                final ok = await showDialog<bool>(
                                  context: ctx,
                                  builder: (dctx) => AlertDialog(
                                    title: const Text(
                                        'Excluir igreja permanentemente?'),
                                    content: Text(
                                      'Remove o documento da igreja e subcoleções (membros, financeiro, etc.). '
                                      'Não remove usuários Auth. Esta ação não pode ser desfeita.\n\n"$nome"',
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dctx, false),
                                          child: const Text('Cancelar')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                            backgroundColor:
                                                ThemeCleanPremium.error),
                                        onPressed: () =>
                                            Navigator.pop(dctx, true),
                                        child: const Text('Excluir tudo'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                try {
                                  await billing
                                      .removerIgrejaELimparDados(igrejaId);
                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      ThemeCleanPremium.successSnackBar(
                                          'Igreja e dados vinculados foram removidos.'),
                                    );
                                    setState(() {});
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('$e'),
                                          backgroundColor:
                                              ThemeCleanPremium.error),
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: Icon(Icons.delete_forever_rounded,
                            color: ThemeCleanPremium.error),
                        label: Text('Exclusão total no banco',
                            style: TextStyle(color: ThemeCleanPremium.error)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Fechar'),
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
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow =
        MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointTablet;
    final padding = EdgeInsets.all(
        isNarrow ? ThemeCleanPremium.spaceSm : ThemeCleanPremium.spaceMd);

    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance.collection('igrejas').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Erro: ${snap.error}',
                        style: TextStyle(color: ThemeCleanPremium.error)),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final allDocs = snap.data!.docs;
              final docs = allDocs.where(_passesFilters).toList();
              final benchKey = docs.take(20).map((e) => e.id).join('|');
              if (_benchmarkFuture == null || _benchmarkKey != benchKey) {
                _benchmarkKey = benchKey;
                _benchmarkFuture = _loadBenchmark(docs);
              }
              final total = allDocs.length;
              final ativas = allDocs
                  .where((d) =>
                      (d.data()['status'] ?? 'ativa').toString() == 'ativa')
                  .length;
              final inativas = allDocs
                  .where(
                      (d) => (d.data()['status'] ?? '').toString() == 'inativa')
                  .length;
              final novasMes = allDocs.where((d) {
                final data = d.data()['createdAt'] ?? d.data()['dataCadastro'];
                if (data is Timestamp) {
                  final now = DateTime.now();
                  final dt = data.toDate();
                  return dt.month == now.month && dt.year == now.year;
                }
                return false;
              }).length;

              final billing = BillingLicenseService();
              final healthWithoutLogo = allDocs.where((d) {
                final ig = d.data();
                final logo = (ig['logoUrl'] ??
                        ig['logo_url'] ??
                        ig['logoProcessedUrl'] ??
                        '')
                    .toString()
                    .trim();
                return logo.isEmpty;
              }).length;
              final healthWithoutVideo = allDocs.where((d) {
                final ig = d.data();
                return !_hasInstitutionalVideo(ig);
              }).length;
              final mediaBroken = allDocs.where((d) {
                final ig = d.data();
                final logo =
                    (ig['logoUrl'] ?? ig['logoProcessedUrl'] ?? '').toString();
                final video = (ig['institutionalVideoUrl'] ??
                        ig['videoInstitucionalUrl'] ??
                        ig['videoUrl'] ??
                        '')
                    .toString();
                final brokenLogo =
                    logo.trim().isNotEmpty && !_isMediaUrlValid(logo);
                final brokenVideo =
                    video.trim().isNotEmpty && !_isMediaUrlValid(video);
                return brokenLogo || brokenVideo;
              }).length;
              final siteUnavailable = allDocs.where((d) {
                final ig = d.data();
                final guard = SubscriptionGuard.evaluate(church: ig);
                final inativa =
                    (ig['status'] ?? 'ativa').toString().toLowerCase() ==
                        'inativa';
                return inativa || guard.blocked || guard.adminBlocked;
              }).length;
              final healthInGrace = allDocs
                  .where((d) =>
                      SubscriptionGuard.evaluate(church: d.data()).inGrace)
                  .length;
              final healthBlocked = allDocs
                  .where((d) =>
                      SubscriptionGuard.evaluate(church: d.data()).blocked)
                  .length;
              final dueSoon = allDocs.where((d) {
                final guard = SubscriptionGuard.evaluate(church: d.data());
                if (guard.blocked || guard.adminBlocked || guard.isFree) {
                  return false;
                }
                final venc = guard.dataVencimento;
                if (venc == null) return false;
                final days = venc.difference(DateTime.now()).inDays;
                return days >= 0 && days <= 7;
              }).length;
              final now = DateTime.now();
              final chargeCandidates = allDocs.where((d) {
                final guard = SubscriptionGuard.evaluate(church: d.data());
                if (guard.blocked ||
                    guard.inGrace ||
                    guard.statusAssinatura == 'overdue') return true;
                final exp = guard.dataVencimento;
                if (exp == null) return false;
                final days = exp.difference(now).inDays;
                return days >= 0 && days <= 7;
              }).toList()
                ..sort((a, b) {
                  final ga = SubscriptionGuard.evaluate(church: a.data());
                  final gb = SubscriptionGuard.evaluate(church: b.data());
                  final da = ga.dataVencimento ?? DateTime(2099);
                  final dbb = gb.dataVencimento ?? DateTime(2099);
                  return da.compareTo(dbb);
                });

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: isNarrow
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.payment_rounded),
                            label: const Text('Mercado Pago (Admin)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: ThemeCleanPremium.spaceLg,
                                  vertical: ThemeCleanPremium.spaceSm),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const MercadoPagoAdminPage()),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        isNarrow
                            ? Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _MetricCard(label: 'Total', value: total),
                                  _MetricCard(label: 'Ativas', value: ativas),
                                  _MetricCard(
                                      label: 'Inativas', value: inativas),
                                  _MetricCard(
                                      label: 'Novas mês', value: novasMes),
                                ],
                              )
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _MetricCard(label: 'Total', value: total),
                                  _MetricCard(label: 'Ativas', value: ativas),
                                  _MetricCard(
                                      label: 'Inativas', value: inativas),
                                  _MetricCard(
                                      label: 'Novas mês', value: novasMes),
                                ],
                              ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Saúde dos tenants (visão única)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _MetricCard(
                                        label: 'Sem logo',
                                        value: healthWithoutLogo),
                                    _MetricCard(
                                        label: 'Sem vídeo',
                                        value: healthWithoutVideo),
                                    _MetricCard(
                                        label: 'Mídia quebrada',
                                        value: mediaBroken),
                                    _MetricCard(
                                        label: 'Site indisponível',
                                        value: siteUnavailable),
                                    _MetricCard(
                                        label: 'Vencimento próximo',
                                        value: dueSoon),
                                    _MetricCard(
                                        label: 'Em carência',
                                        value: healthInGrace),
                                    _MetricCard(
                                        label: 'Bloqueadas',
                                        value: healthBlocked),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Benchmark entre igrejas (SaaS)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 8),
                                FutureBuilder<List<_BenchmarkTenant>>(
                                  future: _benchmarkFuture,
                                  builder: (context, benchSnap) {
                                    if (!benchSnap.hasData) {
                                      return const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 10),
                                        child: LinearProgressIndicator(),
                                      );
                                    }
                                    final rows = benchSnap.data!;
                                    if (rows.isEmpty) {
                                      return Text(
                                        'Sem dados suficientes ainda para benchmark.',
                                        style: TextStyle(
                                            color: ThemeCleanPremium
                                                .onSurfaceVariant),
                                      );
                                    }
                                    return Column(
                                      children: rows.take(6).map((r) {
                                        final conv = (r.conversionRate * 100)
                                            .toStringAsFixed(1);
                                        final approval = r.avgApprovalHours ==
                                                null
                                            ? 'n/d'
                                            : '${r.avgApprovalHours!.toStringAsFixed(1)}h';
                                        return ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: const Icon(
                                              Icons.insights_rounded),
                                          title: Text(
                                            r.churchName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            'Conversão: $conv% (${r.totalPublicSignups} cadastros) • Engajamento 30d: ${r.siteEngagement30d} posts • Aprovação média: $approval',
                                            style: TextStyle(
                                              color: ThemeCleanPremium
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cobrança inteligente (vencendo / em atraso)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 8),
                                if (chargeCandidates.isEmpty)
                                  Text(
                                    'Nenhuma igreja com cobrança prioritária agora.',
                                    style: TextStyle(
                                        color:
                                            ThemeCleanPremium.onSurfaceVariant),
                                  )
                                else
                                  ...chargeCandidates.take(6).map((d) {
                                    final ig = d.data();
                                    final nome =
                                        (ig['nome'] ?? ig['name'] ?? d.id)
                                            .toString();
                                    final guard =
                                        SubscriptionGuard.evaluate(church: ig);
                                    final exp = guard.dataVencimento;
                                    final due = exp != null
                                        ? DateFormat('dd/MM').format(exp)
                                        : '—';
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                          Icons.notifications_active_rounded,
                                          color: _paymentChipColor(guard)),
                                      title: Text(nome,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                        'Status: ${guard.masterBadgeLabel} • Venc.: $due',
                                        style: TextStyle(
                                            color: ThemeCleanPremium
                                                .onSurfaceVariant),
                                      ),
                                      trailing: IconButton(
                                        tooltip: 'Cobrar no WhatsApp',
                                        icon: const Icon(Icons.chat_rounded),
                                        onPressed: () => _openChargeWhatsapp(
                                            context, ig, d.id),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                if (isNarrow) ...[
                                  TextField(
                                    controller: _searchCtrl,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      hintText:
                                          'Buscar por nome, slug ou ID...',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: widget.onQueryChanged,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: widget.canEdit
                                          ? () async {
                                              await showDialog(
                                                  context: context,
                                                  builder: (_) =>
                                                      const _NovaIgrejaDialog());
                                            }
                                          : null,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Nova igreja'),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    value: _filterStatus.isEmpty
                                        ? null
                                        : _filterStatus,
                                    decoration: const InputDecoration(
                                        labelText: 'Status'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: null, child: Text('Todos')),
                                      DropdownMenuItem(
                                          value: 'ativa', child: Text('Ativa')),
                                      DropdownMenuItem(
                                          value: 'inativa',
                                          child: Text('Inativa')),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _filterStatus = v ?? ''),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _filterPlano.isEmpty
                                        ? null
                                        : _filterPlano,
                                    decoration: const InputDecoration(
                                        labelText: 'Plano'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: null, child: Text('Todos')),
                                      DropdownMenuItem(
                                          value: 'free', child: Text('Free')),
                                      DropdownMenuItem(
                                          value: 'pago', child: Text('Pagos')),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _filterPlano = v ?? ''),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ChoiceChip(
                                        label: const Text('Ativas'),
                                        selected: _paymentFilter == 'active',
                                        onSelected: (_) => setState(() =>
                                            _paymentFilter =
                                                _paymentFilter == 'active'
                                                    ? ''
                                                    : 'active'),
                                      ),
                                      ChoiceChip(
                                        label:
                                            const Text('Em atraso (carência)'),
                                        selected: _paymentFilter == 'grace',
                                        onSelected: (_) => setState(() =>
                                            _paymentFilter =
                                                _paymentFilter == 'grace'
                                                    ? ''
                                                    : 'grace'),
                                      ),
                                      ChoiceChip(
                                        label: const Text('Bloqueadas'),
                                        selected: _paymentFilter == 'blocked',
                                        onSelected: (_) => setState(() =>
                                            _paymentFilter =
                                                _paymentFilter == 'blocked'
                                                    ? ''
                                                    : 'blocked'),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _searchCtrl,
                                          decoration: const InputDecoration(
                                            prefixIcon: Icon(Icons.search),
                                            hintText:
                                                'Buscar por nome, slug ou ID...',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          onChanged: widget.onQueryChanged,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.icon(
                                        onPressed: widget.canEdit
                                            ? () async {
                                                await showDialog(
                                                    context: context,
                                                    builder: (_) =>
                                                        const _NovaIgrejaDialog());
                                              }
                                            : null,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Nova'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: _filterStatus.isEmpty
                                              ? null
                                              : _filterStatus,
                                          decoration: const InputDecoration(
                                              labelText: 'Status'),
                                          items: const [
                                            DropdownMenuItem(
                                                value: null,
                                                child: Text('Todos')),
                                            DropdownMenuItem(
                                                value: 'ativa',
                                                child: Text('Ativa')),
                                            DropdownMenuItem(
                                                value: 'inativa',
                                                child: Text('Inativa')),
                                          ],
                                          onChanged: (v) => setState(
                                              () => _filterStatus = v ?? ''),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: _filterPlano.isEmpty
                                              ? null
                                              : _filterPlano,
                                          decoration: const InputDecoration(
                                              labelText: 'Plano'),
                                          items: const [
                                            DropdownMenuItem(
                                                value: null,
                                                child: Text('Todos')),
                                            DropdownMenuItem(
                                                value: 'free',
                                                child: Text('Free')),
                                            DropdownMenuItem(
                                                value: 'pago',
                                                child: Text('Pagos')),
                                          ],
                                          onChanged: (v) => setState(
                                              () => _filterPlano = v ?? ''),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ChoiceChip(
                                        label: const Text('Ativas'),
                                        selected: _paymentFilter == 'active',
                                        onSelected: (_) => setState(() =>
                                            _paymentFilter =
                                                _paymentFilter == 'active'
                                                    ? ''
                                                    : 'active'),
                                      ),
                                      ChoiceChip(
                                        label:
                                            const Text('Em atraso (carência)'),
                                        selected: _paymentFilter == 'grace',
                                        onSelected: (_) => setState(() =>
                                            _paymentFilter =
                                                _paymentFilter == 'grace'
                                                    ? ''
                                                    : 'grace'),
                                      ),
                                      ChoiceChip(
                                        label: const Text('Bloqueadas'),
                                        selected: _paymentFilter == 'blocked',
                                        onSelected: (_) => setState(() =>
                                            _paymentFilter =
                                                _paymentFilter == 'blocked'
                                                    ? ''
                                                    : 'blocked'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${docs.length} igreja(s) na lista',
                            style: TextStyle(
                                fontSize: 13,
                                color: ThemeCleanPremium.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  if (docs.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.church_rounded,
                                size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              allDocs.isEmpty
                                  ? 'Nenhuma igreja cadastrada.'
                                  : 'Nenhum resultado com os filtros atuais.',
                              style: TextStyle(
                                  color: ThemeCleanPremium.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final doc = docs[i];
                          final ig = doc.data();
                          final igrejaId = doc.id;
                          final status = (ig['status'] ?? 'ativa').toString();
                          final removed = ig['removedByAdminAt'] != null;
                          var licenseExpiresAt = ig['licenseExpiresAt']
                                  is Timestamp
                              ? (ig['licenseExpiresAt'] as Timestamp).toDate()
                              : null;
                          if (licenseExpiresAt == null &&
                              ig['license'] is Map) {
                            final lic = ig['license'] as Map;
                            final exp = lic['expiresAt'];
                            if (exp is Timestamp)
                              licenseExpiresAt = exp.toDate();
                          }
                          final now = DateTime.now();
                          final hasActiveLicense = licenseExpiresAt != null &&
                              licenseExpiresAt.isAfter(now);
                          final daysLeft = licenseExpiresAt != null
                              ? licenseExpiresAt.difference(now).inDays
                              : null;
                          final guard = SubscriptionGuard.evaluate(church: ig);
                          final plano =
                              (ig['plano'] ?? ig['planId'] ?? '—').toString();
                          final adminB = ig['adminBlocked'] == true;
                          final licMap = ig['license'] is Map
                              ? ig['license'] as Map
                              : null;
                          final adminB2 = licMap?['adminBlocked'] == true;
                          String validadeStr = '';
                          if (licenseExpiresAt != null) {
                            validadeStr =
                                'Venc.: ${DateFormat('dd/MM/yyyy').format(licenseExpiresAt)}';
                            if (hasActiveLicense && daysLeft != null)
                              validadeStr += ' (${daysLeft}d)';
                          } else {
                            validadeStr = plano == 'free' ? 'FREE' : '—';
                          }
                          final nome = (ig['nome'] ?? ig['name'] ?? 'Sem nome')
                              .toString();
                          final responsavel =
                              (ig['responsavel'] ?? ig['gestorNome'] ?? '')
                                  .toString();
                          final actionButtons = <Widget>[
                            if (widget.canEdit)
                              IconButton(
                                tooltip:
                                    'Licença, FREE, bloqueio, exclusão',
                                icon: const Icon(
                                    Icons.admin_panel_settings_rounded),
                                onPressed: () => _abrirGestaoLicenca(context,
                                    igrejaId: igrejaId, nome: nome, ig: ig),
                              ),
                            if (widget.canEdit && !removed && plano != 'free')
                              IconButton(
                                tooltip: '+15 dias',
                                icon: const Icon(Icons.date_range_rounded),
                                onPressed: () async {
                                  await billing.prorrogarTenant(igrejaId, 15);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      ThemeCleanPremium.successSnackBar(
                                          'Prazo +15 dias.'),
                                    );
                                  }
                                },
                              ),
                            if (widget.canEdit && !removed && plano != 'free')
                              IconButton(
                                tooltip: 'Bônus +7 dias',
                                icon: const Icon(Icons.card_giftcard_rounded),
                                onPressed: () async {
                                  await billing.prorrogarTenant(igrejaId, 7);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      ThemeCleanPremium.successSnackBar(
                                          'Bônus aplicado: +7 dias de licença.'),
                                    );
                                  }
                                },
                              ),
                            if (widget.canEdit && removed)
                              IconButton(
                                tooltip: 'Reativar',
                                icon: const Icon(Icons.person_add_rounded),
                                onPressed: () async {
                                  await billing.reativarTenant(igrejaId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      ThemeCleanPremium.successSnackBar(
                                          'Igreja reativada.'),
                                    );
                                  }
                                },
                              ),
                            if (widget.canEdit && !removed)
                              IconButton(
                                tooltip: 'Remover acesso (soft)',
                                icon: const Icon(Icons.person_remove_rounded),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Remover igreja'),
                                      content: Text(
                                          'Remover "$nome"? Pode reativar depois.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancelar')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Remover')),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await billing.removerTenant(igrejaId);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        ThemeCleanPremium.successSnackBar(
                                            'Igreja removida (soft).'),
                                      );
                                    }
                                  }
                                },
                              ),
                            IconButton(
                              tooltip: 'Detalhes',
                              icon: const Icon(Icons.info_outline_rounded),
                              onPressed: () {
                                showDialog(
                                    context: context,
                                    builder: (_) =>
                                        _DetalhesIgrejaDialog(igreja: ig));
                              },
                            ),
                            if (widget.canEdit)
                              IconButton(
                                tooltip: 'Editar cadastro',
                                icon: const Icon(Icons.edit_rounded),
                                onPressed: () async {
                                  await showDialog(
                                    context: context,
                                    builder: (_) => _EditIgrejaDialog(
                                      title: 'Editar igreja',
                                      canEdit: widget.canEdit,
                                      tenantId: igrejaId,
                                      igreja: ig,
                                    ),
                                  );
                                },
                              ),
                          ];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              leading: Icon(Icons.church_rounded,
                                  color: ThemeCleanPremium.primary, size: 32),
                              title: isNarrow
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nome,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _paymentChipColor(guard)
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: _paymentChipColor(guard)
                                                    .withOpacity(0.35)),
                                          ),
                                          child: Text(
                                            'Pagamento: ${guard.masterBadgeLabel}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _paymentChipColor(guard),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            nome,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _paymentChipColor(guard)
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: _paymentChipColor(guard)
                                                    .withOpacity(0.35)),
                                          ),
                                          child: Text(
                                            'Pagamento: ${guard.masterBadgeLabel}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _paymentChipColor(guard),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'ID: $igrejaId',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'monospace',
                                            color: ThemeCleanPremium.onSurface,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Copiar ID',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.copy_rounded,
                                            size: 18),
                                        onPressed: () {
                                          Clipboard.setData(
                                              ClipboardData(text: igrejaId));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            ThemeCleanPremium.successSnackBar(
                                                'ID da igreja copiado.'),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'Gestor: $responsavel\n'
                                    'Plano: $plano | $validadeStr | $status'
                                    '${guard.inGrace ? ' | Carência: ${guard.graceDaysLeft}d' : ''}'
                                    '${adminB || adminB2 ? " | BLOQUEADA (master)" : ""}'
                                    '${removed ? " | Removida" : ""}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            ThemeCleanPremium.onSurfaceVariant),
                                  ),
                                  if (isNarrow) ...[
                                    const SizedBox(height: 6),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(children: actionButtons),
                                    ),
                                  ],
                                ],
                              ),
                              isThreeLine: !isNarrow,
                              titleAlignment: ListTileTitleAlignment.top,
                              trailing: isNarrow
                                  ? null
                                  : Wrap(spacing: 4, children: actionButtons),
                              minLeadingWidth: 24,
                            ),
                          );
                        },
                        childCount: docs.length,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BenchmarkTenant {
  final String churchId;
  final String churchName;
  final double conversionRate;
  final int siteEngagement30d;
  final double? avgApprovalHours;
  final int totalPublicSignups;

  const _BenchmarkTenant({
    required this.churchId,
    required this.churchName,
    required this.conversionRate,
    required this.siteEngagement30d,
    required this.avgApprovalHours,
    required this.totalPublicSignups,
  });
}
