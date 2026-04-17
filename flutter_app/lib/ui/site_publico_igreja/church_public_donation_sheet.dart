import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/mp_checkout_fullscreen_page.dart';
import 'package:gestao_yahweh/ui/widgets/premium_toggle_pair.dart';
import 'package:gestao_yahweh/ui/widgets/donation_kind_selector_grid.dart';

/// URL de retorno após pagamento no Checkout Pro (Mercado Pago).
String churchPublicDonationReturnUrl(String slugClean) {
  final s = slugClean.trim();
  if (s.isEmpty) return '${Uri.base.origin}/';
  if (kIsWeb) {
    final o = Uri.base.origin;
    return '$o/#/$s';
  }
  return '${Uri.base.origin}/#/$s';
}

Future<void> showChurchPublicDonationSheet(
  BuildContext context, {
  required String tenantId,
  required Color accentColor,
  required String slugClean,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChurchPublicDonationSheet(
      tenantId: tenantId,
      accentColor: accentColor,
      slugClean: slugClean,
    ),
  );
}

class _ChurchPublicDonationSheet extends StatefulWidget {
  final String tenantId;
  final Color accentColor;
  final String slugClean;

  const _ChurchPublicDonationSheet({
    required this.tenantId,
    required this.accentColor,
    required this.slugClean,
  });

  @override
  State<_ChurchPublicDonationSheet> createState() =>
      _ChurchPublicDonationSheetState();
}

class _ChurchPublicDonationSheetState extends State<_ChurchPublicDonationSheet> {
  final _valorCtrl = TextEditingController(text: '50');
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _pixMode = true;
  int _parcelas = 1;
  String _donationKind = 'dizimo';
  bool _loading = false;
  String? _qrPayload;
  String? _paymentId;
  String? _checkoutEmbedUrl;
  String? _erro;

  @override
  void dispose() {
    _valorCtrl.dispose();
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
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

  Future<void> _gerarPix() async {
    final raw = _valorCtrl.text.replaceAll(',', '.').trim();
    final v = double.tryParse(raw);
    if (v == null || v < 1) {
      _toast('Informe um valor válido (mínimo R\$ 1,00).');
      return;
    }
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      _toast('Informe seu nome.');
      return;
    }
    setState(() {
      _loading = true;
      _erro = null;
      _qrPayload = null;
      _paymentId = null;
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createChurchDonationPix');
      final res = await callable.call(<String, dynamic>{
        'tenantId': widget.tenantId,
        'amount': v,
        'donorName': nome,
        'payerEmail': _emailCtrl.text.trim(),
        'contaDestinoId': '',
        'memberId': '',
        'donationKind': _donationKind,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final qr = (data['qr_code'] ?? '').toString();
      if (mounted) {
        setState(() {
          _qrPayload = qr.isNotEmpty ? qr : null;
          _paymentId = (data['payment_id'] ?? '').toString();
          _loading = false;
        });
        if (qr.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showPixPreviewModal();
          });
        }
      }
      if (mounted && qr.isEmpty) {
        _toast('PIX gerado; se o QR não aparecer, tente novamente.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = '$e';
        });
        _toast('Erro: $e');
      }
    }
  }

  Future<void> _abrirCheckoutCartao() async {
    final raw = _valorCtrl.text.replaceAll(',', '.').trim();
    final v = double.tryParse(raw);
    if (v == null || v < 1) {
      _toast('Informe um valor válido (mínimo R\$ 1,00).');
      return;
    }
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      _toast('Informe seu nome.');
      return;
    }
    setState(() {
      _loading = true;
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
        'contaDestinoId': '',
        'memberId': '',
        'returnUrl': churchPublicDonationReturnUrl(widget.slugClean),
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
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showCheckoutPreviewModal();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = '$e';
        });
        _toast('Erro: $e');
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _thankYouAndCloseSite() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.volunteer_activism_rounded,
                color: widget.accentColor, size: 30),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Obrigado pela sua contribuição!',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'O pagamento foi concluído com o Mercado Pago. '
          'A igreja recebe a confirmação no financeiro em instantes. '
          'Que Deus abençoe a sua semente nesta obra.',
          style: TextStyle(height: 1.45, fontSize: 15),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Amém'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _showPixPreviewModal() {
    final qr = _qrPayload;
    if (qr == null || qr.isEmpty) return;
    final primary = widget.accentColor;
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
                        gradient: LinearGradient(colors: [primary, deep]),
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
                                  'PIX para pagar',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Escaneie ou copie o código',
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
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
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
                              child: QrImageView(
                                data: qr,
                                version: QrVersions.auto,
                                size: 240,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: qr));
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text('Código PIX copiado.')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text(
                                'Copiar PIX copia e cola',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (_paymentId != null && _paymentId!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Ref. MP: $_paymentId',
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

    await showMercadoPagoCheckoutFullscreen(
      context,
      checkoutUrl: url,
      returnUrlHint: churchPublicDonationReturnUrl(widget.slugClean),
      primaryColor: widget.accentColor,
      footerHint:
          'PIX ou cartão acima. Ao aprovar, a igreja recebe a confirmação no financeiro (webhook).',
      onPaymentReturn: (_) async {
        if (!mounted) return;
        await _thankYouAndCloseSite();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final deep = Color.lerp(widget.accentColor, const Color(0xFF0F172A), 0.35)!;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ThemeCleanPremium.radiusXl),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.accentColor.withValues(alpha: 0.15),
                          widget.accentColor.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.volunteer_activism_rounded,
                        color: widget.accentColor, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Doação PIX / Cartão',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Super Premium · escolha dízimo ou oferta · Mercado Pago · lançamento automático no financeiro',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PremiumTogglePair(
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
                    const SizedBox(height: 18),
                    DonationKindSelectorGrid(
                      value: _donationKind,
                      accentColor: widget.accentColor,
                      onChanged: (k) => setState(() => _donationKind = k),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _valorCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Valor (R\$)',
                        prefixText: 'R\$ ',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nomeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Seu nome',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'E-mail (opcional, recibo)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                        ),
                      ),
                    ),
                    if (!_pixMode) ...[
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Parcelas no cartão (máximo)',
                          prefixIcon: Icon(Icons.numbers_rounded,
                              color: widget.accentColor, size: 22),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                          ),
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
                        'Ao gerar, o checkout abre num painel em tela quase inteira. Se o iframe falhar, use “abrir em nova aba” no rodapé.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _erro!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded, size: 20),
                            label: const Text(
                              'Voltar',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: deep,
                              side: BorderSide(
                                color: widget.accentColor.withValues(alpha: 0.55),
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
                            onPressed: _loading ? null : _cancelarFluxoDoacao,
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
                      child: InkWell(
                        onTap: _loading
                            ? null
                            : (_pixMode ? _gerarPix : _abrirCheckoutCartao),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.accentColor,
                                deep,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusLg),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.accentColor.withValues(alpha: 0.4),
                                blurRadius: 18,
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
                                if (_loading)
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
                                        ? Icons.qr_code_rounded
                                        : Icons.payment_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                const SizedBox(width: 10),
                                Text(
                                  _loading
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
                          foregroundColor: widget.accentColor,
                          side: BorderSide(
                            color: widget.accentColor.withValues(alpha: 0.65),
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
                          'Ver PIX em destaque',
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
                          foregroundColor: widget.accentColor,
                          side: BorderSide(
                            color: widget.accentColor.withValues(alpha: 0.65),
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
