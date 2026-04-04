import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/carteirinha_staff_redirect.dart';
import 'package:gestao_yahweh/services/carteirinha_validacao_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Página pública aberta pelo QR da carteirinha (hash `#/carteirinha-validar`).
///
/// Consulta a Cloud Function [validateCarteirinhaPublic] para confirmar se o membro
/// existe e está ativo, sem expor dados sensíveis no cliente.
class PublicCarteirinhaConsultaPage extends StatefulWidget {
  final String tenantId;
  final String memberId;

  const PublicCarteirinhaConsultaPage({
    super.key,
    required this.tenantId,
    required this.memberId,
  });

  @override
  State<PublicCarteirinhaConsultaPage> createState() => _PublicCarteirinhaConsultaPageState();
}

class _PublicCarteirinhaConsultaPageState extends State<PublicCarteirinhaConsultaPage> {
  CarteirinhaValidacaoResultado? _result;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final tid = widget.tenantId.trim();
    final mid = widget.memberId.trim();
    if (tid.isNotEmpty && mid.isNotEmpty) {
      final wentPainel = await _tryPainelRedirectForStaff();
      if (wentPainel) return;
    }
    await _run();
  }

  /// Gestores da mesma igreja: abre o painel na ficha do membro (edição / presença).
  Future<bool> _tryPainelRedirectForStaff() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final tid = widget.tenantId.trim();
    final mid = widget.memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final role = (doc.data()?['role'] ?? '').toString().toLowerCase().trim();
      if (!carteirinhaPainelStaffRole(role)) return false;
      final ok = await carteirinhaUserTenantMatchesQr(qrTenantId: tid);
      if (!ok || !mounted) return false;
      Navigator.of(context).pushReplacementNamed(
        '/painel?openMemberId=${Uri.encodeComponent(mid)}',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _run() async {
    final tid = widget.tenantId.trim();
    final mid = widget.memberId.trim();
    if (tid.isEmpty || mid.isEmpty) {
      setState(() {
        _loading = false;
        _result = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await CarteirinhaValidacaoService.consultar(tenantId: tid, memberId: mid);
      if (mounted) {
        setState(() {
          _result = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tid = widget.tenantId.trim();
    final mid = widget.memberId.trim();
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Consulta de carteirinha'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 48, color: ThemeCleanPremium.primary.withValues(alpha: 0.85)),
                      const SizedBox(height: 16),
                      Text(
                        'Validação',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Leitura do QR da Gestão YAHWEH. Os dados pessoais completos não são exibidos aqui.',
                        style: TextStyle(fontSize: 14, height: 1.45, color: Colors.grey.shade700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (tid.isEmpty || mid.isEmpty)
                        Text(
                          'Parâmetros de consulta ausentes ou inválidos.',
                          style: TextStyle(fontSize: 14, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        )
                      else if (_error != null)
                        Column(
                          children: [
                            Text(
                              'Não foi possível consultar agora. Tente novamente em instantes.',
                              style: TextStyle(fontSize: 14, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _run,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar de novo'),
                            ),
                          ],
                        )
                      else
                        _buildResult(context, _result!),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, CarteirinhaValidacaoResultado r) {
    if (!r.ok && r.message.isNotEmpty) {
      return Column(
        children: [
          Text(r.message, style: TextStyle(fontSize: 14, color: Colors.orange.shade800), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar de novo'),
          ),
        ],
      );
    }

    if (!r.found) {
      return Column(
        children: [
          _statusBanner(
            icon: Icons.search_off_rounded,
            color: Colors.orange.shade800,
            title: 'Credencial não encontrada',
            subtitle: r.message.isNotEmpty ? r.message : 'Verifique se o QR é recente ou fale com a secretaria.',
          ),
          const SizedBox(height: 16),
          _codeRow(context, 'Igreja (ID)', widget.tenantId.trim()),
        ],
      );
    }

    final ativo = r.active;
    final igrejaLinha = r.churchName.trim().isNotEmpty
        ? r.churchName.trim()
        : 'Igreja local';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusBanner(
          icon: ativo ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: ativo ? const Color(0xFF166534) : const Color(0xFFB91C1C),
          title: ativo
              ? 'Membro ativo — $igrejaLinha'
              : 'Cadastro não está ativo',
          subtitle: ativo
              ? '${r.message.isNotEmpty ? '${r.message} ' : ''}Credencial reconhecida no ecossistema Gestão YAHWEH.'
              : r.message,
        ),
        if (r.churchName.isNotEmpty) ...[
          const SizedBox(height: 16),
          _codeRow(context, 'Igreja', r.churchName),
        ],
        if (r.titularMascarado.isNotEmpty) ...[
          const SizedBox(height: 10),
          _codeRow(context, 'Titular (mascarado)', r.titularMascarado),
        ],
        if (r.validityHint.isNotEmpty) ...[
          const SizedBox(height: 10),
          _codeRow(context, 'Validade (cadastro)', r.validityHint),
        ],
        const SizedBox(height: 20),
        Text(
          'Em caso de dúvida, a secretaria pode confirmar nome completo e documentos no painel autenticado.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static Widget _statusBanner({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade800)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _codeRow(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
