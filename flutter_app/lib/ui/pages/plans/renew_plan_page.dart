import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/license_access_policy.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/billing_service.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/express_renew_bootstrap.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/services/payment_ui_feedback_service.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart' show EffectivePlanConfig, PlanPriceService;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/ios_payment_unavailable_view.dart';
import '../../widgets/mp_checkout_embed.dart';
import '../../widgets/primary_button.dart';
import 'package:gestao_yahweh/utils/mp_web_checkout_redirect.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

String _money(double v) =>
    'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

enum _ExpressPayStep { options, confirm }

class RenewPlanPage extends StatefulWidget {
  /// Quando true (ex.: bloqueio de licença no shell), não exibe AppBar próprio.
  final bool embeddedInShell;

  /// Modo «atualizar plano expresso» — fluxo abreviado para usuário vindo do
  /// app iOS via `/atualizar-plano`:
  ///   - Cabeçalho mostra plano atual + data de vencimento.
  ///   - CTA «Ir para pagamento» fica fixo no topo após selecionar plano.
  ///   - Esconde o botão «Ativar plano (demo)».
  ///   - Após pagamento confirmado, exibe tela final com link «voltar ao app»
  ///     em vez de redirecionar para `/painel`.
  final bool expressMode;

  /// Modo expresso: rota relativa enviada ao Cloud Function para o `back_url`
  /// do Mercado Pago (ex.: `/atualizar-plano?from=ios_app`).
  final String? expressCheckoutReturnPath;

  /// Papel no painel (gestor, secretário, tesoureiro…) — gate de pagamento de licença.
  final String? panelRole;

  const RenewPlanPage({
    super.key,
    this.embeddedInShell = false,
    this.expressMode = false,
    this.expressCheckoutReturnPath,
    this.panelRole,
  });

  @override
  State<RenewPlanPage> createState() => _RenewPlanPageState();
}

class _RenewPlanPageState extends State<RenewPlanPage> {
  String _selected = planosOficiais.first.id;
  bool _loading = false;
  String? _err;
  bool _billingAnnual = false;
  bool _paymentPix = true;
  Map<String, EffectivePlanConfig>? _effectiveConfigs;
  /// Quando não nulo, exibe o checkout Mercado Pago na mesma tela (WebView / iframe).
  MpCheckoutSession? _checkoutSession;
  /// Quando não nulo, exibe PIX pronto com QR e copia-e-cola.
  MpPixSession? _pixSession;

  final _billing = BillingService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _churchBillingSub;
  StreamSubscription<User?>? _idTokenRefreshSub;
  StreamSubscription<Map<String, EffectivePlanConfig>>? _planPricesSub;
  bool _paymentApprovedRedirected = false;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _paymentSectionKey = GlobalKey();
  /// Parcelas no cartão (anual + cartão): 1 a 6.
  int _expressCardInstallments = 1;

  /// Safari iOS / modo expresso: opções → confirmação antes do Mercado Pago.
  _ExpressPayStep _expressPayStep = _ExpressPayStep.options;
  String? _prefetchKey;
  MpCheckoutSession? _prefetchedCheckout;
  String? _pixPrefetchKey;
  MpPixSession? _prefetchedPix;

  /// Modo expresso — última versão do doc da igreja (para mostrar plano
  /// atual + data de vencimento no cabeçalho).
  Map<String, dynamic>? _churchData;

  /// Modo expresso — exibe a tela final «Pagamento confirmado» em vez de
  /// redirecionar (já que o utilizador veio do site público / iPhone).
  bool _expressPaymentDone = false;
  String _resolvedPanelRole = 'membro';
  /// Primeiro snapshot só estabelece linha de base — evita "pagamento confirmado" ao abrir Planos com licença já paga.
  bool _billingBaselineEstablished = false;
  bool _wasBillingPaidAtBaseline = false;
  /// Na web o 1º snapshot pode vir sem `billing` (cache/rede); esperar o mapa evita falso "unpaid → paid".
  /// Assinatura do estado de cobrança na linha de base (mp|sub|lastPaymentMs).
  String _baselinePaymentSig = '';

  void _closeCheckout() {
    setState(() {
      _checkoutSession = null;
      _pixSession = null;
    });
  }

