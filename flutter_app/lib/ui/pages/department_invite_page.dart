import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/login_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/department_member_integration_service.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

/// Link público: `/convite-departamento?tid=&did=` — após login, vincula o membro ao departamento.
class DepartmentInvitePage extends StatefulWidget {
  final String tenantIdOrSlug;
  final String departmentId;

  const DepartmentInvitePage({
    super.key,
    required this.tenantIdOrSlug,
    required this.departmentId,
  });

  @override
  State<DepartmentInvitePage> createState() => _DepartmentInvitePageState();
}

class _DepartmentInvitePageState extends State<DepartmentInvitePage> {
  bool _busy = false;
  String? _message;
  bool _success = false;
  StreamSubscription<User?>? _authSub;
  bool _autoJoinScheduled = false;

  Future<String?> _findMemberDocId(String tenantId, String cpfDigits) async {
    if (cpfDigits.length != 11) return null;
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros');
    final byId = await col.doc(cpfDigits).get();
    if (byId.exists) return byId.id;
    Future<String?> tryQuery(String field) async {
      final q = await col.where(field, isEqualTo: cpfDigits).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.id;
      return null;
    }
    return await tryQuery('CPF') ?? await tryQuery('cpf');
  }

  Future<void> _join() async {
    if (_busy || _success) return;
    final tidRaw = widget.tenantIdOrSlug.trim();
    final did = widget.departmentId.trim();
    if (tidRaw.isEmpty || did.isEmpty) {
      setState(() {
        _message = 'Link inválido: faltam dados da igreja ou do departamento.';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final effectiveTid =
          await TenantResolverService.resolveEffectiveTenantId(tidRaw);
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      final userChurch = (userData['igrejaId'] ?? userData['tenantId'] ?? '')
          .toString()
          .trim();
      final resolvedUserChurch = userChurch.isEmpty
          ? ''
          : await TenantResolverService.resolveEffectiveTenantId(userChurch);

      if (resolvedUserChurch.isEmpty ||
          resolvedUserChurch != effectiveTid) {
        setState(() {
          _busy = false;
          _message =
              'Sua conta não está vinculada a esta igreja. Entre com o usuário da igreja que enviou o convite.';
        });
        return;
      }

      final cpfRaw =
          (userData['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (cpfRaw.length != 11) {
        setState(() {
          _busy = false;
          _message =
              'Seu cadastro não tem CPF vinculado. Peça ao gestor para associar seu CPF ao usuário ou vincule pelo painel.';
        });
        return;
      }

      final memberId = await _findMemberDocId(effectiveTid, cpfRaw);
      if (memberId == null) {
        setState(() {
          _busy = false;
          _message =
              'Não encontramos sua ficha de membro nesta igreja com este CPF.';
        });
        return;
      }

      final deptSnap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(effectiveTid)
          .collection('departamentos')
          .doc(did)
          .get();
      if (!deptSnap.exists) {
        setState(() {
          _busy = false;
          _message = 'Este departamento não existe mais ou foi removido.';
        });
        return;
      }

      final memSnap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(effectiveTid)
          .collection('membros')
          .doc(memberId)
          .get();
      await DepartmentMemberIntegrationService.linkMember(
        tenantId: effectiveTid,
        departmentId: did,
        memberDocId: memberId,
        memberData: memSnap.data() ?? {},
      );

      final deptName = churchDepartmentNameFromData(
        deptSnap.data() ?? {},
        docId: did,
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = true;
        _message = 'Você entrou em "$deptName".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Não foi possível concluir: $e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null || !mounted || _success || _autoJoinScheduled) return;
      _autoJoinScheduled = true;
      _join();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Convite — departamento'),
        backgroundColor: Colors.white,
        foregroundColor: ThemeCleanPremium.onSurface,
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snap) {
            final user = snap.data;
            return SingleChildScrollView(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            _success
                                ? Icons.check_circle_rounded
                                : Icons.groups_rounded,
                            size: 56,
                            color: _success
                                ? const Color(0xFF2E7D32)
                                : ThemeCleanPremium.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _success
                                ? 'Tudo certo'
                                : 'Entrar no departamento',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (user == null) ...[
                            Text(
                              'Faça login com a mesma conta que você usa no painel da igreja. '
                              'Depois disso, toque em continuar para ser vinculado ao grupo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ThemeCleanPremium.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: () {
                                final tid = Uri.encodeComponent(
                                    widget.tenantIdOrSlug.trim());
                                final did = Uri.encodeComponent(
                                    widget.departmentId.trim());
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => LoginPage(
                                      title: 'Entrar — convite',
                                      afterLoginRoute:
                                          '/convite-departamento?tid=$tid&did=$did',
                                      showFleetBranding: false,
                                      backRoute: '/',
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Entrar e continuar'),
                            ),
                          ] else ...[
                            if (_busy)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              )
                            else if (_message != null)
                              Text(
                                _message!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  height: 1.4,
                                  color: _success
                                      ? const Color(0xFF2E7D32)
                                      : ThemeCleanPremium.onSurfaceVariant,
                                  fontWeight: _success
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            if (!_busy && !_success && _message != null) ...[
                              const SizedBox(height: 20),
                              OutlinedButton(
                                onPressed: _join,
                                child: const Text('Tentar de novo'),
                              ),
                            ],
                            if (_success) ...[
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/painel',
                                  (r) => false,
                                ),
                                child: const Text('Ir ao painel'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

