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
  DateTime? _benchmarkFetchedAt;
  static const Duration _benchmarkCacheTtl = Duration(minutes: 4);
  MasterDashboardSummary? _masterSummary;
  Future<MasterDashboardSummary>? _masterSummaryFuture;
  List<MasterChurchListItem> _churches = const [];
  bool _churchesLoading = true;
  String? _churchesLoadError;
  bool _benchmarkRequested = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.query);
    unawaited(_loadChurchesList());
    _masterSummaryFuture = _loadMasterSummary();
  }

  Future<void> _loadChurchesList({bool force = false}) async {
    if (!mounted) return;
    final mem = MasterChurchesListService.peekMemory();
    if (!force && mem != null && mem.isNotEmpty) {
      setState(() {
        _churches = mem;
        _churchesLoading = false;
        _churchesLoadError = null;
      });
    } else {
      setState(() {
        _churchesLoading = true;
        _churchesLoadError = null;
      });
    }
    try {
      var list = await MasterChurchesListService.loadFast(
        force: force,
      ).timeout(const Duration(seconds: 22));
      if (list.isEmpty && !force) {
        MasterDashboardSummary? summary = _masterSummary;
        if (summary == null && _masterSummaryFuture != null) {
          try {
            summary = await _masterSummaryFuture;
          } catch (_) {}
        }
        if (summary != null && summary.igrejas > 0) {
          list = await MasterChurchesListService.loadFast(
            force: true,
          ).timeout(const Duration(seconds: 25));
        }
      }
      if (!mounted) return;
      setState(() {
        _churches = list;
        _churchesLoading = false;
        _churchesLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = MasterChurchesListService.peekMemory();
      setState(() {
        _churchesLoading = false;
        if (cached != null && cached.isNotEmpty) {
          _churches = cached;
          _churchesLoadError = null;
        } else {
          _churchesLoadError = formatFirebaseErrorForUser(
            e,
            logToCrashlytics: false,
          );
        }
      });
    }
  }

  /// Botão de ação do cartão de igreja — pílula colorida com ícone + rótulo.
  ///
  /// Antes eram `IconButton` cinzentos sem legenda: no painel master ninguém
  /// sabia o que cada ícone fazia sem passar o rato por cima.
  Widget _acaoPill({
    required IconData icon,
    required String label,
    required String tooltip,
    required Color cor,
    required VoidCallback? onTap,
    bool destacado = false,
  }) {
    final ativo = onTap != null;
    final base = ativo ? cor : const Color(0xFF94A3B8);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: destacado ? base : base.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: base.withValues(alpha: destacado ? 1 : 0.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: destacado ? Colors.white : base,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: destacado ? Colors.white : base,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Confirmação moderna e colorida (substitui os `AlertDialog` crus).
  Future<bool> _confirmarModerno(
    BuildContext context, {
    required String titulo,
    required String mensagem,
    required IconData icone,
    required Color cor,
    required String confirmar,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cor, cor.withValues(alpha: 0.70)],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ThemeCleanPremium.radiusLg),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icone, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, false),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Voltar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: cor),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: Icon(icone, size: 18),
                  label: Text(confirmar),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Executa uma ação de licença do master com feedback e recarga da lista.
  ///
  /// Antes o `onPressed` fazia `await` sem `try` — se a escrita falhasse (ex.:
  /// `INTERNAL ASSERTION` do SDK na web) o botão ficava mudo e a lista não
  /// refletia a alteração (classe §8 dos defeitos recorrentes).
  Future<void> _runTenantAction(
    BuildContext context, {
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    try {
      await action();
      MasterChurchesListService.invalidateMemory();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(ThemeCleanPremium.successSnackBar(successMessage));
      await _loadChurchesList(force: true);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatFirebaseErrorForUser(e, logToCrashlytics: false)),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
  }

  Future<MasterDashboardSummary> _loadMasterSummary() async {
    final instant = await MasterDashboardCacheService.readCachedInstant();
    if (instant != null) {
      _masterSummary = instant;
      if (!instant.isFresh) {
        MasterDashboardCacheService.revalidateInBackground(
          onUpdated: (s) {
            if (!mounted) return;
            setState(() => _masterSummary = s);
          },
        );
      }
      return instant;
    }
    final warmed = await MasterDashboardCacheService.warmFromCallable();
    _masterSummary = warmed;
    return warmed;
  }

  @override
  void didUpdateWidget(covariant _IgrejasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query && widget.query != _searchCtrl.text) {
      _searchCtrl.text = widget.query;
      _searchCtrl.selection = TextSelection.collapsed(
        offset: _searchCtrl.text.length,
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _passesFilters(MasterChurchListItem item) {
    final data = item.data;
    final docId = item.id;
    final q = widget.query.trim().toLowerCase();
    if (_filterStatus.isNotEmpty) {
      final st = (data['status'] ?? 'ativa').toString();
      if (st != _filterStatus) return false;
    }
    if (_filterPlano.isNotEmpty) {
      final p = (data['plano'] ?? data['planId'] ?? '')
          .toString()
          .toLowerCase();
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
      final idLower = docId.toLowerCase();
      if (!nome.contains(q) && !slug.contains(q) && !idLower.contains(q)) {
        return false;
      }
    }
    return true;
  }

  Color _paymentChipColor(SubscriptionGuardState s) {
    if (s.isFree) {
      if (s.adminBlocked) return const Color(0xFF7C3AED);
      return const Color(0xFF0D9488);
    }
    if (s.adminBlocked || s.blocked) return const Color(0xFFDC2626);
    if (s.inGrace || s.statusAssinatura == 'overdue') {
      return const Color(0xFFD97706);
    }
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

  /// Amostra de membros aprovados via cadastro público.
  ///
  /// Web/desktop: REST. O `get()` do SDK JS abre um alvo de LISTEN por leitura;
  /// o painel master varria até 8 igrejas de uma vez e cada alvo somava no
  /// `WatchChangeAggregator` — origem do `INTERNAL ASSERTION FAILED`.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _benchmarkApprovedDocs(CollectionReference<Map<String, dynamic>> col) async {
    if (YahwehRestFirst.prefer) {
      return firestoreRestCollect(
        collectionPath: col.path,
        filters: [
          RestFieldFilter.equal('PUBLIC_SIGNUP', true),
          RestFieldFilter.equal('status', 'ativo'),
        ],
        limit: 120,
      );
    }
    final snap = await col
        .where('PUBLIC_SIGNUP', isEqualTo: true)
        .where('status', isEqualTo: 'ativo')
        .limit(120)
        .get();
    return snap.docs;
  }

  Future<List<_BenchmarkTenant>> _loadBenchmark(
    List<MasterChurchListItem> items,
  ) async {
    final now = DateTime.now();
    final last30 = Timestamp.fromDate(now.subtract(const Duration(days: 30)));
    final out = <_BenchmarkTenant>[];
    for (final d in items.take(8)) {
      final churchId = d.id;
      final churchName = (d.data['nome'] ?? d.data['name'] ?? churchId)
          .toString();
      try {
        final op = ChurchPanelTenantGateway.churchId(churchId.trim());
        final membrosCol = ChurchUiCollections.membros(op);
        final publicTotalAgg = await membrosCol
            .where('PUBLIC_SIGNUP', isEqualTo: true)
            .count()
            .get();
        final approvedAgg = await membrosCol
            .where('PUBLIC_SIGNUP', isEqualTo: true)
            .where('status', isEqualTo: 'ativo')
            .count()
            .get();
        final approvalDocs = await _benchmarkApprovedDocs(membrosCol);
        final newsAgg = await ChurchUiCollections.eventos(churchId)
            .where('publicSite', isEqualTo: true)
            .where('createdAt', isGreaterThanOrEqualTo: last30)
            .count()
            .get();

        final totalPublic = publicTotalAgg.count ?? 0;
        final approved = approvedAgg.count ?? 0;
        final conversion = totalPublic == 0
            ? 0.0
            : (approved / totalPublic).toDouble();

        int samples = 0;
        double totalHours = 0;
        for (final m in approvalDocs) {
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
        out.add(
          _BenchmarkTenant(
            churchId: churchId,
            churchName: churchName,
            conversionRate: conversion,
            siteEngagement30d: newsAgg.count ?? 0,
            avgApprovalHours: avgHours,
            totalPublicSignups: totalPublic,
          ),
        );
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
    final phoneRaw =
        (ig['whatsappIgreja'] ??
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
          'Sem telefone/WhatsApp cadastrado para cobrança.',
        ),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Não foi possível abrir o WhatsApp.',
        ),
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
    final planKey = (ig['planId'] ?? ig['plano'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final initialBlocked =
        ig['adminBlocked'] == true || lic['adminBlocked'] == true;
    var adminBlocked = initialBlocked;
    var modoFree =
        planKey == 'free' ||
        (planKey.isEmpty && (ig['isFree'] == true || lic['isFree'] == true));
    if (planKey.isNotEmpty && planKey != 'free') {
      modoFree = false;
    }
    final initialModoFree = modoFree;
    String planoSel = (ig['planId'] ?? ig['plano'] ?? 'essencial').toString();
    if (planoSel == 'free' || !planosOficiais.any((p) => p.id == planoSel)) {
      planoSel = planosOficiais.first.id;
    }
    DateTime? venc = LicenseAccessPolicy.churchAccessEnd(ig);
    final initialVenc = venc;
    final initialPlanoSel = planoSel == 'free' || planoSel.isEmpty
        ? planosOficiais.first.id
        : planoSel;
    String ciclo = (ig['billingCycle'] ?? 'monthly').toString();
    if (ciclo != 'annual') ciclo = 'monthly';
    final initialCiclo = ciclo;
    var saving = false;

    Future<void> persistLicense(
      BuildContext sheetCtx,
      void Function(void Function()) setModal,
    ) async {
      if (saving) return;
      setModal(() => saving = true);
      try {
        final blockChanged = adminBlocked != initialBlocked;
        final licenseChanged =
            modoFree != initialModoFree ||
            (!modoFree &&
                (planoSel != initialPlanoSel ||
                    venc != initialVenc ||
                    ciclo != initialCiclo));

        if (blockChanged && !licenseChanged) {
          await billing.applyMasterLicenseConfig(
            igrejaId,
            isFreeMode: null,
            adminBlocked: adminBlocked,
            touchBlockOnly: true,
          );
        } else {
          await billing.applyMasterLicenseConfig(
            igrejaId,
            isFreeMode: modoFree,
            planId: modoFree ? null : planoSel,
            licenseExpiresAt: modoFree ? null : venc,
            billingCycle: ciclo,
            adminBlocked: adminBlocked,
          );
        }
        MasterChurchesListService.invalidateMemory();
        if (context.mounted) {
          Navigator.pop(sheetCtx);
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
              blockChanged && !licenseChanged
                  ? (adminBlocked
                        ? 'Igreja bloqueada pelo master.'
                        : 'Igreja liberada — bloqueio removido.')
                  : modoFree
                  ? 'Igreja configurada como FREE.'
                  : 'Plano e licença salvos com sucesso.',
            ),
          );
          await _loadChurchesList(force: true);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                formatFirebaseErrorForUser(e, logToCrashlytics: false),
              ),
              backgroundColor: ThemeCleanPremium.error,
            ),
          );
        }
      } finally {
        if (sheetCtx.mounted) setModal(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      // Quase tela cheia: o painel de licença tem preview, plano, ciclo,
      // vencimento, bloqueio e exclusão — na altura antiga metade ficava por
      // baixo da dobra e o botão de voltar nem se via.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final previewGuard = SubscriptionGuard.evaluate(
              church: {
                ...ig,
                'plano': modoFree ? 'free' : planoSel,
                'planId': modoFree ? 'free' : planoSel,
                'isFree': modoFree,
                'adminBlocked': adminBlocked,
                'billingCycle': ciclo,
                if (!modoFree && venc != null) ...{
                  'licenseExpiresAt': Timestamp.fromDate(venc!),
                  'data_vencimento': Timestamp.fromDate(venc!),
                },
                'license': {
                  ...lic,
                  'isFree': modoFree,
                  'adminBlocked': adminBlocked,
                },
              },
            );

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.cardBackground,
                  borderRadius: BorderRadius.circular(
                    ThemeCleanPremium.radiusLg,
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  'ID: $igrejaId',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _paymentChipColor(
                            previewGuard,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusMd,
                          ),
                          border: Border.all(
                            color: _paymentChipColor(
                              previewGuard,
                            ).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              modoFree
                                  ? Icons.volunteer_activism_rounded
                                  : Icons.verified_rounded,
                              color: _paymentChipColor(previewGuard),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    previewGuard.masterBadgeLabel,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _paymentChipColor(previewGuard),
                                    ),
                                  ),
                                  Text(
                                    modoFree
                                        ? 'Acesso gratuito — sem cobrança automática.'
                                        : venc != null
                                        ? 'Vencimento: ${DateFormat('dd/MM/yyyy').format(venc!)}'
                                        : 'Defina a data de vencimento.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Tipo de licença',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              avatar: Icon(
                                Icons.volunteer_activism_rounded,
                                size: 18,
                                color: modoFree
                                    ? ThemeCleanPremium.primary
                                    : Colors.grey,
                              ),
                              label: const Text('FREE'),
                              selected: modoFree,
                              onSelected: widget.canEdit
                                  ? (sel) {
                                      if (sel) {
                                        setModal(() => modoFree = true);
                                      }
                                    }
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              avatar: Icon(
                                Icons.payments_rounded,
                                size: 18,
                                color: !modoFree
                                    ? ThemeCleanPremium.primary
                                    : Colors.grey,
                              ),
                              label: const Text('Plano pago'),
                              selected: !modoFree,
                              onSelected: widget.canEdit
                                  ? (sel) {
                                      if (sel) {
                                        setModal(() {
                                          modoFree = false;
                                          venc ??=
                                              BillingLicenseService.licensePeriodEndFrom(
                                                DateTime.now(),
                                                ciclo,
                                              );
                                        });
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      if (!modoFree) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Plano manual',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: planoSel,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: planosOficiais
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.name),
                                ),
                              )
                              .toList(),
                          onChanged: widget.canEdit
                              ? (v) => setModal(() => planoSel = v ?? planoSel)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ciclo de cobrança',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: Text(
                                  'Mensal (${BillingLicenseService.licensePeriodDaysMonthly}d)',
                                ),
                                selected: ciclo == 'monthly',
                                onSelected: widget.canEdit
                                    ? (sel) {
                                        if (sel) {
                                          setModal(() => ciclo = 'monthly');
                                        }
                                      }
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: Text(
                                  'Anual (${BillingLicenseService.licensePeriodDaysAnnual}d)',
                                ),
                                selected: ciclo == 'annual',
                                onSelected: widget.canEdit
                                    ? (sel) {
                                        if (sel) {
                                          setModal(() => ciclo = 'annual');
                                        }
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm,
                            ),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Data de vencimento',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      venc != null
                                          ? DateFormat(
                                              'dd/MM/yyyy',
                                            ).format(venc!)
                                          : 'Obrigatória para plano pago',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: venc != null
                                            ? ThemeCleanPremium.onSurface
                                            : ThemeCleanPremium.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Escolher data',
                                icon: const Icon(Icons.calendar_month_rounded),
                                onPressed: widget.canEdit
                                    ? () async {
                                        final d = await showDatePicker(
                                          context: ctx,
                                          initialDate:
                                              venc ??
                                              BillingLicenseService.licensePeriodEndFrom(
                                                DateTime.now(),
                                                ciclo,
                                              ),
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime(2040),
                                        );
                                        if (d != null) {
                                          setModal(() => venc = d);
                                        }
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: widget.canEdit
                                  ? () {
                                      setModal(() {
                                        venc =
                                            BillingLicenseService.licensePeriodEndFrom(
                                              DateTime.now(),
                                              ciclo,
                                            );
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.today_rounded, size: 18),
                              label: Text(
                                ciclo == 'annual'
                                    ? '+${BillingLicenseService.licensePeriodDaysAnnual} dias'
                                    : '+${BillingLicenseService.licensePeriodDaysMonthly} dias',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: widget.canEdit
                                  ? () => setModal(() => venc = null)
                                  : null,
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              label: const Text('Limpar data'),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Text(
                          'Igreja gratuita: sem vencimento nem cobrança Mercado Pago. '
                          'O gestor usa o painel normalmente (salvo bloqueio manual).',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const Divider(height: 28),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bloquear igreja (master)'),
                        subtitle: const Text(
                          'Gestor vê apenas tela de renovação',
                        ),
                        value: adminBlocked,
                        onChanged: widget.canEdit
                            ? (v) => setModal(() => adminBlocked = v)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: modoFree
                              ? const Color(0xFF0D9488)
                              : const Color(0xFF4F46E5),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: widget.canEdit && !saving
                            ? () => persistLicense(ctx, setModal)
                            : null,
                        icon: saving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          saving
                              ? 'Salvando…'
                              : modoFree
                              ? 'Salvar licença FREE'
                              : 'Salvar plano e vencimento',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: widget.canEdit
                            ? () async {
                                // Passa pela Cloud Function. A versão anterior
                                // apagava coleção a coleção a partir do
                                // cliente e as regras negavam
                                // (`permission-denied`) — além de nunca tocar
                                // no Storage.
                                final apagou = await confirmAndDeleteChurch(
                                  context: ctx,
                                  tenantId: igrejaId,
                                  churchName: nome,
                                );
                                if (!apagou) return;
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) setState(() {});
                              }
                            : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: ThemeCleanPremium.error,
                          backgroundColor: ThemeCleanPremium.error.withValues(
                            alpha: 0.07,
                          ),
                          side: BorderSide(
                            color: ThemeCleanPremium.error.withValues(
                              alpha: 0.40,
                            ),
                          ),
                        ),
                        icon: const Icon(
                          Icons.delete_forever_rounded,
                          color: ThemeCleanPremium.error,
                        ),
                        label: const Text(
                          'Excluir igreja (Firestore + Storage)',
                          style: TextStyle(
                            color: ThemeCleanPremium.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: ThemeCleanPremium.onSurfaceVariant,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Voltar sem alterar'),
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
      isNarrow ? ThemeCleanPremium.spaceSm : ThemeCleanPremium.spaceMd,
    );

    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Builder(
            builder: (context) {
              if (_churchesLoadError != null && _churches.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Erro ao carregar igrejas: $_churchesLoadError',
                          style: TextStyle(color: ThemeCleanPremium.error),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _loadChurchesList(force: true),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (_churchesLoading && _churches.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              final allDocs = _churches;
              final docs = allDocs.where(_passesFilters).toList();
              final benchKey = docs.take(20).map((e) => e.id).join('|');
              final benchmarkCacheValid =
                  _benchmarkFetchedAt != null &&
                  DateTime.now().difference(_benchmarkFetchedAt!) <
                      _benchmarkCacheTtl;
              if (_benchmarkRequested &&
                  (_benchmarkFuture == null ||
                      _benchmarkKey != benchKey ||
                      !benchmarkCacheValid)) {
                _benchmarkKey = benchKey;
                _benchmarkFuture = _loadBenchmark(docs);
                _benchmarkFetchedAt = DateTime.now();
              }
              final summary = _masterSummary;
              final total = summary?.igrejas ?? allDocs.length;
              final ativas = summary != null
                  ? (summary.licencasAtivas > 0
                        ? summary.licencasAtivas
                        : allDocs
                              .where(
                                (d) =>
                                    (d.data['status'] ?? 'ativa').toString() ==
                                    'ativa',
                              )
                              .length)
                  : allDocs
                        .where(
                          (d) =>
                              (d.data['status'] ?? 'ativa').toString() ==
                              'ativa',
                        )
                        .length;
              final inativas =
                  summary?.blockedCount ??
                  allDocs
                      .where(
                        (d) => (d.data['status'] ?? '').toString() == 'inativa',
                      )
                      .length;
              final novasMes = allDocs.where((d) {
                final data = d.data['createdAt'] ?? d.data['dataCadastro'];
                if (data is Timestamp) {
                  final now = DateTime.now();
                  final dt = data.toDate();
                  return dt.month == now.month && dt.year == now.year;
                }
                return false;
              }).length;

              final billing = BillingLicenseService();
              final healthWithoutLogo = allDocs.where((d) {
                final ig = d.data;
                final logo =
                    ChurchBrandService.logoPathFromData(ig, churchId: d.id) ??
                    '';
                return logo.isEmpty;
              }).length;
              final healthWithoutVideo = allDocs.where((d) {
                final ig = d.data;
                return !_hasInstitutionalVideo(ig);
              }).length;
              final mediaBroken = allDocs.where((d) {
                final ig = d.data;
                final logo =
                    ChurchBrandService.logoPathFromData(ig, churchId: d.id) ??
                    '';
                final video =
                    (ig['institutionalVideoUrl'] ??
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
                final ig = d.data;
                final inativa =
                    (ig['status'] ?? 'ativa').toString().toLowerCase() ==
                    'inativa';
                final guard = SubscriptionGuard.evaluate(church: ig);
                return inativa || guard.blocked || guard.adminBlocked;
              }).length;
              final healthInGrace = allDocs
                  .where(
                    (d) => SubscriptionGuard.evaluate(church: d.data).inGrace,
                  )
                  .length;
              final healthBlocked = allDocs
                  .where(
                    (d) => SubscriptionGuard.evaluate(church: d.data).blocked,
                  )
                  .length;
              final dueSoon = allDocs.where((d) {
                final guard = SubscriptionGuard.evaluate(church: d.data);
                if (guard.blocked || guard.adminBlocked || guard.isFree) {
                  return false;
                }
                final venc = guard.dataVencimento;
                if (venc == null) return false;
                final days = venc.difference(DateTime.now()).inDays;
                return days >= 0 && days <= 7;
              }).length;
              final now = DateTime.now();
              final chargeCandidates =
                  allDocs.where((d) {
                    final guard = SubscriptionGuard.evaluate(church: d.data);
                    if (guard.blocked ||
                        guard.inGrace ||
                        guard.statusAssinatura == 'overdue') {
                      return true;
                    }
                    final exp = guard.dataVencimento;
                    if (exp == null) return false;
                    final days = exp.difference(now).inDays;
                    return days >= 0 && days <= 7;
                  }).toList()..sort((a, b) {
                    final ga = SubscriptionGuard.evaluate(church: a.data);
                    final gb = SubscriptionGuard.evaluate(church: b.data);
                    final da = ga.dataVencimento ?? DateTime(2099);
                    final dbb = gb.dataVencimento ?? DateTime(2099);
                    return da.compareTo(dbb);
                  });

              return RefreshIndicator(
                onRefresh: _loadChurchesList,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
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
                                  vertical: ThemeCleanPremium.spaceSm,
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const MercadoPagoAdminPage(),
                                  ),
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
                                      label: 'Inativas',
                                      value: inativas,
                                    ),
                                    _MetricCard(
                                      label: 'Novas mês',
                                      value: novasMes,
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _MetricCard(label: 'Total', value: total),
                                    _MetricCard(label: 'Ativas', value: ativas),
                                    _MetricCard(
                                      label: 'Inativas',
                                      value: inativas,
                                    ),
                                    _MetricCard(
                                      label: 'Novas mês',
                                      value: novasMes,
                                    ),
                                  ],
                                ),
                          const SizedBox(height: 16),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Saúde dos tenants (visão única)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      _MetricCard(
                                        label: 'Sem logo',
                                        value: healthWithoutLogo,
                                      ),
                                      _MetricCard(
                                        label: 'Sem vídeo',
                                        value: healthWithoutVideo,
                                      ),
                                      _MetricCard(
                                        label: 'Mídia quebrada',
                                        value: mediaBroken,
                                      ),
                                      _MetricCard(
                                        label: 'Site indisponível',
                                        value: siteUnavailable,
                                      ),
                                      _MetricCard(
                                        label: 'Vencimento próximo',
                                        value: dueSoon,
                                      ),
                                      _MetricCard(
                                        label: 'Em carência',
                                        value: healthInGrace,
                                      ),
                                      _MetricCard(
                                        label: 'Bloqueadas',
                                        value: healthBlocked,
                                      ),
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
                                ThemeCleanPremium.radiusMd,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Benchmark entre igrejas (SaaS)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (!_benchmarkRequested)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: docs.isEmpty
                                            ? null
                                            : () => setState(
                                                () =>
                                                    _benchmarkRequested = true,
                                              ),
                                        icon: const Icon(
                                          Icons.insights_rounded,
                                        ),
                                        label: const Text(
                                          'Carregar benchmark (opcional)',
                                        ),
                                      ),
                                    )
                                  else
                                    FutureBuilder<List<_BenchmarkTenant>>(
                                      future: _benchmarkFuture,
                                      builder: (context, benchSnap) {
                                        if (!benchSnap.hasData) {
                                          return const Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: LinearProgressIndicator(),
                                          );
                                        }
                                        final rows = benchSnap.data!;
                                        if (rows.isEmpty) {
                                          return Text(
                                            'Sem dados suficientes ainda para benchmark.',
                                            style: TextStyle(
                                              color: ThemeCleanPremium
                                                  .onSurfaceVariant,
                                            ),
                                          );
                                        }
                                        return Column(
                                          children: rows.take(6).map((r) {
                                            final conv =
                                                (r.conversionRate * 100)
                                                    .toStringAsFixed(1);
                                            final approval =
                                                r.avgApprovalHours == null
                                                ? 'n/d'
                                                : '${r.avgApprovalHours!.toStringAsFixed(1)}h';
                                            return ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons.insights_rounded,
                                              ),
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
                                ThemeCleanPremium.radiusMd,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cobrança inteligente (vencendo / em atraso)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (chargeCandidates.isEmpty)
                                    Text(
                                      'Nenhuma igreja com cobrança prioritária agora.',
                                      style: TextStyle(
                                        color:
                                            ThemeCleanPremium.onSurfaceVariant,
                                      ),
                                    )
                                  else
                                    ...chargeCandidates.take(6).map((d) {
                                      final ig = d.data;
                                      final nome =
                                          (ig['nome'] ?? ig['name'] ?? d.id)
                                              .toString();
                                      final guard = SubscriptionGuard.evaluate(
                                        church: ig,
                                      );
                                      final exp = guard.dataVencimento;
                                      final due = exp != null
                                          ? DateFormat('dd/MM').format(exp)
                                          : '—';
                                      return ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.notifications_active_rounded,
                                          color: _paymentChipColor(guard),
                                        ),
                                        title: Text(
                                          nome,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          'Status: ${guard.masterBadgeLabel} • Venc.: $due',
                                          style: TextStyle(
                                            color: ThemeCleanPremium
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Cobrar no WhatsApp',
                                          icon: const Icon(Icons.chat_rounded),
                                          onPressed: () => _openChargeWhatsapp(
                                            context,
                                            ig,
                                            d.id,
                                          ),
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
                                ThemeCleanPremium.radiusMd,
                              ),
                            ),
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
                                                await Navigator.of(context)
                                                    .push<void>(
                                                      MaterialPageRoute<void>(
                                                        builder: (_) =>
                                                            const MasterNovaIgrejaPage(),
                                                      ),
                                                    );
                                              }
                                            : null,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Nova igreja'),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      initialValue: _filterStatus.isEmpty
                                          ? null
                                          : _filterStatus,
                                      decoration: const InputDecoration(
                                        labelText: 'Status',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: null,
                                          child: Text('Todos'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'ativa',
                                          child: Text('Ativa'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'inativa',
                                          child: Text('Inativa'),
                                        ),
                                      ],
                                      onChanged: (v) => setState(
                                        () => _filterStatus = v ?? '',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: _filterPlano.isEmpty
                                          ? null
                                          : _filterPlano,
                                      decoration: const InputDecoration(
                                        labelText: 'Plano',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: null,
                                          child: Text('Todos'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'free',
                                          child: Text('Free'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'pago',
                                          child: Text('Pagos'),
                                        ),
                                      ],
                                      onChanged: (v) => setState(
                                        () => _filterPlano = v ?? '',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ChoiceChip(
                                          label: const Text('Ativas'),
                                          selected: _paymentFilter == 'active',
                                          onSelected: (_) => setState(
                                            () => _paymentFilter =
                                                _paymentFilter == 'active'
                                                ? ''
                                                : 'active',
                                          ),
                                        ),
                                        ChoiceChip(
                                          label: const Text(
                                            'Em atraso (carência)',
                                          ),
                                          selected: _paymentFilter == 'grace',
                                          onSelected: (_) => setState(
                                            () => _paymentFilter =
                                                _paymentFilter == 'grace'
                                                ? ''
                                                : 'grace',
                                          ),
                                        ),
                                        ChoiceChip(
                                          label: const Text('Bloqueadas'),
                                          selected: _paymentFilter == 'blocked',
                                          onSelected: (_) => setState(
                                            () => _paymentFilter =
                                                _paymentFilter == 'blocked'
                                                ? ''
                                                : 'blocked',
                                          ),
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
                                                  await Navigator.of(context)
                                                      .push<void>(
                                                        MaterialPageRoute<void>(
                                                          builder: (_) =>
                                                              const MasterNovaIgrejaPage(),
                                                        ),
                                                      );
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
                                          child:
                                              DropdownButtonFormField<String>(
                                                initialValue:
                                                    _filterStatus.isEmpty
                                                    ? null
                                                    : _filterStatus,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Status',
                                                    ),
                                                items: const [
                                                  DropdownMenuItem(
                                                    value: null,
                                                    child: Text('Todos'),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'ativa',
                                                    child: Text('Ativa'),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'inativa',
                                                    child: Text('Inativa'),
                                                  ),
                                                ],
                                                onChanged: (v) => setState(
                                                  () => _filterStatus = v ?? '',
                                                ),
                                              ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child:
                                              DropdownButtonFormField<String>(
                                                initialValue:
                                                    _filterPlano.isEmpty
                                                    ? null
                                                    : _filterPlano,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Plano',
                                                    ),
                                                items: const [
                                                  DropdownMenuItem(
                                                    value: null,
                                                    child: Text('Todos'),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'free',
                                                    child: Text('Free'),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'pago',
                                                    child: Text('Pagos'),
                                                  ),
                                                ],
                                                onChanged: (v) => setState(
                                                  () => _filterPlano = v ?? '',
                                                ),
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
                                          onSelected: (_) => setState(
                                            () => _paymentFilter =
                                                _paymentFilter == 'active'
                                                ? ''
                                                : 'active',
                                          ),
                                        ),
                                        ChoiceChip(
                                          label: const Text(
                                            'Em atraso (carência)',
                                          ),
                                          selected: _paymentFilter == 'grace',
                                          onSelected: (_) => setState(
                                            () => _paymentFilter =
                                                _paymentFilter == 'grace'
                                                ? ''
                                                : 'grace',
                                          ),
                                        ),
                                        ChoiceChip(
                                          label: const Text('Bloqueadas'),
                                          selected: _paymentFilter == 'blocked',
                                          onSelected: (_) => setState(
                                            () => _paymentFilter =
                                                _paymentFilter == 'blocked'
                                                ? ''
                                                : 'blocked',
                                          ),
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
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
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
                              Icon(
                                Icons.church_rounded,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                allDocs.isEmpty
                                    ? 'Nenhuma igreja cadastrada.'
                                    : 'Nenhum resultado com os filtros atuais.',
                                style: TextStyle(
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final doc = docs[i];
                          final ig = doc.data;
                          final igrejaId = doc.id;
                          final guard = SubscriptionGuard.evaluate(church: ig);
                          final status = (ig['status'] ?? 'ativa').toString();
                          final removed = ig['removedByAdminAt'] != null;
                          var licenseExpiresAt =
                              ig['licenseExpiresAt'] is Timestamp
                              ? (ig['licenseExpiresAt'] as Timestamp).toDate()
                              : null;
                          if (licenseExpiresAt == null &&
                              ig['license'] is Map) {
                            final lic = ig['license'] as Map;
                            final exp = lic['expiresAt'];
                            if (exp is Timestamp) {
                              licenseExpiresAt = exp.toDate();
                            }
                          }
                          final now = DateTime.now();
                          final hasActiveLicense =
                              licenseExpiresAt != null &&
                              licenseExpiresAt.isAfter(now);
                          final daysLeft = licenseExpiresAt
                              ?.difference(now)
                              .inDays;
                          final plano = (ig['plano'] ?? ig['planId'] ?? '—')
                              .toString();
                          final adminB = ig['adminBlocked'] == true;
                          final licMap = ig['license'] is Map
                              ? ig['license'] as Map
                              : null;
                          final adminB2 = licMap?['adminBlocked'] == true;
                          String validadeStr = '';
                          if (licenseExpiresAt != null) {
                            validadeStr =
                                'Venc.: ${DateFormat('dd/MM/yyyy').format(licenseExpiresAt)}';
                            if (hasActiveLicense && daysLeft != null) {
                              validadeStr += ' (${daysLeft}d)';
                            }
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
                              _acaoPill(
                                icon: Icons.admin_panel_settings_rounded,
                                label: 'Licença',
                                tooltip: 'Licença, FREE, bloqueio, exclusão',
                                cor: const Color(0xFF4F46E5),
                                onTap: () => _abrirGestaoLicenca(
                                  context,
                                  igrejaId: igrejaId,
                                  nome: nome,
                                  ig: ig,
                                ),
                              ),
                            if (widget.canEdit && !removed && plano != 'free')
                              _acaoPill(
                                icon: Icons.date_range_rounded,
                                label: '+15d',
                                tooltip: 'Prorrogar 15 dias',
                                cor: const Color(0xFF0D9488),
                                onTap: () => _runTenantAction(
                                  context,
                                  action: () =>
                                      billing.prorrogarTenant(igrejaId, 15),
                                  successMessage: 'Prazo +15 dias.',
                                ),
                              ),
                            if (widget.canEdit && !removed && plano != 'free')
                              _acaoPill(
                                icon: Icons.card_giftcard_rounded,
                                label: 'Bônus',
                                tooltip: 'Bônus de 7 dias',
                                cor: const Color(0xFFDB2777),
                                onTap: () => _runTenantAction(
                                  context,
                                  action: () =>
                                      billing.prorrogarTenant(igrejaId, 7),
                                  successMessage:
                                      'Bônus aplicado: +7 dias de licença.',
                                ),
                              ),
                            if (widget.canEdit && removed)
                              _acaoPill(
                                icon: Icons.person_add_rounded,
                                label: 'Reativar',
                                tooltip: 'Reativar igreja',
                                cor: const Color(0xFF16A34A),
                                onTap: () => _runTenantAction(
                                  context,
                                  action: () =>
                                      billing.reativarTenant(igrejaId),
                                  successMessage: 'Igreja reativada.',
                                ),
                              ),
                            if (widget.canEdit && !removed)
                              _acaoPill(
                                icon: Icons.person_remove_rounded,
                                label: 'Remover',
                                tooltip: 'Remover acesso (reversível)',
                                cor: const Color(0xFFD97706),
                                onTap: () async {
                                  final ok = await _confirmarModerno(
                                    context,
                                    titulo: 'Remover igreja',
                                    mensagem:
                                        'Remover "$nome"? O acesso é suspenso '
                                        'e pode ser reativado a qualquer '
                                        'momento — nenhum dado é apagado.',
                                    icone: Icons.person_remove_rounded,
                                    cor: const Color(0xFFD97706),
                                    confirmar: 'Remover',
                                  );
                                  if (ok && context.mounted) {
                                    await _runTenantAction(
                                      context,
                                      action: () =>
                                          billing.removerTenant(igrejaId),
                                      successMessage:
                                          'Igreja removida (reversível).',
                                    );
                                  }
                                },
                              ),
                            _acaoPill(
                              icon: Icons.info_outline_rounded,
                              label: 'Detalhes',
                              tooltip: 'Ver todos os dados da igreja',
                              cor: const Color(0xFF2563EB),
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) =>
                                      _DetalhesIgrejaDialog(igreja: ig),
                                );
                              },
                            ),
                            if (widget.canEdit)
                              _acaoPill(
                                icon: Icons.edit_rounded,
                                label: 'Editar',
                                tooltip: 'Editar cadastro da igreja',
                                cor: const Color(0xFF7C3AED),
                                onTap: () async {
                                  await showDialog<void>(
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
                            MasterChurchPublicationButton(
                              churchId: igrejaId,
                              data: ig,
                              canEdit: widget.canEdit,
                            ),
                            MasterChurchNoticeButton(
                              churchId: igrejaId,
                              canEdit: widget.canEdit,
                            ),
                            _acaoPill(
                              icon: Icons.open_in_full_rounded,
                              label: 'Veja mais',
                              tooltip: 'Abrir a igreja em tela cheia',
                              cor: const Color(0xFF0F766E),
                              destacado: true,
                              onTap: () async {
                                // Tela cheia: membros, líderes, gestores,
                                // dados, armazenamento, links e ações.
                                await Navigator.of(context).push<bool>(
                                  MaterialPageRoute<bool>(
                                    fullscreenDialog: true,
                                    builder: (_) => MasterChurchOverviewPage(
                                      tenantId: igrejaId,
                                      initialData: ig,
                                    ),
                                  ),
                                );
                                if (context.mounted) {
                                  await _loadChurchesList(force: true);
                                }
                              },
                            ),
                          ];
                          return _MasterIgrejaCard(
                            accent: _paymentChipColor(guard),
                            isNarrow: isNarrow,
                            logo: _MasterChurchListLogo(
                              churchId: igrejaId,
                              data: ig,
                            ),
                            nome: nome,
                            igrejaId: igrejaId,
                            paymentLabel: guard.masterBadgeLabel,
                            plano: plano,
                            validadeStr: validadeStr,
                            status: status,
                            responsavel: responsavel,
                            graceDaysLeft: guard.inGrace
                                ? guard.graceDaysLeft
                                : null,
                            blocked: adminB || adminB2,
                            removed: removed,
                            actions: actionButtons,
                          );
                        }, childCount: docs.length),
                      ),
                  ],
                ),
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

/// Miniatura da logo na lista Master (path canónico `igrejas/{id}/…`).
class _MasterChurchListLogo extends StatelessWidget {
  const _MasterChurchListLogo({required this.churchId, required this.data});

  final String churchId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final path = ChurchBrandService.logoPathFromData(data, churchId: churchId);
    final url = (data['logoUrl'] ?? data['urlLogo'] ?? '').toString().trim();
    final hasUrl = url.startsWith('http');
    final hasPath = path != null && path.trim().isNotEmpty;

    final placeholder = CircleAvatar(
      radius: 22,
      backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.12),
      child: Icon(
        Icons.church_rounded,
        color: ThemeCleanPremium.primary,
        size: 26,
      ),
    );

    if (!hasPath && !hasUrl) return placeholder;

    return ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: StableStorageImage(
          storagePath: hasPath ? path : null,
          imageUrl: hasUrl ? url : null,
          fit: BoxFit.cover,
          width: 44,
          height: 44,
          placeholder: placeholder,
          errorWidget: placeholder,
        ),
      ),
    );
  }
}

/// Pílula compacta de estado usada no cartão de igreja do painel master.
class _MasterChip extends StatelessWidget {
  const _MasterChip({
    required this.label,
    required this.color,
    this.icon,
    this.strong = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: icon == null ? 10 : 8,
        right: 10,
        top: 4,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: strong ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.1,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de igreja da Lista Igrejas (painel master).
///
/// Modernizado: faixa de estado colorida, nome completo em duas linhas (antes
/// truncava no meio), estado em pílulas legíveis (pagamento/plano/vencimento/
/// gestor/bloqueio) e barra de ações agrupada numa superfície própria.
class _MasterIgrejaCard extends StatelessWidget {
  const _MasterIgrejaCard({
    required this.accent,
    required this.isNarrow,
    required this.logo,
    required this.nome,
    required this.igrejaId,
    required this.paymentLabel,
    required this.plano,
    required this.validadeStr,
    required this.status,
    required this.responsavel,
    required this.graceDaysLeft,
    required this.blocked,
    required this.removed,
    required this.actions,
  });

  final Color accent;
  final bool isNarrow;
  final Widget logo;
  final String nome;
  final String igrejaId;
  final String paymentLabel;
  final String plano;
  final String validadeStr;
  final String status;
  final String responsavel;
  final int? graceDaysLeft;
  final bool blocked;
  final bool removed;
  final List<Widget> actions;

  static const Color _planColor = Color(0xFF4F46E5);
  static const Color _neutral = Color(0xFF64748B);
  static const Color _warn = Color(0xFFD97706);

  List<Widget> _chips() {
    final chips = <Widget>[
      _MasterChip(
        label: paymentLabel,
        color: accent,
        icon: Icons.verified_rounded,
        strong: true,
      ),
      _MasterChip(
        label: plano.trim().isEmpty || plano == '—' ? 'Sem plano' : plano,
        color: _planColor,
        icon: Icons.workspace_premium_rounded,
      ),
      if (validadeStr.trim().isNotEmpty && validadeStr != '—')
        _MasterChip(
          label: validadeStr,
          color: _neutral,
          icon: Icons.event_available_rounded,
        ),
      if (responsavel.trim().isNotEmpty)
        _MasterChip(
          label: responsavel.trim(),
          color: _neutral,
          icon: Icons.person_rounded,
        ),
      if (status.trim().isNotEmpty)
        _MasterChip(
          label: status,
          color: status.toLowerCase() == 'ativa'
              ? ThemeCleanPremium.success
              : _neutral,
          icon: Icons.toggle_on_rounded,
        ),
    ];
    final grace = graceDaysLeft;
    if (grace != null) {
      chips.add(
        _MasterChip(
          label: 'Carência: ${grace}d',
          color: _warn,
          icon: Icons.hourglass_bottom_rounded,
        ),
      );
    }
    if (blocked) {
      chips.add(
        const _MasterChip(
          label: 'BLOQUEADA',
          color: ThemeCleanPremium.error,
          icon: Icons.lock_rounded,
          strong: true,
        ),
      );
    }
    if (removed) {
      chips.add(
        const _MasterChip(
          label: 'Removida',
          color: _neutral,
          icon: Icons.delete_outline_rounded,
        ),
      );
    }
    return chips;
  }

  Widget _actionBar() {
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: actions,
      ),
    );
    if (!isNarrow) return bar;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: bar);
  }

  Widget _idRow(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.tag_rounded, size: 14, color: _neutral),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            igrejaId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: _neutral,
            ),
          ),
        ),
        const SizedBox(width: 2),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            Clipboard.setData(ClipboardData(text: igrejaId));
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar('ID da igreja copiado.'),
            );
          },
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.copy_rounded, size: 14, color: _neutral),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nome,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15.5,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        _idRow(context),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: _chips()),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [accent, accent.withValues(alpha: 0.40)],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              logo,
                              const SizedBox(width: 12),
                              Expanded(child: info),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _actionBar(),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          logo,
                          const SizedBox(width: 12),
                          Expanded(child: info),
                          const SizedBox(width: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 470),
                            child: _actionBar(),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
