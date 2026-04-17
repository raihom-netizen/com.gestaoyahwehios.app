import 'dart:async' show unawaited;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intl/intl.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/widgets/mp_checkout_fullscreen_page.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/ui/widgets/donation_kind_selector_grid.dart';

/// Dízimos, ofertas e contribuições via PIX ou cartão (Checkout Pro Mercado Pago da igreja).
/// Só contas tesouraria **Mercado Pago** (323) entram na conciliação desta tela.
String _onlyDigits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

bool _isMercadoPagoTreasuryAccount(Map<String, dynamic> data) {
  final cod = (data['bancoCodigo'] ?? '').toString().trim();
  if (cod == '323') return true;
  final bn = (data['bancoNome'] ?? '').toString().toLowerCase();
  if (bn.contains('mercado pago')) return true;
  if ((data['seedPreset'] ?? '').toString() == 'tesouraria_mercado_pago') {
    return true;
  }
  final nome = (data['nome'] ?? '').toString().toLowerCase();
  if (nome.contains('mercado pago')) return true;
  return false;
}

/// URL de retorno após pagamento no Checkout Pro (Mercado Pago exige `https`).
String _churchPanelDonationReturnUrl() {
  if (kIsWeb) {
    final u = Uri.base;
    if (u.scheme == 'https') {
      return u.replace(fragment: '').toString();
    }
    if (u.scheme == 'http' &&
        (u.host == 'localhost' || u.host == '127.0.0.1')) {
      return '${AppConstants.publicWebBaseUrl}/';
    }
  }
  return '${AppConstants.publicWebBaseUrl}/';
}

class ChurchDonationsPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String? cpf;
  /// Dentro de [IgrejaCleanShell]: sem AppBar duplicada; abas “pill” no corpo.
  final bool embeddedInShell;

  const ChurchDonationsPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.cpf,
    this.embeddedInShell = false,
  });

  @override
  State<ChurchDonationsPage> createState() => _ChurchDonationsPageState();
}

