import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/app_shell.dart';

/// iOS — Guideline 3.2.2(iv): dízimos e ofertas só no **site** (Safari), não no app.
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
  bool _opening = false;
  bool _autoOpened = false;
  String? _churchSlug;
  Map<String, dynamic>? _churchData;
  String _churchName = 'sua igreja';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChurch());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoOpened) return;
      _autoOpened = true;
      _openSite();
    });
  }

  Future<void> _loadChurch() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .get();
      final d = snap.data() ?? {};
      var slug = (d['slug'] ?? '').toString().trim();
      if (slug.isEmpty) slug = widget.tenantId;
      final nome = (d['nome'] ?? d['NOME'] ?? d['name'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _churchData = d;
        _churchSlug = slug;
        if (nome.isNotEmpty) _churchName = nome;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _churchSlug = widget.tenantId;
        _loading = false;
      });
    }
  }

  Future<void> _openSite() async {
    if (_opening) return;
    final slug = _churchSlug ?? widget.tenantId;
    setState(() => _opening = true);
    try {
      final ok = await IosPaymentsGate.openChurchDonationsExternally(
        churchSlug: slug,
        churchData: _churchData,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir o navegador. Toque no botão abaixo para tentar de novo.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o site da igreja.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
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
                color: cs.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Dízimos e ofertas',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: ThemeCleanPremium.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _loading
                    ? 'A preparar o link da igreja…'
                    : 'No iPhone, as contribuições (PIX e ofertas) são feitas no site oficial de $_churchName, em ambiente seguro — conforme as regras da App Store.',
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
                  onPressed: _opening || _loading ? null : _openSite,
                  icon: _opening
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.open_in_new_rounded),
                  label: Text(
                    _opening
                        ? 'Abrindo site…'
                        : 'Abrir dízimos e ofertas no site',
                    style: const TextStyle(
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
              const SizedBox(height: 12),
              Text(
                'No site, use o botão de doação para PIX ou cartão. '
                'O lançamento entra no financeiro da igreja automaticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.grey.shade600,
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
        title: const Text('Dízimos e ofertas'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}