  void _scrollPaymentSectionIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _paymentSectionKey.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.12,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _parseBillingError(dynamic e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'unauthenticated':
          return 'Faça login novamente para continuar.';
        case 'failed-precondition':
        case 'invalid-argument':
          return e.message ?? 'Verifique os dados e tente novamente.';
        case 'not-found':
          return 'Plano não encontrado. Tente novamente ou use "Ativar plano (demo)".';
        case 'internal':
          final m = e.message ?? e.details?.toString() ?? '';
          if (m.contains('payer') || m.contains('email')) {
            return 'Configure um e-mail de contato na igreja e tente novamente.';
          }
          if (m.contains('MP API') || m.contains('mercadopago')) {
            return 'Falha temporária no gateway de pagamento. Tente em instantes.';
          }
          return m.isNotEmpty && m.length < 120 ? m : 'Erro ao processar pagamento. Tente novamente ou use outra forma de pagamento.';
        default:
          return e.message ?? 'Erro: ${e.code}';
      }
    }
    String msg = e.toString().replaceAll('Exception:', '').trim();
    if (msg.contains('not-found') && msg.contains('Plano')) {
      return 'Plano não encontrado no servidor. Tente novamente.';
    }
    if (msg.contains('internal') || msg.contains('firebase_functions')) {
      return 'Erro ao processar pagamento. Tente novamente ou escolha outra forma de pagamento.';
    }
    return msg.length > 100 ? 'Erro ao processar. Tente novamente.' : msg;
  }

  /// Sai da assinatura: só [Navigator.pop] se houver rota acima — evita [pushNamedAndRemoveUntil](..., (_) => false) que “reinicia” o app.
  void _exitRenewPage() {
    if (!mounted) return;
    if (widget.embeddedInShell) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed('/painel');
    }
  }

  void _onFecharPressed() {
    if (_checkoutSession != null) {
      _closeCheckout();
      return;
    }
    _exitRenewPage();
  }

  void _onCheckoutLikelyFinished(String url) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Retorno do pagamento detectado. A licença atualiza em segundos via confirmação automática.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() => _checkoutSession = null);
    if (widget.embeddedInShell) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(true);
    }
  }

  bool _isBillingStatusPaid(Map<String, dynamic>? church) {
    if (church == null) return false;
    final billing = church['billing'] is Map
        ? Map<String, dynamic>.from(church['billing'] as Map)
        : <String, dynamic>{};
    return (billing['status'] ?? '').toString().toLowerCase() == 'paid';
  }

  /// Evidência gravada pelo webhook do Mercado Pago (`mpPaymentId` / `subscriptionId` + provider).
  bool _billingEvidenceMercadoPagoPaid(Map<String, dynamic>? church) {
    if (church == null) return false;
    final billing = church['billing'] is Map
        ? Map<String, dynamic>.from(church['billing'] as Map)
        : <String, dynamic>{};
    if ((billing['status'] ?? '').toString().toLowerCase() != 'paid') return false;
    final mpId = (billing['mpPaymentId'] ?? '').toString().trim();
    if (mpId.isNotEmpty) return true;
    final provider = (billing['provider'] ?? '').toString().toLowerCase();
    if (!provider.contains('mercado')) return false;
    final subId = (billing['subscriptionId'] ?? '').toString().trim();
    return subId.isNotEmpty;
  }

  String _billingPaymentSignature(Map<String, dynamic> church) {
    final billing = church['billing'] is Map
        ? Map<String, dynamic>.from(church['billing'] as Map)
        : <String, dynamic>{};
    final mp = (billing['mpPaymentId'] ?? '').toString().trim();
    final sub = (billing['subscriptionId'] ?? '').toString().trim();
    final lp = billing['lastPaymentAt'];
    final lpPart = lp is Timestamp ? lp.millisecondsSinceEpoch.toString() : '';
    return '$mp|$sub|$lpPart';
  }

  void _applyChurchBillingSnapshot(Map<String, dynamic>? data) {
    if (!mounted) return;
    if (data == null) return;
    // Modo expresso: guardar para o cabeçalho — mesmo sem `billing` ainda.
    if (widget.expressMode) {
      setState(() => _churchData = data);
    }
    // Sem `billing` ainda: não fixar linha de base (evita falso unpaid→paid no 2º evento na web).
    if (data['billing'] is! Map) return;

    final nowPaid = _isBillingStatusPaid(data);
    if (!_billingBaselineEstablished) {
      _baselinePaymentSig = _billingPaymentSignature(data);
      _billingBaselineEstablished = true;
      _wasBillingPaidAtBaseline = nowPaid;
      return;
    }
    final transitionedToPaid = !_wasBillingPaidAtBaseline && nowPaid;
    final newSig = _billingPaymentSignature(data);
    final paymentProofChanged =
        newSig != _baselinePaymentSig && newSig.replaceAll('|', '').trim().isNotEmpty;

    if (transitionedToPaid &&
        _billingEvidenceMercadoPagoPaid(data) &&
        paymentProofChanged) {
      _handlePaymentApprovedAutoReturn();
      _wasBillingPaidAtBaseline = true;
      _baselinePaymentSig = newSig;
      return;
    }
    if (nowPaid) _wasBillingPaidAtBaseline = true;
  }

  Future<String?> _resolveTenantIdFromClaims({bool forceRefresh = false}) async {
    return ExpressRenewBootstrap.instance.resolveTenantId(
      forceRefresh: forceRefresh,
    );
  }

  /// Confirmação + prefetch antes do MP: web, Android e `/atualizar-plano`.
  bool get _usesAnnualCardConfirmFlow {
    if (widget.expressMode) return true;
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.android) return true;
    return false;
  }

  String get _currentPrefetchKey =>
      '$_selected|${_billingAnnual ? "a" : "m"}|${_expressCardInstallments.clamp(1, 6)}';

  String get _currentPixPrefetchKey =>
      '$_selected|${_billingAnnual ? "a" : "m"}';

  void _invalidatePaymentPrefetch() {
    _prefetchKey = null;
    _prefetchedCheckout = null;
    _pixPrefetchKey = null;
    _prefetchedPix = null;
  }

  void _schedulePaymentPrefetch() {
    // Pagamento MP só após toque explícito em «Gerar pagamento» / «Confirmar e pagar».
  }

  Future<void> _schedulePixPrefetch() async {
    if (!_paymentPix) return;
    final key = _currentPixPrefetchKey;
    if (_prefetchedPix != null && _pixPrefetchKey == key) return;
    _pixPrefetchKey = key;
    _prefetchedPix = null;
    try {
      final pix = await _billing.createMpPixPayment(
        planId: _selected,
        billingCycle:
            _billingAnnual ? BillingCycle.annual : BillingCycle.monthly,
      );
      if (!mounted) return;
      if (_pixPrefetchKey != key) return;
      if (pix.isValid) {
        setState(() => _prefetchedPix = pix);
      }
    } catch (_) {}
  }

  void _backToPaymentOptions() {
    setState(() {
      _expressPayStep = _ExpressPayStep.options;
      _err = null;
      _invalidatePaymentPrefetch();
    });
    _schedulePaymentPrefetch();
    _scrollPaymentSectionIntoView();
  }

  void _goToCardConfirmStep() {
    if (!_usesAnnualCardConfirmFlow || _paymentPix) return;
    setState(() {
      _expressPayStep = _ExpressPayStep.confirm;
      _err = null;
    });
    _schedulePaymentPrefetch();
    _scrollPaymentSectionIntoView();
  }

  void _onSelectPix() {
    setState(() {
      _paymentPix = true;
      _expressPayStep = _ExpressPayStep.options;
      _err = null;
      _invalidatePaymentPrefetch();
    });
    _schedulePaymentPrefetch();
  }

  void _onSelectCard() {
    setState(() {
      _paymentPix = false;
      _expressPayStep = _ExpressPayStep.options;
      _err = null;
      _invalidatePaymentPrefetch();
    });
    if (_usesAnnualCardConfirmFlow && !_billingAnnual) {
      _goToCardConfirmStep();
    } else {
      _schedulePaymentPrefetch();
      _scrollPaymentSectionIntoView();
    }
  }

  void _onSelectInstallment(int n) {
    setState(() {
      _expressCardInstallments = n;
      _invalidatePaymentPrefetch();
    });
    if (_usesAnnualCardConfirmFlow) {
      _goToCardConfirmStep();
    } else {
      _schedulePaymentPrefetch();
    }
  }

  Future<void> _scheduleCheckoutPrefetch({bool requireConfirmFlow = true}) async {
    if (_paymentPix) return;
    if (requireConfirmFlow) {
      if (!_usesAnnualCardConfirmFlow) return;
      if (_expressPayStep != _ExpressPayStep.confirm) return;
    }
    final key = _currentPrefetchKey;
    if (_prefetchedCheckout != null && _prefetchKey == key) return;
    _prefetchKey = key;
    _prefetchedCheckout = null;
    try {
      final returnPath = widget.expressMode
          ? (widget.expressCheckoutReturnPath ?? '/atualizar-plano')
          : '/painel';
      final session = await _billing.createMpCheckout(
        planId: _selected,
        billingCycle:
            _billingAnnual ? BillingCycle.annual : BillingCycle.monthly,
        paymentMethod: PaymentMethod.card,
        installments: _billingAnnual
            ? _expressCardInstallments.clamp(1, 6)
            : 1,
        returnPath: returnPath,
      );
      if (!mounted) return;
      if (_prefetchKey != key) return;
      if (session.isValid) {
        setState(() => _prefetchedCheckout = session);
      }
    } catch (_) {}
  }

  void _handlePaymentApprovedAutoReturn() {
    if (!mounted || _paymentApprovedRedirected) return;
    _paymentApprovedRedirected = true;
    PaymentUiFeedbackService.notifyPaymentConfirmed();
    // Modo expresso: NÃO sair da tela — mostrar confirmação inline para o
    // utilizador voltar ao app iPhone manualmente (não tem painel aberto).
    if (widget.expressMode) {
      setState(() {
        _expressPaymentDone = true;
        _checkoutSession = null;
        _pixSession = null;
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pagamento confirmado. Retornando ao painel principal...'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (widget.embeddedInShell) {
        // O shell escuta `igrejas/{id}` e deixa o modo só-renovação quando a licença atualizar.
        // Reiniciar `/painel` aqui recria o gate com perfil antigo e pode manter o utilizador preso.
        return;
      }
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(true);
      } else {
        nav.pushNamedAndRemoveUntil('/painel', (_) => false);
      }
    });
  }

  Future<void> _startPaymentStatusWatcher() async {
    if (_churchBillingSub != null) return;
    var tenantId = ExpressRenewBootstrap.instance.cachedTenantId;
    tenantId ??= await _resolveTenantIdFromClaims();
    if (tenantId == null || tenantId.isEmpty) return;
    final op = ChurchRepository.churchId(tenantId.trim());
    _churchBillingSub =         ChurchUiCollections.churchDoc(op)
        .watchSafe()
        .listen((snap) {
      _applyChurchBillingSnapshot(snap.data());
    }, onError: (_) {});
  }

  /// Claims podem chegar segundos após o login — reabre o listener do doc da igreja.
  Future<void> _retryPaymentWatcherIfNeeded() async {
    if (_churchBillingSub != null) return;
    await _startPaymentStatusWatcher();
  }

  @override
  void initState() {
    super.initState();
    final hint = (widget.panelRole ?? '').trim().toLowerCase();
    if (hint.isNotEmpty) _resolvedPanelRole = hint;
    unawaited(_resolvePanelRoleFromAuth());
    final boot = ExpressRenewBootstrap.instance;
    final cachedPlans = boot.cachedPlans;
    if (cachedPlans != null) {
      _effectiveConfigs = cachedPlans;
    }
    final cachedChurch = boot.cachedChurchData;
    if (cachedChurch != null) {
      _churchData = cachedChurch;
      _applyChurchBillingSnapshot(cachedChurch);
    }
    unawaited(boot.warmUp().then((_) {
      if (!mounted) return;
      final plans = boot.cachedPlans;
      final church = boot.cachedChurchData;
      if (plans != null || church != null) {
        setState(() {
          if (plans != null) _effectiveConfigs = plans;
          if (church != null) _churchData = church;
        });
        if (church != null) _applyChurchBillingSnapshot(church);
      }
    }));
    _planPricesSub =
        PlanPriceService.watchEffectivePlanConfigs().listen((cfg) {
      if (mounted) setState(() => _effectiveConfigs = cfg);
    });
    _startPaymentStatusWatcher();
    _idTokenRefreshSub = FirebaseAuth.instance.idTokenChanges().listen((_) {
      unawaited(_retryPaymentWatcherIfNeeded());
    });
  }

  @override
  void dispose() {
    _planPricesSub?.cancel();
    _planPricesSub = null;
    _idTokenRefreshSub?.cancel();
    _idTokenRefreshSub = null;
    _churchBillingSub?.cancel();
    _churchBillingSub = null;
    _scrollController.dispose();
    super.dispose();
  }

  PlanoOficial get _selectedPlan {
    final cfg = _effectiveConfigs?[_selected];
    if (cfg != null) return cfg.toPlanoOficial();
    return planosOficiais.firstWhere(
      (p) => p.id == _selected,
      orElse: () => planosOficiais.first,
    );
  }

  String _confirmPanelHint() {
    if (kIsWeb && mpWebCheckoutPrefersSameTabRedirect) {
      return 'Ao confirmar, abrimos a página segura do Mercado Pago neste separador. '
          'Depois do pagamento você volta automaticamente ao Gestão YAHWEH e a licença '
          'anual é atualizada em instantes.';
    }
    if (kIsWeb) {
      return 'Ao confirmar, o checkout seguro do Mercado Pago abre nesta página. '
          'Após o pagamento, a licença anual da igreja é renovada automaticamente.';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'Ao confirmar, o checkout do Mercado Pago abre no app. '
          'Quando o pagamento for aprovado, a licença anual é liberada em instantes.';
    }
    return 'Revise os dados e confirme para abrir o checkout seguro do Mercado Pago.';
  }

  double? _selectedCyclePrice() {
    final cfg = _effectiveConfigs?[_selected];
    if (_billingAnnual) {
      final a = cfg?.annualPrice;
      if (a != null && a > 0) return a;
      final m = cfg?.monthlyPrice ?? _selectedPlan.monthlyPrice;
      if (m != null && m > 0) return m * 12;
      return _selectedPlan.annualPrice;
    }
    return cfg?.monthlyPrice ?? _selectedPlan.monthlyPrice;
  }

  Widget _buildExpressConfirmPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = _selectedCyclePrice();
    final inst = _billingAnnual
        ? _expressCardInstallments.clamp(1, 6)
        : 1;
    final parcelHint = _billingAnnual && inst > 1
        ? ' (${inst}x no cartão — total ${_money(price ?? 0)})'
        : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, color: cs.primary, size: 26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Confirmar pagamento',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_selectedPlan.name} • ${_billingAnnual ? "Anual" : "Mensal"} • '
            'Cartão ${inst}x$parcelHint',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              height: 1.35,
            ),
          ),
          if (price != null && price > 0) ...[
            const SizedBox(height: 8),
            Text(
              _money(price),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: cs.primary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _confirmPanelHint(),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            text: 'Confirmar e pagar',
            icon: Icons.lock_rounded,
            loading: _loading,
            onPressed: _startSubscription,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _loading ? null : _backToPaymentOptions,
              child: const Text('Alterar plano ou parcelas'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------- Modo expresso: cabeçalho ----------------------

  String? _currentPlanLabel() {
    final church = _churchData;
    if (church == null) return null;
    final raw = (church['planId'] ?? church['plano'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    PlanoOficial? found;
    for (final p in planosOficiais) {
      if (p.id.toLowerCase() == raw.toLowerCase()) {
        found = p;
        break;
      }
    }
    return found?.name ?? raw;
  }

  String? _currentPlanExpiryLabel() {
    final church = _churchData;
    if (church == null) return null;
    final end = LicenseAccessPolicy.churchAccessEnd(church);
    if (end == null) return null;
    final fmt = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();
    final days = end.difference(now).inDays;
    if (end.isBefore(now)) {
      final overdue = now.difference(end).inDays;
      return overdue <= 0
          ? 'Vence hoje'
          : 'Venceu há $overdue dia${overdue == 1 ? '' : 's'} (${fmt.format(end)})';
    }
    if (days <= 7) {
      return 'Vence em $days dia${days == 1 ? '' : 's'} (${fmt.format(end)})';
    }
    return 'Vence em ${fmt.format(end)}';
  }

  Widget _buildExpressHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final planLabel = _currentPlanLabel();
    final expiry = _currentPlanExpiryLabel();
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = (user?.email ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Atualizar plano',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (planLabel != null)
            _ExpressInfoRow(
              icon: Icons.verified_user_outlined,
              label: 'Plano atual',
              value: planLabel,
            ),
          if (expiry != null)
            _ExpressInfoRow(
              icon: Icons.event_outlined,
              label: 'Vencimento',
              value: expiry,
            ),
          if (userEmail.isNotEmpty)
            _ExpressInfoRow(
              icon: Icons.account_circle_outlined,
              label: 'Conta',
              value: userEmail,
            ),
          if (planLabel == null && expiry == null && userEmail.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Carregando dados da igreja…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------- Modo expresso: tela final ----------------------

  Widget _buildExpressDoneView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFA7F3D0), width: 2),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                child: const Center(
                  child: Icon(Icons.check_circle_rounded,
                      color: Color(0xFF047857), size: 64),
                ),
              ),
              const Center(
                child: Text(
                  'Pagamento confirmado!',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Seu plano foi atualizado com sucesso. Agora você pode '
                'voltar ao aplicativo Gestão YAHWEH no seu celular — o novo '
                'plano já está ativo na sua conta.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade800, height: 1.4),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/painel', (_) => false),
                icon: const Icon(Icons.dashboard_rounded),
                label: const Text('Abrir o painel agora'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (_) => false),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Voltar ao site'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Pode ser necessário reabrir o app no celular para que o '
                  'novo plano apareça imediatamente.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _activate() async {
    setState(() { _loading = true; _err = null; });
    try {
      await _billing.activatePlanDemo(_selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plano ativado (modo demo).')),
      );
      if (widget.embeddedInShell) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(true);
      } else {
        nav.pushReplacementNamed('/painel');
      }
    } catch (e) {
      setState(() => _err = _parseBillingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCardCheckout(MpCheckoutSession session) async {
    if (!session.isValid) throw 'Não foi possível abrir o checkout.';
    if (!mounted) return;
    if (kIsWeb && mpWebCheckoutPrefersSameTabRedirect) {
      setState(() => _loading = false);
      mpWebRedirectSameTab(session.initPoint);
      return;
    }
    if (IosPaymentsGate.preferExternalMercadoPagoCheckout) {
      setState(() => _loading = false);
      final uri = Uri.tryParse(session.initPoint);
      if (uri == null) throw 'Link do Mercado Pago inválido.';
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        throw 'Não foi possível abrir o navegador. Tente novamente.';
      }
      return;
    }
    setState(() => _checkoutSession = session);
  }

  Future<void> _startSubscription() async {
    if (!widget.expressMode && !_canPurchaseLicense) {
      setState(() => _err =
          'Somente gestor, secretário ou tesoureiro pode gerar o pagamento.');
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
      _checkoutSession = null;
      _pixSession = null;
    });
    try {
      var tenantId = ExpressRenewBootstrap.instance.cachedTenantId;
      tenantId ??= await _resolveTenantIdFromClaims();
      if (tenantId == null || tenantId.isEmpty) {
        throw 'Sua sessão ainda não está vinculada a uma igreja. '
            'Saia, entre de novo com a conta de gestor e aguarde alguns segundos.';
      }
      if (_paymentPix) {
        final pix = await _billing.createMpPixPayment(
          planId: _selected,
          billingCycle: _billingAnnual
              ? BillingCycle.annual
              : BillingCycle.monthly,
        );
        if (!pix.isValid) throw 'Não foi possível gerar o PIX.';
        if (!mounted) return;
        setState(() => _pixSession = pix);
      } else {
        // Mensal: 1x. Anual + cartão: 1–6x à escolha do gestor.
        final int installments = _billingAnnual
            ? _expressCardInstallments.clamp(1, 6)
            : 1;
        final String? returnPath;
        if (widget.expressMode) {
          returnPath =
              widget.expressCheckoutReturnPath ?? '/atualizar-plano';
        } else if (kIsWeb && mpWebCheckoutPrefersSameTabRedirect) {
          returnPath = '/painel';
        } else {
          returnPath = null;
        }
        final session = await _billing.createMpCheckout(
          planId: _selected,
          billingCycle: _billingAnnual
              ? BillingCycle.annual
              : BillingCycle.monthly,
          paymentMethod: PaymentMethod.card,
          installments: installments,
          returnPath: returnPath,
        );
        await _openCardCheckout(session);
      }
    } catch (e) {
      String msg = _parseBillingError(e);
      setState(() => _err = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolvePanelRoleFromAuth() async {
    if ((widget.panelRole ?? '').trim().isNotEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdTokenResult();
      final claims = token.claims ?? {};
      final role = (claims['role'] ?? claims['nivel'] ?? claims['perfil'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (role.isNotEmpty && mounted) {
        setState(() => _resolvedPanelRole = role);
      }
    } catch (_) {}
  }

  String get _effectivePanelRole {
    final fromWidget = (widget.panelRole ?? '').trim().toLowerCase();
    if (fromWidget.isNotEmpty) return fromWidget;
    return _resolvedPanelRole;
  }

  bool get _canPurchaseLicense =>
      AppPermissions.canPurchaseChurchLicense(_effectivePanelRole);

  Widget _buildLicensePaymentForbidden(BuildContext context) {
    return Scaffold(
      appBar: widget.embeddedInShell
          ? null
          : AppBar(title: const Text('Licença da igreja')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 56, color: Colors.grey.shade600),
                const SizedBox(height: 16),
                Text(
                  'Renovação só pela liderança',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Somente o gestor, secretário ou tesoureiro da igreja pode '
                  'gerar o pagamento da licença. Peça a um deles para abrir '
                  '«Adquirir plano» e confirmar o pagamento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _exitRenewPage,
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Apple Guideline 3.1.1 — em iOS com `exibir_pagamento_ios=false` o app se
    // comporta como Reader/SaaS: sem precos, sem botoes de cobranca direta.
    // No modo expresso (vindo do site público) a flag não se aplica — esse
    // fluxo só roda na web, onde o pagamento é permitido.
    if (!widget.expressMode && !_canPurchaseLicense) {
      return _buildLicensePaymentForbidden(context);
    }
    if (!widget.expressMode && IosPaymentsGate.shouldHidePayments) {
      return IosPaymentUnavailableView(embedded: widget.embeddedInShell);
    }

    final cs = Theme.of(context).colorScheme;
    final isMobile = ThemeCleanPremium.isMobile(context);
    final pad = ThemeCleanPremium.pagePadding(context);

    // Modo expresso — pós-pagamento: tela final dedicada (não volta ao painel).
    if (widget.expressMode && _expressPaymentDone) {
      final doneBody = SafeArea(child: AppShell(padding: pad, child: _buildExpressDoneView(context)));
      if (widget.embeddedInShell) return doneBody;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Pagamento confirmado'),
          backgroundColor: ThemeCleanPremium.primary,
          foregroundColor: Colors.white,
        ),
        body: doneBody,
      );
    }

    final body = SafeArea(
      child: AppShell(
      padding: pad,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_pixSession != null) {
            final px = _pixSession!;
            final screenH = MediaQuery.sizeOf(context).height;
            final isSmallMobile = MediaQuery.sizeOf(context).width < 520;
            final qrBytes = px.qrCodeBase64.isNotEmpty ? base64Decode(px.qrCodeBase64) : null;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  child: Container(
                    margin: EdgeInsets.only(bottom: isSmallMobile ? 16 : 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Voltar',
                              onPressed: _loading ? null : _closeCheckout,
                              icon: const Icon(Icons.arrow_back_rounded),
                              constraints: BoxConstraints(
                                minWidth: ThemeCleanPremium.minTouchTarget,
                                minHeight: ThemeCleanPremium.minTouchTarget,
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'PIX gerado',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Copie e pague',
                                style: TextStyle(
                                  color: Color(0xFF047857),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Abra o app do banco, escaneie o QR Code ou use o código copia-e-cola abaixo.',
                          style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: Container(
                            height: isSmallMobile ? math.min(220, screenH * 0.28) : 250,
                            width: isSmallMobile ? math.min(220, screenH * 0.28) : 250,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: qrBytes != null
                                ? Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Image.memory(qrBytes, fit: BoxFit.contain),
                                  )
                                : const Center(
                                    child: Icon(Icons.qr_code_2_rounded, size: 84, color: Colors.black54),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          px.qrCode,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await Clipboard.setData(ClipboardData(text: px.qrCode));
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Código PIX copiado.'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copiar código PIX'),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _startSubscription,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Gerar novo PIX'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Assim que o pagamento for confirmado, o sistema retorna automaticamente para o painel principal.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          if (_checkoutSession != null) {
            final screenH = MediaQuery.sizeOf(context).height;
            final checkoutH = math.max(isMobile ? 520.0 : 440.0, math.min(screenH * (isMobile ? 0.76 : 0.68), 780.0));
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      elevation: 0,
                      shadowColor: Colors.black12,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Voltar',
                              onPressed: _loading ? null : _closeCheckout,
                              icon: const Icon(Icons.arrow_back_rounded),
                              constraints: BoxConstraints(
                                minWidth: ThemeCleanPremium.minTouchTarget,
                                minHeight: ThemeCleanPremium.minTouchTarget,
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'Concluir pagamento',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: checkoutH,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        elevation: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 30,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child:                             MpCheckoutEmbed(
                              checkoutUrl: _checkoutSession!.initPoint,
                              returnUrlHint: _checkoutSession!.backUrl,
                              onLikelyFinished: _onCheckoutLikelyFinished,
                              footerHint: widget.expressMode
                                  ? 'PIX ou cartão nesta página — padrão Super Premium e mais rápido. '
                                      'Não o leva para o site do Mercado Pago: o checkout abre aqui embebido; '
                                      'o processamento continua seguro com o Mercado Pago em segundo plano.'
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return SingleChildScrollView(
            controller: _scrollController,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  if (widget.expressMode) ...[
                    _buildExpressHeader(context),
                    const SizedBox(height: 18),
                  ],
                  Text(
                    widget.expressMode
                        ? 'Escolha o plano que melhor atende sua igreja'
                        : 'Planos oficiais',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.expressMode
                        ? (kIsWeb
                            ? (mpWebCheckoutPrefersSameTabRedirect
                                ? 'Selecione plano, ciclo e forma de pagamento. '
                                    'No iPhone (Safari), o cartão abre no Mercado Pago; '
                                    'o PIX fica nesta página. Anual no cartão: até 6x.'
                                : 'Selecione plano e ciclo. Anual no cartão em até 6x; '
                                    'após confirmar, o checkout abre nesta página.')
                            : 'Selecione plano e ciclo. Anual no cartão em até 6x; '
                                'a licença renova automaticamente após o pagamento.')
                        : (kIsWeb || defaultTargetPlatform == TargetPlatform.android)
                            ? 'Todos os módulos inclusos. Anual: PIX à vista ou cartão em até 6x '
                                '(confirme antes de pagar). A licença atualiza após aprovação.'
                            : 'Todos os módulos inclusos. O que muda é a escala de uso.',
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: planosOficiais.map((p) {
                      final cfg = _effectiveConfigs?[p.id];
                      final display = cfg?.toPlanoOficial() ?? p;
                      return SizedBox(
                        width: isMobile ? double.infinity : 280,
                        child: _PlanCardOficial(
                          plan: display,
                          selected: p.id == _selected,
                          onTap: () {
                            setState(() {
                              _selected = p.id;
                              _expressPayStep = _ExpressPayStep.options;
                              _invalidatePaymentPrefetch();
                            });
                            _schedulePaymentPrefetch();
                          },
                          priceMonthly: cfg?.monthlyPrice ?? p.monthlyPrice,
                          priceAnnual: cfg?.annualPrice ?? p.annualPrice,
                          onChooseMonthly: () {
                            setState(() {
                              _selected = p.id;
                              _billingAnnual = false;
                              _expressCardInstallments = 1;
                              _expressPayStep = _ExpressPayStep.options;
                              _invalidatePaymentPrefetch();
                            });
                            _schedulePaymentPrefetch();
                            _scrollPaymentSectionIntoView();
                          },
                          onChooseAnnual: () {
                            setState(() {
                              _selected = p.id;
                              _billingAnnual = true;
                              _expressCardInstallments =
                                  _expressCardInstallments.clamp(1, 6);
                              _expressPayStep = _ExpressPayStep.options;
                              _invalidatePaymentPrefetch();
                            });
                            _schedulePaymentPrefetch();
                            _scrollPaymentSectionIntoView();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  KeyedSubtree(
                    key: _paymentSectionKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  const Text(
                    'Ciclo de cobrança',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : (constraints.maxWidth - 12) / 2,
                        child: _ChoiceChip(
                          label: 'Mensal',
                          selected: !_billingAnnual,
                          onTap: () {
                            setState(() {
                              _billingAnnual = false;
                              _expressCardInstallments = 1;
                              _expressPayStep = _ExpressPayStep.options;
                              _invalidatePaymentPrefetch();
                            });
                            _schedulePaymentPrefetch();
                          },
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : (constraints.maxWidth - 12) / 2,
                        child: _ChoiceChip(
                          label: 'Anual',
                          selected: _billingAnnual,
                          onTap: () {
                            setState(() {
                              _billingAnnual = true;
                              _expressCardInstallments =
                                  _expressCardInstallments.clamp(1, 6);
                              _expressPayStep = _ExpressPayStep.options;
                              _invalidatePaymentPrefetch();
                            });
                            _schedulePaymentPrefetch();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Forma de pagamento',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : (constraints.maxWidth - 12) / 2,
                        child: _ChoiceChip(
                          label: 'PIX',
                          icon: Icons.qr_code_2_rounded,
                          selected: _paymentPix,
                          onTap: _onSelectPix,
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : (constraints.maxWidth - 12) / 2,
                        child: _ChoiceChip(
                          label: _billingAnnual
                              ? 'Cartão (até 6x)'
                              : 'Cartão (1x)',
                          icon: Icons.credit_card_rounded,
                          selected: !_paymentPix,
                          onTap: _onSelectCard,
                          enabled: true,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _billingAnnual
                          ? 'Anual: PIX à vista ou cartão em até 6x — escolha as parcelas abaixo.'
                          : 'Mensal: uma cobrança — PIX ou cartão à vista (1x).',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  if (kIsWeb && !_paymentPix) ...[
                    const SizedBox(height: 8),
                    Text(
                      mpWebCheckoutPrefersSameTabRedirect
                          ? 'No Safari do iPhone o cartão abre na página segura do Mercado Pago; '
                              'após o pagamento a licença anual volta ativa no Gestão YAHWEH.'
                          : 'No cartão anual (até 6x), confirme o resumo e pague; '
                              'a licença da igreja renova automaticamente após aprovação.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_billingAnnual &&
                      !_paymentPix &&
                      !(_usesAnnualCardConfirmFlow &&
                          _expressPayStep == _ExpressPayStep.confirm)) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Parcelas no cartão',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(6, (i) {
                        final n = i + 1;
                        final sel = _expressCardInstallments == n;
                        return FilterChip(
                          label: Text('${n}x'),
                          selected: sel,
                          onSelected: (_) => _onSelectInstallment(n),
                        );
                      }),
                    ),
                  ],
                  if (_usesAnnualCardConfirmFlow &&
                      !_paymentPix &&
                      _expressPayStep == _ExpressPayStep.confirm) ...[
                    const SizedBox(height: 20),
                    _buildExpressConfirmPanel(context),
                  ],
                  if (_err != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        border: Border.all(
                          color: ThemeCleanPremium.error.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 22,
                            color: ThemeCleanPremium.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _err!,
                              style: TextStyle(
                                color: ThemeCleanPremium.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_paymentPix ||
                      !_usesAnnualCardConfirmFlow ||
                      _expressPayStep == _ExpressPayStep.options) ...[
                    const SizedBox(height: 24),
                    PrimaryButton(
                      text: _paymentPix ? 'Pagar com PIX' : 'Pagar com Cartão',
                      icon: _paymentPix
                          ? Icons.qr_code_2_rounded
                          : Icons.credit_card_rounded,
                      loading: _loading,
                      onPressed: _startSubscription,
                    ),
                  ],
                  if (!widget.expressMode) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _activate,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Ativar plano (demo)'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 46),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '${_selectedPlan.name} • ${_billingAnnual ? "Anual" : "Mensal"} • ${_paymentPix ? "PIX" : (_billingAnnual ? "Cartão ${_expressCardInstallments.clamp(1, 6)}x" : "Cartão 1x")}',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    ),
    );

    if (widget.embeddedInShell) {
      return body;
    }
    final appBarTitle = widget.expressMode
        ? 'Atualizar plano'
        : 'Assinatura — Escolha seu plano';
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.expressMode,
        leading: widget.expressMode
            ? null
            : IconButton(
                tooltip: 'Voltar',
                onPressed: _loading ? null : _onFecharPressed,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        actions: widget.expressMode
            ? const [SizedBox.shrink()]
            : [
                TextButton(
                  onPressed: _loading ? null : _onFecharPressed,
                  child: Text(
                    'Fechar',
                    style: TextStyle(
                      color: ThemeCleanPremium.navSidebarAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
      ),
      body: body,
    );
  }
}

/// Card no mesmo estilo do site de divulgação (Planos oficiais), com estado de seleção.
/// [priceMonthly] e [priceAnnual] vêm do Firestore quando o master altera preços.
class _PlanCardOficial extends StatelessWidget {
  final PlanoOficial plan;
  final bool selected;
  final VoidCallback onTap;
  final double? priceMonthly;
  final double? priceAnnual;
  final VoidCallback? onChooseMonthly;
  final VoidCallback? onChooseAnnual;

  const _PlanCardOficial({
    required this.plan,
    required this.selected,
    required this.onTap,
    this.priceMonthly,
    this.priceAnnual,
    this.onChooseMonthly,
    this.onChooseAnnual,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : (plan.featured ? cs.primary.withValues(alpha: 0.6) : const Color(0xFFE5EAF3)),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x12000000),
                blurRadius: 16,
                offset: Offset(0, 10),
              ),
              if (selected)
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (plan.featured)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Recomendado',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                plan.members,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(
                (priceMonthly ?? plan.monthlyPrice) == null
                    ? (plan.note ?? 'Valor a combinar')
                    : '${_money((priceMonthly ?? plan.monthlyPrice)!)} / mês',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: plan.featured ? cs.primary : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              if ((priceAnnual ?? plan.annualPrice) != null)
                Text(
                  'Anual: ${_money((priceAnnual ?? plan.annualPrice)!)} (12 por 10)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              const SizedBox(height: 12),
              const Text(
                'App + Painel Web + Site público\n'
                'Eventos, escalas e financeiro\n'
                'Backups automáticos e segurança',
                style: TextStyle(color: Colors.black54, height: 1.35, fontSize: 12),
              ),
              if (onChooseMonthly != null && onChooseAnnual != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: onChooseMonthly,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Mensal',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: onChooseAnnual,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Anual',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Toque para ir ao pagamento (PIX ou cartão) no fim da página.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
              if (selected) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      'Selecionado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpressInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ExpressInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  const _ChoiceChip({
    required this.label,
    this.icon,
    required this.selected,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDisabled = !enabled || onTap == null;
    final radius = BorderRadius.circular(16);
    return Material(
      color: Colors.transparent,
      elevation: selected ? 3 : 0,
      shadowColor: selected ? cs.primary.withValues(alpha: 0.35) : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: radius,
        child: Opacity(
          opacity: isDisabled ? 0.55 : 1,
          child: Ink(
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary.withValues(alpha: 0.22),
                        const Color(0xFFE0F2FE),
                      ],
                    )
                  : null,
              color: selected ? null : Colors.grey.shade100,
              borderRadius: radius,
              border: Border.all(
                color: selected ? cs.primary : Colors.grey.shade300,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 22,
                      color: selected ? cs.primary : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 15,
                        letterSpacing: -0.2,
                        color: selected ? cs.primary : Colors.grey.shade800,
                      ),
                      overflow: TextOverflow.ellipsis,
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
}