class _ChurchDonationsPageState extends State<ChurchDonationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _valorCtrl = TextEditingController(text: formatBrCurrencyInitial(50));
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _contaId;
  bool _loadingContas = true;
  List<({String id, String nome})> _contas = [];
  bool _gerando = false;
  bool _pixMode = true;
  int _parcelas = 1;
  /// `dizimo` | `oferta` — enviado ao MP (metadata) e ao financeiro via webhook.
  String _donationKind = 'dizimo';
  String? _memberDocIdForDonation;
  String? _qrPayload;
  String? _paymentId;
  String? _checkoutEmbedUrl;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final u = FirebaseAuth.instance.currentUser;
    _nomeCtrl.text = u?.displayName ?? '';
    _emailCtrl.text = u?.email ?? '';
    _loadContas();
    unawaited(_bindMemberForDonation());
  }

  Future<void> _bindMemberForDonation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final q = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros')
          .where('authUid', isEqualTo: uid)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return;
      final doc = q.docs.first;
      final data = doc.data();
      final nome = (data['NOME_COMPLETO'] ?? data['NOME'] ?? data['nome'] ?? '')
          .toString()
          .trim();
      if (!mounted) return;
      if (nome.isNotEmpty && _nomeCtrl.text.trim().isEmpty) {
        setState(() => _nomeCtrl.text = nome);
      }
      setState(() => _memberDocIdForDonation = doc.id);
    } catch (_) {}
  }

  void _cancelarFluxoDoacao() {
    setState(() {
      _erro = null;
      _qrPayload = null;
      _paymentId = null;
      _checkoutEmbedUrl = null;
      _parcelas = 1;
      _pixMode = true;
    });
  }

  Future<void> _loadContas() async {
    setState(() {
      _loadingContas = true;
      _erro = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('contas')
          .orderBy('nome')
          .get();
      final list = snap.docs
          .where((d) => d.data()['ativo'] != false)
          .where((d) => _isMercadoPagoTreasuryAccount(d.data()))
          .map((d) => (id: d.id, nome: (d.data()['nome'] ?? '').toString()))
          .where((e) => e.nome.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _contas = list;
          _contaId = list.isNotEmpty ? list.first.id : null;
          _loadingContas = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingContas = false;
          _erro = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _valorCtrl.dispose();
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  InputDecoration _inputDec({
    required String label,
    IconData? icon,
    String? hint,
    String? prefixText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      prefixIcon: icon == null ? null : Icon(icon, size: 22),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.95),
          width: 1.6,
        ),
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade800,
        fontSize: 14,
      ),
    );
  }

  Future<void> _gerarPix() async {
    final v = parseBrCurrencyInput(_valorCtrl.text);
    if (v < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe um valor válido (mínimo R\$ 1,00).')),
      );
      return;
    }
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do doador ou membro.')),
      );
      return;
    }
    setState(() {
      _gerando = true;
      _qrPayload = null;
      _paymentId = null;
      _erro = null;
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createChurchDonationPix');
      final res = await callable.call(<String, dynamic>{
        'tenantId': widget.tenantId,
        'amount': v,
        'donorName': nome,
        'payerEmail': _emailCtrl.text.trim(),
        'contaDestinoId': _contaId ?? '',
        'memberId': _memberDocIdForDonation ?? '',
        'memberCpf': _onlyDigits(widget.cpf),
        'donationKind': _donationKind,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final qr = (data['qr_code'] ?? '').toString();
      if (mounted) {
        setState(() {
          _qrPayload = qr.isNotEmpty ? qr : null;
          _paymentId = (data['payment_id'] ?? '').toString();
          _gerando = false;
        });
        if (qr.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showPixPreviewModal();
          });
        }
      }
      if (mounted && qr.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'PIX gerado (id $_paymentId), mas o QR não veio na resposta. Tente de novo ou verifique o MP.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gerando = false;
          _erro = '$e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _abrirCheckoutCartao() async {
    final v = parseBrCurrencyInput(_valorCtrl.text);
    if (v < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe um valor válido (mínimo R\$ 1,00).')),
      );
      return;
    }
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do doador ou membro.')),
      );
      return;
    }
    setState(() {
      _gerando = true;
      _erro = null;
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createChurchDonationPreference');
      final res = await callable.call(<String, dynamic>{
        'tenantId': widget.tenantId,
        'amount': v,
        'donorName': nome,
        'payerEmail': _emailCtrl.text.trim(),
        'contaDestinoId': _contaId ?? '',
        'memberId': _memberDocIdForDonation ?? '',
        'memberCpf': _onlyDigits(widget.cpf),
        'returnUrl': _churchPanelDonationReturnUrl(),
        'maxInstallments': _parcelas,
        'donationKind': _donationKind,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final url = (data['init_point'] ?? '').toString().trim();
      if (url.isEmpty) {
        throw Exception('Link do Mercado Pago não retornado.');
      }
      if (mounted) {
        setState(() {
          _checkoutEmbedUrl = url;
          _gerando = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showCheckoutPreviewModal();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gerando = false;
          _erro = '$e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _onPrimaryAction() async {
    if (_pixMode) {
      await _gerarPix();
    } else {
      await _abrirCheckoutCartao();
    }
  }

  void _showPixPreviewModal() {
    final qr = _qrPayload;
    if (qr == null || qr.isEmpty) return;
    final primary = ThemeCleanPremium.primary;
    final deep = Color.lerp(primary, const Color(0xFF0F172A), 0.35)!;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(context).height * 0.9;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: maxH,
              child: ColoredBox(
                color: Colors.white,
                child: Column(
                  children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primary, deep],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.qr_code_2_rounded,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PIX pronto para pagar',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Escaneie ou copie — confirmação em segundos',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.pop(ctx),
                          icon:
                              const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                                boxShadow: ThemeCleanPremium.softUiCardShadow,
                              ),
                              child: QrImageView(
                                data: qr,
                                version: QrVersions.auto,
                                size: 240,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 3,
                            ),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: qr));
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Código PIX copiado.'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text(
                              'Copiar PIX copia e cola',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SelectableText(
                            qr,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          if (_paymentId != null && _paymentId!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Pagamento MP: $_paymentId',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCheckoutPreviewModal() async {
    final url = _checkoutEmbedUrl;
    if (url == null || url.isEmpty) return;
    final primary = ThemeCleanPremium.primary;

    await showMercadoPagoCheckoutFullscreen(
      context,
      checkoutUrl: url,
      returnUrlHint: _churchPanelDonationReturnUrl(),
      primaryColor: primary,
      footerHint:
          'PIX ou cartão acima. Ao aprovar, o lançamento entra no Financeiro em segundos (webhook).',
      onPaymentReturn: (u) async {
        if (!mounted) return;
        setState(() => _checkoutEmbedUrl = null);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.volunteer_activism_rounded,
                    color: ThemeCleanPremium.primary, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Obrigado pela contribuição!',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'O pagamento foi concluído no Mercado Pago. '
              'O lançamento entra no Financeiro em instantes (webhook). '
              'Que Deus abençoe a sua semente.',
              style: TextStyle(height: 1.45, fontSize: 15),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Amém'),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _seeAllDonationHistory() {
    final r = widget.role.toLowerCase();
    return r == 'gestor' ||
        r == 'adm' ||
        r == 'admin' ||
        r == 'master' ||
        r == 'tesoureiro' ||
        r == 'tesouraria' ||
        r == 'pastor' ||
        r == 'pastora' ||
        r == 'secretario' ||
        r == 'presbitero' ||
        r == 'diacono' ||
        r == 'evangelista';
  }

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    final deep = Color.lerp(primary, const Color(0xFF0F172A), 0.35)!;

    final embedded = widget.embeddedInShell;
    return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: embedded
            ? null
            : AppBar(
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                title: const SizedBox.shrink(),
                toolbarHeight: 48,
                bottom: ChurchPanelPillTabBar(
                  dense: true,
                  controller: _tabCtrl,
                  tabs: const [
                    Tab(
                      text: 'Contribuir',
                      icon: Icon(Icons.volunteer_activism_rounded, size: 18),
                    ),
                    Tab(
                      text: 'Histórico',
                      icon: Icon(Icons.history_rounded, size: 18),
                    ),
                  ],
                ),
              ),
        body: SafeArea(
          top: !embedded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (embedded)
                Container(
                  color: ThemeCleanPremium.primary,
                  child: ChurchPanelPillTabBar(
                    dense: true,
                    controller: _tabCtrl,
                    tabs: const [
                      Tab(
                        text: 'Contribuir',
                        icon: Icon(Icons.volunteer_activism_rounded, size: 18),
                      ),
                      Tab(
                        text: 'Histórico',
                        icon: Icon(Icons.history_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: ThemeCleanPremium.churchPanelBodyGradient,
          ),
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withValues(alpha: 0.12),
                    primary.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              primary.withValues(alpha: 0.2),
                              primary.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        ),
                        child: Icon(Icons.volunteer_activism_rounded,
                            color: primary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PIX ou cartão (Mercado Pago)',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: -0.3,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'O valor cai na conta MP da igreja. Super Premium: escolha dízimo ou oferta — extrato e financeiro com nome completo do membro (cadastro) ou nome informado.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (ctx) {
                final pad = ThemeCleanPremium.pagePadding(ctx);
                return Container(
                  margin: EdgeInsets.only(
                    left: -pad.left,
                    right: -pad.right,
                    bottom: 2,
                  ),
                  child: ChurchPanelPillPair(
                    valueIsA: _pixMode,
                    onChanged: (v) {
                      setState(() {
                        _pixMode = v;
                        if (_pixMode) _checkoutEmbedUrl = null;
                      });
                    },
                    labelA: 'PIX',
                    labelB: 'Cartão',
                    iconA: Icons.qr_code_2_rounded,
                    iconB: Icons.credit_card_rounded,
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            DonationKindSelectorGrid(
              value: _donationKind,
              accentColor: primary,
              onChanged: (k) => setState(() => _donationKind = k),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _valorCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [BrCurrencyInputFormatter()],
              decoration: _inputDec(
                label: 'Valor (R\$)',
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nomeCtrl,
              decoration: _inputDec(
                label: 'Nome do doador ou membro',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDec(
                label: 'E-mail (opcional, para recibo MP)',
                icon: Icons.alternate_email_rounded,
              ),
            ),
            if (!_pixMode) ...[
              const SizedBox(height: 20),
              InputDecorator(
                decoration: _inputDec(
                  label: 'Parcelas no cartão (máximo)',
                  icon: Icons.numbers_rounded,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _parcelas,
                    isExpanded: true,
                    isDense: true,
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}×'),
                      ),
                    ),
                    onChanged: (v) =>
                        setState(() => _parcelas = v ?? 1),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ao gerar, o checkout abre num painel em destaque (mesma sessão). Se o iframe falhar, use “abrir em nova aba” no rodapé.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (_loadingContas)
              const LinearProgressIndicator(minHeight: 3)
            else if (_contas.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  'É necessária uma conta Mercado Pago (código bancário 323) em Financeiro → Contas, '
                  'ou em Configurações → criar conta Mercado Pago na tesouraria. Outros bancos não entram nesta integração.',
                  style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 13,
                      height: 1.35),
                ),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey<String>('mpconta_${_contaId ?? 'none'}'),
                initialValue: _contaId,
                decoration: _inputDec(
                  label: 'Conta (tesouraria) para conciliação',
                  icon: Icons.account_balance_rounded,
                ),
                isExpanded: true,
                items: _contas
                    .map((e) =>
                        DropdownMenuItem(value: e.id, child: Text(e.nome)))
                    .toList(),
                onChanged: (v) => setState(() => _contaId = v),
              ),
            if (_erro != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: SelectableText(
                  _erro!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _gerando
                        ? null
                        : () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text(
                      'Voltar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: deep,
                      side: BorderSide(
                        color: primary.withValues(alpha: 0.55),
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _gerando ? null : _cancelarFluxoDoacao,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade800,
                      side: BorderSide(
                        color: Colors.grey.shade400,
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Material(
              color: Colors.transparent,
              elevation: 0,
              child: InkWell(
                onTap: (_gerando || _loadingContas || _contas.isEmpty)
                    ? null
                    : _onPrimaryAction,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primary, deep],
                    ),
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.45),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      ...ThemeCleanPremium.cardShadowHover,
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_gerando)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          Icon(
                            _pixMode
                                ? Icons.qr_code_2_rounded
                                : Icons.payment_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        const SizedBox(width: 10),
                        Text(
                          _gerando
                              ? 'Aguarde…'
                              : (_pixMode
                                  ? 'Gerar código PIX'
                                  : 'Abrir checkout (cartão ou PIX)'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_pixMode &&
                _qrPayload != null &&
                _qrPayload!.isNotEmpty) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(
                    color: primary.withValues(alpha: 0.65),
                    width: 2,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                ),
                onPressed: _showPixPreviewModal,
                icon: const Icon(Icons.open_in_full_rounded),
                label: const Text(
                  'Ver código PIX em destaque',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            if (!_pixMode &&
                _checkoutEmbedUrl != null &&
                _checkoutEmbedUrl!.isNotEmpty) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(
                    color: primary.withValues(alpha: 0.65),
                    width: 2,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                ),
                onPressed: _showCheckoutPreviewModal,
                icon: const Icon(Icons.layers_rounded),
                label: const Text(
                  'Abrir checkout em destaque',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
              _DonationHistoryTab(
                tenantId: widget.tenantId,
                cpf: widget.cpf,
                seeAll: _seeAllDonationHistory(),
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

/// Contribuições aprovadas (histórico leve, retenção ~5 meses no servidor).
class _DonationHistoryTab extends StatefulWidget {
  final String tenantId;
  final String? cpf;
  final bool seeAll;

  const _DonationHistoryTab({
    required this.tenantId,
    this.cpf,
    required this.seeAll,
  });

  @override
  State<_DonationHistoryTab> createState() => _DonationHistoryTabState();
}

class _DonationHistoryTabState extends State<_DonationHistoryTab> {
  final _searchCtrl = TextEditingController();
  String? _methodFilter;
  /// null = todos, `dizimo`, `oferta`
  String? _kindFilter;
  int _periodDays = 152;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _myCpfDigits => _onlyDigits(widget.cpf);

  bool _passesRole(Map<String, dynamic> d) {
    if (widget.seeAll) return true;
    final docCpf = (d['memberCpfDigits'] ?? '').toString();
    if (_myCpfDigits.length >= 11 && docCpf == _myCpfDigits) return true;
    return false;
  }

  bool _passesKind(Map<String, dynamic> d) {
    if (_kindFilter == null) return true;
    final k = (d['donationKind'] ?? '').toString().toLowerCase().trim();
    if (_kindFilter == 'oferta') return k == 'oferta';
    return k.isEmpty || k == 'dizimo' || k == 'dízimo';
  }

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    final q = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('contribuicoes_dizimo_historico')
        .orderBy('approvedAt', descending: true)
        .limit(400);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Não foi possível carregar o histórico.\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        final now = DateTime.now();
        final cutoff = now.subtract(Duration(days: _periodDays));
        final needle = _searchCtrl.text.trim().toLowerCase();

        var rows = docs.where((x) {
          final d = x.data();
          final ap = d['approvedAt'];
          DateTime? dt;
          if (ap is Timestamp) dt = ap.toDate();
          if (dt == null || dt.isBefore(cutoff)) return false;
          if (!_passesRole(d)) return false;
          final mk = (d['methodKey'] ?? '').toString();
          if (_methodFilter != null && mk != _methodFilter) return false;
          if (!_passesKind(d)) return false;
          if (needle.isEmpty) return true;
          final nome = (d['donorName'] ?? '').toString().toLowerCase();
          final mp = (d['mpPaymentId'] ?? '').toString().toLowerCase();
          return nome.contains(needle) || mp.contains(needle);
        }).toList();

        final fmtMoney = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
        final fmtDate =
            DateFormat("d MMM 'de' yyyy · HH:mm", 'pt_BR');

        return ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withValues(alpha: 0.14),
                    primary.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.insights_rounded, color: primary, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Histórico temporário',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.seeAll
                        ? 'Até 5 meses — registros antigos são removidos automaticamente para poupar espaço. Não substitui o Financeiro.'
                        : 'Mostramos apenas contribuições vinculadas ao seu CPF no cadastro, quando informado.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!widget.seeAll && _myCpfDigits.length < 11)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Text(
                    'Para ver apenas as suas contribuições, o cadastro da igreja deve ter o seu CPF associado ao login.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.amber.shade900,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Buscar por nome ou ID Mercado Pago',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Período',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _periodChip('30 dias', 30, primary),
                _periodChip('90 dias', 90, primary),
                _periodChip('5 meses', 152, primary),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Forma de pagamento',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _methodChip('Todos', null, primary),
                _methodChip('PIX', 'pix', primary),
                _methodChip('Cartão', 'cartao', primary),
                _methodChip('Outro', 'outro', primary),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Dízimo / Oferta',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kindChip('Todos', null, primary),
                _kindChip('Dízimo', 'dizimo', primary),
                _kindChip('Oferta', 'oferta', primary),
              ],
            ),
            const SizedBox(height: 20),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_rounded,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhuma contribuição neste filtro.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...rows.map((doc) {
                final d = doc.data();
                final ap = d['approvedAt'];
                DateTime? dt;
                if (ap is Timestamp) dt = ap.toDate();
                final amount = (d['amount'] is num)
                    ? (d['amount'] as num).toDouble()
                    : 0.0;
                final mk = (d['methodKey'] ?? '').toString();
                String label;
                IconData ic;
                switch (mk) {
                  case 'pix':
                    label = 'PIX';
                    ic = Icons.qr_code_2_rounded;
                    break;
                  case 'cartao':
                    label = 'Cartão';
                    ic = Icons.credit_card_rounded;
                    break;
                  default:
                    label = 'Outro';
                    ic = Icons.payment_rounded;
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.white,
                    elevation: 0,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(ic, color: primary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fmtMoney.format(amount),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (d['donorName'] ?? '').toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Builder(
                                    builder: (context) {
                                      final dk =
                                          (d['donationKind'] ?? '').toString();
                                      final kindLabel = (d['donationKindLabel'] ??
                                              (dk == 'oferta'
                                                  ? 'Oferta'
                                                  : 'Dízimo'))
                                          .toString();
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:
                                              primary.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          kindLabel,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            color: primary,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (dt != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              fmtDate.format(dt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          if ((d['contaDestinoNome'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Conta: ${d['contaDestinoNome']}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'MP ${d['mpPaymentId'] ?? doc.id}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 64),
          ],
        );
      },
    );
  }

  Widget _periodChip(String label, int days, Color primary) {
    final sel = _periodDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (v) {
        if (v) setState(() => _periodDays = days);
      },
      selectedColor: primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
        color: sel ? primary : Colors.grey.shade800,
      ),
    );
  }

  Widget _methodChip(String label, String? key, Color primary) {
    final sel = _methodFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (v) {
        if (v) setState(() => _methodFilter = key);
      },
      selectedColor: primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
        color: sel ? primary : Colors.grey.shade800,
      ),
    );
  }

  Widget _kindChip(String label, String? key, Color primary) {
    final sel = _kindFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (v) {
        if (v) setState(() => _kindFilter = key);
      },
      selectedColor: primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
        color: sel ? primary : Colors.grey.shade800,
      ),
    );
  }
}
