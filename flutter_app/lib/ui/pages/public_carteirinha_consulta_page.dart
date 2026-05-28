import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/carteirinha_staff_redirect.dart';
import 'package:gestao_yahweh/core/carteirinha_visual_tokens.dart';
import 'package:gestao_yahweh/services/carteirinha_validacao_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Rota pública do QR da carteirinha (`/carteirinha-validar`).
class PublicCarteirinhaConsultaPage extends StatefulWidget {
  final String tenantId;
  final String memberId;

  const PublicCarteirinhaConsultaPage({
    super.key,
    required this.tenantId,
    required this.memberId,
  });

  @override
  State<PublicCarteirinhaConsultaPage> createState() =>
      _PublicCarteirinhaConsultaPageState();
}

class _PublicCarteirinhaConsultaPageState
    extends State<PublicCarteirinhaConsultaPage> {
  late Future<CarteirinhaValidacaoResultado> _validacao;

  @override
  void initState() {
    super.initState();
    _validacao = CarteirinhaValidacaoService.consultar(
      tenantId: widget.tenantId,
      memberId: widget.memberId,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStaffRedirect();
    });
  }

  Future<void> _retry() async {
    setState(() {
      _validacao = CarteirinhaValidacaoService.consultar(
        tenantId: widget.tenantId,
        memberId: widget.memberId,
      );
    });
    await _validacao;
  }

  Future<void> _tryStaffRedirect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final tid = widget.tenantId.trim();
    final mid = widget.memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final role = (doc.data()?['role'] ?? '').toString().toLowerCase().trim();
      if (!carteirinhaPainelStaffRole(role)) return;
      final ok = await carteirinhaUserTenantMatchesQr(qrTenantId: tid);
      if (!ok || !mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/painel?openMemberId=${Uri.encodeComponent(mid)}',
      );
    } catch (_) {}
  }

  bool _credencialValida(CarteirinhaValidacaoResultado r) =>
      r.ok && r.found && r.active;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Validar carteirinha'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<CarteirinhaValidacaoResultado>(
          future: _validacao,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'A verificar credencial…',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C6B7A),
                      ),
                    ),
                  ],
                ),
              );
            }

            final r = snap.data;
            if (r == null) {
              return _scrollWrap(
                _resultCard(
                  context,
                  tone: _CarteirinhaValTone.erro,
                  title: 'Não foi possível validar',
                  subtitle:
                      'Ocorreu um erro inesperado. Tente novamente em instantes.',
                  showRetry: true,
                ),
              );
            }

            if (_credencialValida(r)) {
              return _scrollWrap(_validBody(context, r));
            }

            if (!r.found) {
              return _scrollWrap(
                _resultCard(
                  context,
                  tone: _CarteirinhaValTone.aviso,
                  title: 'Credencial não encontrada',
                  subtitle: r.message.isNotEmpty
                      ? r.message
                      : 'Este código não corresponde a um membro ativo nesta igreja.',
                  detailRows: r.churchName.isNotEmpty
                      ? [('Igreja consultada', r.churchName)]
                      : null,
                  showRetry: true,
                ),
              );
            }

            if (!r.active) {
              return _scrollWrap(
                _resultCard(
                  context,
                  tone: _CarteirinhaValTone.aviso,
                  title: 'Cadastro inativo',
                  subtitle: r.message.isNotEmpty
                      ? r.message
                      : 'A credencial existe, mas o membro não está ativo no sistema.',
                  detailRows: [
                    if (r.churchName.isNotEmpty) ('Igreja', r.churchName),
                    if (r.titularMascarado.isNotEmpty)
                      ('Titular', r.titularMascarado),
                  ],
                ),
              );
            }

            return _scrollWrap(
              _resultCard(
                context,
                tone: _CarteirinhaValTone.erro,
                title: 'Validação indisponível',
                subtitle: r.message.isNotEmpty
                    ? r.message
                    : 'Não foi possível concluir a verificação.',
                showRetry: true,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _scrollWrap(Widget child) {
    return SingleChildScrollView(
      padding: ThemeCleanPremium.pagePadding(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: child,
        ),
      ),
    );
  }

  Widget _validBody(BuildContext context, CarteirinhaValidacaoResultado r) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        side: BorderSide(
          color: CarteirinhaVisualTokens.accentGoldFlutter.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _CarteirinhaSeloValidade(),
            const SizedBox(height: 20),
            Text(
              'Credencial verificada',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0D3B66),
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Esta carteirinha está registrada e ativa na plataforma Gestão YAHWEH.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (r.churchName.isNotEmpty)
              _valRow('Igreja emissora', r.churchName),
            if (r.titularMascarado.isNotEmpty)
              _valRow('Titular', r.titularMascarado),
            if (r.validityHint.isNotEmpty)
              _valRow('Validade', r.validityHint),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 22, color: Colors.green.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.message.isNotEmpty
                          ? r.message
                          : 'Situação ativa confirmada em tempo real.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Para conferência completa de dados ou segunda via, contacte a secretaria da igreja.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(
    BuildContext context, {
    required _CarteirinhaValTone tone,
    required String title,
    required String subtitle,
    List<(String, String)>? detailRows,
    bool showRetry = false,
  }) {
    final (icon, color, bg) = switch (tone) {
      _CarteirinhaValTone.ok => (
          Icons.verified_rounded,
          Colors.green.shade700,
          const Color(0xFFE8F5E9),
        ),
      _CarteirinhaValTone.aviso => (
          Icons.warning_amber_rounded,
          Colors.orange.shade800,
          const Color(0xFFFFF3E0),
        ),
      _CarteirinhaValTone.erro => (
          Icons.error_outline_rounded,
          Colors.red.shade700,
          const Color(0xFFFFEBEE),
        ),
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            if (detailRows != null && detailRows.isNotEmpty) ...[
              const SizedBox(height: 20),
              for (final row in detailRows) _valRow(row.$1, row.$2),
            ],
            const SizedBox(height: 20),
            if (showRetry)
              FilledButton.icon(
                onPressed: _retry,
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CarteirinhaValTone { ok, aviso, erro }

/// Selo circular dourado — validação oficial da credencial.
class _CarteirinhaSeloValidade extends StatelessWidget {
  const _CarteirinhaSeloValidade();

  @override
  Widget build(BuildContext context) {
    const gold = CarteirinhaVisualTokens.accentGoldFlutter;
    const navy = Color(0xFF0D3B66);

    return Center(
      child: SizedBox(
        width: 132,
        height: 132,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    gold.withValues(alpha: 0.35),
                    gold.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(color: gold, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: gold.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: navy.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    size: 40,
                    color: navy.withValues(alpha: 0.92),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'VÁLIDA',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _valRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
            letterSpacing: 0.25,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A2B3C),
          ),
        ),
      ],
    ),
  );
}
