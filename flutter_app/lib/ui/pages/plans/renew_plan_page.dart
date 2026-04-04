import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/billing_service.dart';
import 'package:gestao_yahweh/services/payment_ui_feedback_service.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/mp_checkout_embed.dart';
import '../../widgets/primary_button.dart';

String _money(double v) =>
    'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

class RenewPlanPage extends StatefulWidget {
  /// Quando true (ex.: bloqueio de licença no shell), não exibe AppBar próprio.
  final bool embeddedInShell;

  const RenewPlanPage({super.key, this.embeddedInShell = false});

  @override
  State<RenewPlanPage> createState() => _RenewPlanPageState();
}

class _RenewPlanPageState extends State<RenewPlanPage> {
  String _selected = planosOficiais.first.id;
  bool _loading = false;
  String? _err;
  bool _billingAnnual = false;
  bool _paymentPix = true;
  Map<String, ({double? monthly, double? annual})>? _effectivePrices;
  /// Quando não nulo, exibe o checkout Mercado Pago na mesma tela (WebView / iframe).
  MpCheckoutSession? _checkoutSession;
  /// Quando não nulo, exibe PIX pronto com QR e copia-e-cola.
  MpPixSession? _pixSession;

  final _billing = BillingService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _churchBillingSub;
  String? _watchingTenantId;
  bool _paymentApprovedRedirected = false;
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

  Future<String?> _resolveTenantIdFromClaims() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final token = await user.getIdTokenResult(true);
    final tenantId = (token.claims?['igrejaId'] ?? token.claims?['tenantId'] ?? '')
        .toString()
        .trim();
    return tenantId.isEmpty ? null : tenantId;
  }

  void _handlePaymentApprovedAutoReturn() {
    if (!mounted || _paymentApprovedRedirected) return;
    _paymentApprovedRedirected = true;
    PaymentUiFeedbackService.notifyPaymentConfirmed();
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
    final tenantId = await _resolveTenantIdFromClaims();
    if (tenantId == null || tenantId.isEmpty) return;
    _watchingTenantId = tenantId;
    _churchBillingSub = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .snapshots()
        .listen((snap) {
      _applyChurchBillingSnapshot(snap.data());
    }, onError: (_) {});
  }

  @override
  void initState() {
    super.initState();
    _loadPrices();
    _startPaymentStatusWatcher();
  }

  @override
  void dispose() {
    _churchBillingSub?.cancel();
    _churchBillingSub = null;
    super.dispose();
  }

  Future<void> _loadPrices() async {
    final prices = await PlanPriceService.getEffectivePrices();
    if (mounted) setState(() => _effectivePrices = prices);
  }

  PlanoOficial get _selectedPlan =>
      planosOficiais.firstWhere((p) => p.id == _selected, orElse: () => planosOficiais.first);

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

  Future<void> _startSubscription() async {
    setState(() {
      _loading = true;
      _err = null;
      _checkoutSession = null;
      _pixSession = null;
    });
    try {
      if (_paymentPix) {
        final pix = await _billing.createMpPixPayment(
          planId: _selected,
          billingCycle: _billingAnnual ? BillingCycle.annual : BillingCycle.monthly,
        );
        if (!pix.isValid) throw 'Não foi possível gerar o PIX.';
        if (!mounted) return;
        setState(() => _pixSession = pix);
      } else {
        // Mensal: cartão em 1x. Anual: cartão em até 10x.
        final installments = _billingAnnual ? 10 : 1;
        final session = await _billing.createMpCheckout(
          planId: _selected,
          billingCycle: _billingAnnual ? BillingCycle.annual : BillingCycle.monthly,
          paymentMethod: PaymentMethod.card,
          installments: installments,
        );
        if (!session.isValid) throw 'Não foi possível abrir o checkout.';
        if (!mounted) return;
        setState(() => _checkoutSession = session);
      }
    } catch (e) {
      String msg = _parseBillingError(e);
      setState(() => _err = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = ThemeCleanPremium.isMobile(context);
    final pad = ThemeCleanPremium.pagePadding(context);

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
                              await Clipboard.setData(ClipboardData(text: px.qrCode));
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
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
                            child: MpCheckoutEmbed(
                              checkoutUrl: _checkoutSession!.initPoint,
                              returnUrlHint: _checkoutSession!.backUrl,
                              onLikelyFinished: _onCheckoutLikelyFinished,
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text(
                    'Planos oficiais',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Todos os módulos inclusos. O que muda é a escala de uso.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: planosOficiais.map((p) {
                      final ep = _effectivePrices?[p.id];
                      return SizedBox(
                        width: isMobile ? double.infinity : 280,
                        child: _PlanCardOficial(
                          plan: p,
                          selected: p.id == _selected,
                          onTap: () => setState(() => _selected = p.id),
                          priceMonthly: ep?.monthly ?? p.monthlyPrice,
                          priceAnnual: ep?.annual ?? p.annualPrice,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
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
                          onTap: () => setState(() {
                            _billingAnnual = false;
                          }),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : (constraints.maxWidth - 12) / 2,
                        child: _ChoiceChip(
                          label: 'Anual',
                          selected: _billingAnnual,
                          onTap: () => setState(() {
                            _billingAnnual = true;
                          }),
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
                          onTap: () => setState(() => _paymentPix = true),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : (constraints.maxWidth - 12) / 2,
                        child: _ChoiceChip(
                          label: _billingAnnual ? 'Cartão em 10x' : 'Cartão (1x)',
                          icon: Icons.credit_card_rounded,
                          selected: !_paymentPix,
                          onTap: () => setState(() => _paymentPix = false),
                          enabled: true,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _billingAnnual
                          ? 'Anual: PIX à vista ou cartão parcelado em até 10x.'
                          : 'Mensal: uma cobrança — PIX ou cartão à vista (1x).',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
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
                  const SizedBox(height: 24),
                  PrimaryButton(
                    text: _paymentPix ? 'Pagar com PIX' : 'Pagar com Cartão',
                    icon: _paymentPix ? Icons.qr_code_2_rounded : Icons.credit_card_rounded,
                    loading: _loading,
                    onPressed: _startSubscription,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _activate,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Ativar plano (demo)'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '${_selectedPlan.name} • ${_billingAnnual ? "Anual" : "Mensal"} • ${_paymentPix ? "PIX" : (_billingAnnual ? "Cartão 10x" : "Cartão 1x")}',
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
          ),
        );
        },
      ),
    ),
    );

    if (widget.embeddedInShell) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assinatura — Escolha seu plano'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: _loading ? null : _onFecharPressed,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
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

  const _PlanCardOficial({
    required this.plan,
    required this.selected,
    required this.onTap,
    this.priceMonthly,
    this.priceAnnual,
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
                  : (plan.featured ? cs.primary.withOpacity(0.6) : const Color(0xFFE5EAF3)),
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
                  color: cs.primary.withOpacity(0.15),
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
                        color: cs.primary.withOpacity(0.1),
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
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
      child: Opacity(
        opacity: isDisabled ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withOpacity(0.12) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            border: Border.all(
              color: selected ? cs.primary : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: selected ? cs.primary : Colors.grey.shade700),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.primary : Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
