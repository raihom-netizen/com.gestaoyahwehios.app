import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/ios_payments_gate.dart';
import '../../data/planos_oficiais.dart';
import '../theme_clean_premium.dart';
import 'app_shell.dart';

/// Tela de "Atualizar plano" exibida em iOS sob o gate `exibir_pagamento_ios`.
///
/// Estrategia (Apple Guideline 3.1.1 / 3.1.3 — Multiplatform Service / Reader):
///
///   1. Mostrar **somente informacoes** dos planos (nome, capacidade,
///      recursos). Sem precos, sem ciclo de cobranca, sem qualquer CTA
///      de compra dentro do binario iOS.
///   2. Botao «Atualizar plano no site» abre Safari em `/atualizar-plano?from=ios_app`
///      (sessão web existente → planos direto; senão Google/Apple/e-mail) e checkout MP.
///   3. Webhook MP atualiza o status no Firestore — o app detecta via
///      snapshot listener e libera o plano automaticamente.
///
/// E o mesmo padrao usado por outros apps SaaS aprovados na App Store
/// (ex.: Spotify, Netflix, Kindle e o competidor "enuves").
class IosPaymentUnavailableView extends StatefulWidget {
  /// Quando `true`, omite a AppBar (uso embutido em outro Scaffold/Shell).
  final bool embedded;

  const IosPaymentUnavailableView({
    super.key,
    this.embedded = false,
  });

  @override
  State<IosPaymentUnavailableView> createState() =>
      _IosPaymentUnavailableViewState();
}

class _IosPaymentUnavailableViewState extends State<IosPaymentUnavailableView> {
  bool _opening = false;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    // Um toque no botão "Atualizar plano" do app iOS já deve abrir o fluxo web expresso.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoOpened) return;
      _autoOpened = true;
      _openExternalPlans();
    });
  }

  /// URL externa — abre o **login web da igreja**; depois do login segue para
  /// `/atualizar-plano` com `from=ios_app` (planos + checkout embebido).
  Uri _buildExternalUrl() {
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    return IosPaymentsGate.churchWebLoginThenAtualizarPlanoUri(
      utmMedium: 'manage_subscription',
      email: email.isEmpty ? null : email,
    );
  }

  Future<void> _openExternalPlans() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final uri = _buildExternalUrl();
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Nao foi possivel abrir o navegador. Acesse gestaoyahweh.com.br/atualizar-plano no Safari.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Nao foi possivel abrir o navegador. Acesse gestaoyahweh.com.br/atualizar-plano no Safari.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _buildUpgradeCta(BuildContext context, {required String label}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: _opening ? null : _openExternalPlans,
        icon: _opening
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.open_in_new_rounded),
        label: Text(
          _opening ? 'Abrindo navegador...' : label,
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
    );
  }

  Widget _buildPlanCard(BuildContext context, PlanoOficial p) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.featured ? cs.primary : const Color(0xFFE5EAF3),
          width: p.featured ? 1.6 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 6),
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
                  p.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (p.featured)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Recomendado',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            p.members,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          const _PlanFeatureLine('Painel web + app mobile + site público'),
          const _PlanFeatureLine('Membros, eventos, escalas e financeiro'),
          const _PlanFeatureLine('Backups automáticos e segurança'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final body = SafeArea(
      child: AppShell(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabeçalho
                  Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Atualizar plano',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Veja os planos disponíveis e a capacidade de cada um. '
                    'Para contratar ou trocar de plano, use o botão abaixo — '
                    'a contratação é feita no nosso site.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade800,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // CTA — TOPO
                  _buildUpgradeCta(context, label: 'Atualizar plano no site'),
                  const SizedBox(height: 14),

                  // Lista de planos (somente informacoes — sem precos)
                  LayoutBuilder(
                    builder: (context, c) {
                      final isWide = c.maxWidth >= 560;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final p in planosOficiais)
                            SizedBox(
                              width: isWide
                                  ? (c.maxWidth - 12) / 2
                                  : double.infinity,
                              child: _buildPlanCard(context, p),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  // CTA — RODAPÉ (mesma ação)
                  _buildUpgradeCta(context, label: 'Atualizar plano no site'),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Você será redirecionado para gestaoyahweh.com.br',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Card explicativo
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 20,
                          color: Color(0xFF475569),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Após contratar o plano no site, ele é ativado '
                            'automaticamente nesta conta — pode ser preciso '
                            'reabrir o aplicativo.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botão voltar (opcional, não embedded)
                  Builder(
                    builder: (ctx) {
                      final canPop = Navigator.of(ctx).canPop();
                      if (!canPop || widget.embedded) {
                        return const SizedBox.shrink();
                      }
                      return SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Voltar ao painel'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atualizar plano'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}

class _PlanFeatureLine extends StatelessWidget {
  final String text;
  const _PlanFeatureLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF334155),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
