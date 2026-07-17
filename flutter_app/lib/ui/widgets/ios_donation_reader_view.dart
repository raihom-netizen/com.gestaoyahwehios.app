import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/public_member_signup_navigation.dart';
import 'package:gestao_yahweh/core/church_panel_tenant_gateway.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/app_shell.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// iOS — Guideline 3.2.2(iv): checkout PIX/cartão no site; navegação **in-app** instantânea.
///
/// Android/Web mantêm [ChurchDonationsPage] com PIX/cartão no painel.
class IosDonationReaderView extends StatefulWidget {
  final String tenantId;
  final bool embeddedInShell;

  const IosDonationReaderView({
    super.key,
    required this.tenantId,
    this.embeddedInShell = false,
  });

  @override
  State<IosDonationReaderView> createState() => _IosDonationReaderViewState();
}

class _IosDonationReaderViewState extends State<IosDonationReaderView> {
  bool _openingSafari = false;
  String? _churchSlug;
  Map<String, dynamic>? _churchData;
  String _churchName = 'sua igreja';

  @override
  void initState() {
    super.initState();
    _churchSlug = widget.tenantId.trim().isEmpty ? null : widget.tenantId.trim();
    unawaited(_loadChurchMeta());
  }

  Future<void> _loadChurchMeta() async {
    try {
      final op = ChurchPanelTenantGateway.churchId(widget.tenantId.trim());
      final snap = await ChurchUiCollections.churchDoc(op)
          .get(const GetOptions(source: Source.cache));
      var d = snap.data() ?? {};
      var slug = (d['slug'] ?? d['slugId'] ?? '').toString().trim();
      if (slug.isEmpty) {
        final server = await ChurchUiCollections.churchDoc(op).get();
        d = server.data() ?? {};
        slug = (d['slug'] ?? d['slugId'] ?? '').toString().trim();
      }
      final nome = (d['nome'] ?? d['NOME'] ?? d['name'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _churchData = d;
        if (slug.isNotEmpty) _churchSlug = slug;
        if (nome.isNotEmpty) _churchName = nome;
      });
    } catch (_) {}
  }

  String get _effectiveSlug {
    final s = (_churchSlug ?? widget.tenantId).trim();
    return s.isEmpty ? widget.tenantId : s;
  }

  void _openSiteInApp() {
    final slug = _effectiveSlug;
    if (slug.isEmpty || !mounted) return;
    PublicMemberSignupNavigation.openChurchPublicSite(context, slug: slug);
  }

  Future<void> _openSafariCheckout() async {
    if (_openingSafari) return;
    final slug = _effectiveSlug;
    setState(() => _openingSafari = true);
    try {
      await IosPaymentsGate.openChurchDonationsExternally(
        churchSlug: slug,
        churchData: _churchData,
      );
    } finally {
      if (mounted) setState(() => _openingSafari = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = AppShell(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.volunteer_activism_rounded,
                size: 56,
                color: cs.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 16),
              Text(
                kChurchDonationModuleLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Abra o site de $_churchName no app e use o botão Dízimos/Ofertas (PIX ou cartão Mercado Pago). '
                'No iPhone o pagamento final pode abrir no Safari, conforme a App Store.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _openSiteInApp,
                  icon: const Icon(Icons.public_rounded),
                  label: const Text(
                    'Abrir site da igreja',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _openingSafari ? null : _openSafariCheckout,
                  icon: _openingSafari
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : const Icon(Icons.open_in_new_rounded, size: 20),
                  label: Text(
                    _openingSafari ? 'Abrindo Safari…' : 'Abrir no Safari',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.embeddedInShell) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text(kChurchDonationModuleLabel),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}
