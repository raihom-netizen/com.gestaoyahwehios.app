import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/constants/premium_pro_limits.dart';
import 'package:gestao_yahweh/services/biometric_auth_service.dart';
import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'package:gestao_yahweh/ui/widgets/bank_card_widget.dart';
import 'package:gestao_yahweh/ui/widgets/open_finance_entitlement_guard.dart';
import 'package:gestao_yahweh/ui/widgets/pluggy_sync_schedule_banner.dart';
import 'package:gestao_yahweh/ui/widgets/premium_pro_value_copy.dart';
import 'bank_connection_page.dart';
import 'open_finance_coverage_page.dart';
import 'supported_banks_page.dart';
import 'package:gestao_yahweh/utils/firestore_user_doc_id.dart';

/// Hub de conexões bancárias: lista `users/{uid}/bank_connections` (funcionalidade legada / desativada para novas ligações).
///
/// Com biometria ativada nas configurações, exige [authenticateWithBiometric] ao entrar
/// (camada extra para dados sensíveis — LGPD).
class OpenFinanceConnectionsScreen extends StatefulWidget {
  final String uid;
  /// Define quantas conexões são inclusas (2 padrão; contas VIP → 5).
  final String? accountEmail;
  /// `users.premiumProIncludedBankConnections` (painel Admin).
  final int? premiumProIncludedBankConnectionsOverride;

  const OpenFinanceConnectionsScreen({
    super.key,
    required this.uid,
    this.accountEmail,
    this.premiumProIncludedBankConnectionsOverride,
  });

  @override
  State<OpenFinanceConnectionsScreen> createState() => _OpenFinanceConnectionsScreenState();
}

class _OpenFinanceConnectionsScreenState extends State<OpenFinanceConnectionsScreen> {
  bool _checkingBio = true;
  bool _bioOk = false;
  StreamSubscription<fa.User?>? _authUidSub;

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    _runBiometricGate();
  }

  @override
  void dispose() {
    _authUidSub?.cancel();
    super.dispose();
  }

  Future<void> _runBiometricGate() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _checkingBio = false;
          _bioOk = true;
        });
      }
      return;
    }
    final enabled = await BiometricPreferences.isEnabled();
    if (!enabled) {
      if (mounted) {
        setState(() {
          _checkingBio = false;
          _bioOk = true;
        });
      }
      return;
    }
    final ok = await authenticateWithBiometric();
    if (!mounted) return;
    setState(() {
      _checkingBio = false;
      _bioOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingBio) {
      return Scaffold(
        appBar: AppBar(title: Text('Conexões bancárias')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_bioOk) {
      return Scaffold(
        appBar: AppBar(title: Text('Conexões bancárias')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint_rounded, size: 56, color: AppColors.primary.withValues(alpha: 0.85)),
              SizedBox(height: 16),
              Text(
                'Confirme sua identidade para ver bancos e conexões.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
              ),
              SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  setState(() => _checkingBio = true);
                  await _runBiometricGate();
                },
                icon: Icon(Icons.refresh_rounded),
                label: Text('Tentar de novo'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    return OpenFinanceEntitlementGuard(
      uid: firestoreUserDocIdForAppShell(widget.uid),
      appBarTitle: 'Conexões bancárias',
      entitledBuilder: (context, _) {
    final ref =
        FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('bank_connections');

    return Scaffold(
      appBar: AppBar(
        title: Text('Conexões bancárias'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const SupportedBanksScreen()),
              );
            },
            child: Text('Lista de bancos'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}', style: TextStyle(color: AppColors.error)));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          final n = docs.length;
          final included = PremiumProLimits.includedBankConnections(
            email: widget.accountEmail,
            adminPerUserOverride: widget.premiumProIncludedBankConnectionsOverride,
          );
          final atLimit = n >= included;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PluggySyncScheduleBanner(uid: firestoreUserDocIdForAppShell(widget.uid)),
              SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: AppColors.primary.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, color: AppColors.primary, size: 26),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Conexão segura',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: context.appTextPrimary,
                              ),
                            ),
                          ),
                          if (n > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                '$n / $included',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Compras no crédito, débito e Pix podem ser capturadas e lançadas automaticamente '
                        '(notificação ou API do agregador). Você autoriza o compartilhamento no ambiente do banco — '
                        'sem guardar número de cartão neste app.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: context.appTextSecondary,
                        ),
                      ),
                      if (atLimit) ...[
                        SizedBox(height: 12),
                        Material(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: Colors.amber.shade900),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Limite de $included bancos inclusos atingido. Não é possível contratar vagas extra. '
                                    'Remova uma conexão antiga ou use lançamentos manuais no plano Premium. Em dúvida, contacte o suporte.',
                                    style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.amber.shade900),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: atLimit
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => BankConnectionScreen(
                                          uid: firestoreUserDocIdForAppShell(widget.uid),
                                          accountEmail: widget.accountEmail,
                                          includedBankSlotsOverride:
                                              widget.premiumProIncludedBankConnectionsOverride,
                                        ),
                                  ),
                                ),
                        icon: Icon(Icons.link_rounded),
                        label: Text(atLimit ? 'Limite de bancos atingido' : 'Conectar meu banco'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      SizedBox(height: 10),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(builder: (_) => const OpenFinanceCoverageScreen()),
                          ),
                          icon: Icon(Icons.list_alt_rounded, size: 20),
                          label: Text('Guia: instituições de referência'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              const PremiumProMarketingHighlights(),
              SizedBox(height: 16),
              const PremiumProDiferencialChips(),
              SizedBox(height: 16),
              const PremiumProDepoisChecklist(),
              SizedBox(height: 16),
              const PremiumProResumoVisaoCard(),
              SizedBox(height: 20),
              Text(
                'Minhas contas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.appTextMuted,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 8),
              if (docs.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Nenhuma instituição ainda. Use o botão acima para buscar seu banco e autorizar o acesso.',
                      style: TextStyle(fontSize: 14, color: context.appTextSecondary, height: 1.4),
                    ),
                  ),
                )
              else
                Column(
                  children: docs.map((d) {
                    final m = d.data();
                    final bank = (m['bankName'] ?? m['institutionName'] ?? 'Instituição').toString();
                    final status = (m['status'] ?? '—').toString();
                    final provider = (m['provider'] ?? '').toString();
                    final ok = status.toLowerCase() == 'connected';
                    final last = m['lastSync'];
                    var syncStr = '—';
                    if (last is Timestamp) {
                      syncStr = DateFormat('dd/MM/yyyy HH:mm').format(last.toDate());
                    }
                    return BankCardWidget(
                      bankName: bank,
                      statusLabel: [
                        if (provider.isNotEmpty) provider,
                        if (ok) 'Conectado' else status,
                      ].join(' · '),
                      connected: ok,
                      balanceLabel: 'Saldo: em breve (API)',
                      lastSyncLabel: syncStr,
                    );
                  }).toList(),
                ),
            ],
          );
        },
      ),
    );
      },
    );
  }
}
