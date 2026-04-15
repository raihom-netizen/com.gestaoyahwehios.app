import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/carteirinha_staff_redirect.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Rota legada do QR da carteirinha (`/carteirinha-validar`). Sem validação online.
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStaffRedirect();
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Carteirinha'),
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
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 48,
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.85)),
                      const SizedBox(height: 16),
                      Text(
                        'Consulta online desativada',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'A credencial é válida junto à igreja emissora. '
                        'Para dúvidas ou confirmação, fale com a secretaria ou a liderança.',
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Colors.grey.shade700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Voltar'),
                      ),
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
}
