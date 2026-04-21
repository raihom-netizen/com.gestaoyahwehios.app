import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/license_access_policy.dart';
import '../pages/site_public_page.dart';

import 'pages/biometric_lock_page.dart';
import 'pages/change_password_page.dart';
import 'pages/completar_cadastro_membro_page.dart';
import 'igreja_clean_shell.dart';
import 'widgets/global_announcement_overlay.dart';
import '../services/app_connectivity_service.dart';
import '../services/auth_profile_cache_service.dart';
import '../services/biometric_service.dart';
import '../services/church_funcoes_controle_service.dart';
import '../services/fcm_service.dart';
import '../services/app_permissions.dart';
import '../services/tenant_resolver_service.dart';
import '../services/church_binding_repair_coordinator.dart';

/// Tela quando usuário logou mas não tem igreja vinculada em claims nem em users.
class _IgrejaNaoVinculadaPage extends StatefulWidget {
  final User user;

  const _IgrejaNaoVinculadaPage({required this.user});

  @override
  State<_IgrejaNaoVinculadaPage> createState() => _IgrejaNaoVinculadaPageState();
}

class _IgrejaNaoVinculadaPageState extends State<_IgrejaNaoVinculadaPage> {
  bool _fixing = false;

  Future<void> _ensureBrasilParaCristoAccess() async {
    setState(() => _fixing = true);
    try {
      // Primeiro tenta só sincronizar claims + users (rápido). Se falhar, tenta o seed completo.
      try {
        final syncFn = FirebaseFunctions.instance.httpsCallable('syncGestorBrasilParaCristo');
        await syncFn.call(<String, dynamic>{});
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'permission-denied' || e.code == 'unauthenticated') rethrow;
        final fullFn = FirebaseFunctions.instance.httpsCallable('ensureBrasilParaCristoAccess');
        await fullFn.call(<String, dynamic>{});
      }
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acesso corrigido. Atualizando...'), backgroundColor: Colors.green),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isBrasilParaCristoGestor = (user.email ?? '').toLowerCase() == 'raihom@gmail.com';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Gestão YAHWEH'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut().then((_) {
              Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
            }),
            child: const Text('Sair'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.church_outlined, size: 56, color: Colors.blue.shade700),
                    const SizedBox(height: 20),
                    const Text(
                      'Sua conta não está vinculada a uma igreja',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Se você está abrindo uma igreja nova: use o botão abaixo e siga em duas etapas (seu nome e CPF, depois nome da igreja). Se já é membro de uma igreja no sistema, use a página inicial com seu e-mail para localizar o painel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                    ),
                    if (isBrasilParaCristoGestor) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _fixing ? null : _ensureBrasilParaCristoAccess,
                        icon: _fixing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.build_circle),
                        label: Text(_fixing ? 'Corrigindo acesso...' : 'Garantir meu acesso (Brasil para Cristo)'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/signup/completar-dados', (_) => false),
                      icon: const Icon(Icons.add_business),
                      label: const Text('Nova igreja — continuar cadastro (30 dias grátis)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
                      icon: const Icon(Icons.home),
                      label: const Text('Ir para página inicial'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut().then((_) {
                        Navigator.pushNamedAndRemoveUntil(context, '/igreja/login', (_) => false);
                      }),
                      child: const Text('Fazer logout'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela quando o membro está com status pendente (cadastro externo) — aguardando aprovação do gestor.
class _AguardandoAprovacaoPage extends StatelessWidget {
  final User user;

  const _AguardandoAprovacaoPage({required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Gestão YAHWEH'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut().then((_) {
              Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
            }),
            child: const Text('Sair'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.schedule_rounded, size: 56, color: Colors.amber.shade700),
                    const SizedBox(height: 20),
                    const Text(
                      'Aguardando aprovação do gestor',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Seu cadastro foi recebido. O gestor da igreja precisa aprovar para criar seu acesso ao painel. Após a aprovação, entre com seu e-mail e a senha inicial 123456 (depois você pode trocar ou usar Esqueci a senha).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut().then((_) {
                        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
                      }),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sair'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela quando o usuário está logado mas a conta está desativada (ativo: false).
class _ContaDesativadaPage extends StatelessWidget {
  final User user;

  const _ContaDesativadaPage({required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Gestão YAHWEH'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut().then((_) {
              Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
            }),
            child: const Text('Sair'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.block_rounded, size: 56, color: Colors.orange.shade700),
                    const SizedBox(height: 20),
                    const Text(
                      'Sua conta está desativada',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Entre em contato com o administrador da igreja para reativar seu acesso.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut().then((_) {
                        Navigator.pushNamedAndRemoveUntil(context, '/igreja/login', (_) => false);
                      }),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sair e ir para o login'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  /// Abre a lista Membros com a ficha deste documento (ex.: QR da carteirinha lido por gestor).
  final String? initialOpenMemberDocId;

  /// Abre módulo do shell (ex.: Minha Escala) — deep link `/painel?openModule=minha_escala`.
  final int? initialShellIndex;

  const AuthGate({
    super.key,
    this.initialOpenMemberDocId,
    this.initialShellIndex,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _scheduledLoginRedirect = false;

  Future<Map<String, dynamic>?> _loadProfile(User user, {int repairDepth = 0}) async {
    Map<String, dynamic>? cached;
    if (!kIsWeb) {
      cached = await AuthProfileCacheService.instance.load(user.uid);
    }
    try {
      final db = FirebaseFirestore.instance;
      const loadTimeout = Duration(seconds: 14);

      // `false` = não força refresh na rede; permite abrir com sessão persistida sem internet.
      late final IdTokenResult token;
      try {
        token = await user.getIdTokenResult(false).timeout(loadTimeout);
      } catch (_) {
        if (!kIsWeb &&
            cached != null &&
            (cached['igrejaId'] ?? '').toString().trim().isNotEmpty) {
          return cached;
        }
        rethrow;
      }
      DocumentSnapshot<Map<String, dynamic>> userDoc;
      try {
        userDoc = await db.collection('users').doc(user.uid).get().timeout(loadTimeout);
      } catch (_) {
        userDoc = await db.collection('users').doc(user.uid).get(
              const GetOptions(source: Source.cache),
            );
      }

      final claims = token.claims ?? {};
      var igrejaId = (claims['igrejaId'] ?? claims['tenantId'] ?? '').toString().trim();
      var role = (claims['role'] ?? '').toString().trim();

      final userData = userDoc.data() ?? {};

      if (igrejaId.isEmpty) {
        igrejaId = (userData['igrejaId'] ?? userData['tenantId'] ?? '').toString().trim();
      }
      if (igrejaId.isEmpty && cached != null) {
        igrejaId = (cached['igrejaId'] ?? '').toString().trim();
      }
      // Fallback: resolve igreja pelo e-mail do gestor (ex.: Brasil para Cristo — requer rede)
      if (AppConnectivityService.instance.isOnline &&
          igrejaId.isEmpty &&
          (user.email ?? '').toString().trim().isNotEmpty) {
        try {
          final emailLower = (user.email ?? '').toString().trim().toLowerCase();
          final pair = await Future.wait([
            db
                .collection('igrejas')
                .where('email', isEqualTo: emailLower)
                .limit(1)
                .get(),
            db
                .collection('igrejas')
                .where('gestorEmail', isEqualTo: emailLower)
                .limit(1)
                .get(),
          ]);
          if (pair[0].docs.isNotEmpty) {
            igrejaId = pair[0].docs.first.id;
          } else if (pair[1].docs.isNotEmpty) {
            igrejaId = pair[1].docs.first.id;
          }
          if (igrejaId.isNotEmpty && userDoc.exists) {
            await db
                .collection('users')
                .doc(user.uid)
                .update({'igrejaId': igrejaId, 'tenantId': igrejaId})
                .catchError((_) {});
          }
        } catch (_) {}
      }
      if (role.isEmpty) {
        role = (userData['role'] ?? '').toString().trim();
      }
      if (role.isEmpty && cached != null) {
        role = (cached['role'] ?? '').toString().trim();
      }
      if (igrejaId.isEmpty) return null;

      try {
        igrejaId = await TenantResolverService.resolveEffectiveTenantId(igrejaId);
      } catch (_) {}

      final hasIgrejaInDoc = (userData['igrejaId'] ?? '').toString().trim().isNotEmpty
          || (userData['tenantId'] ?? '').toString().trim().isNotEmpty;

      Future<Map<String, dynamic>?> fetchSub() async {
        try {
          return await _fetchSubscription(db, igrejaId);
        } catch (_) {
          return null;
        }
      }

      Future<DocumentSnapshot<Map<String, dynamic>>> fetchChurch() async {
        try {
          return await db.collection('igrejas').doc(igrejaId).get().timeout(loadTimeout);
        } catch (_) {
          return db.collection('igrejas').doc(igrejaId).get(
                const GetOptions(source: Source.cache),
              );
        }
      }

      final waited = await Future.wait<dynamic>([fetchSub(), fetchChurch()]);
      var subData = waited[0] as Map<String, dynamic>?;
      final chSnap = waited[1] as DocumentSnapshot<Map<String, dynamic>>;

      if (subData == null && cached != null && cached['subscription'] is Map) {
        subData = Map<String, dynamic>.from(cached['subscription'] as Map);
      }

      Map<String, dynamic>? churchData;
      if (chSnap.exists) {
        churchData = chSnap.data();
      } else if (cached != null && cached['church'] is Map) {
        churchData = Map<String, dynamic>.from(cached['church'] as Map);
      } else if (repairDepth < 1 && AppConnectivityService.instance.isOnline) {
        if (await ChurchBindingRepairCoordinator.shouldSkipRepairDueToRecentSuccess(
            user.uid)) {
          try {
            await user.getIdToken(true);
            final retried =
                await _loadProfile(user, repairDepth: repairDepth + 1);
            if (retried != null) return retried;
          } catch (_) {}
        }
        try {
          final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable(
            'repairMyChurchBinding',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
          );
          await fn
              .call(<String, dynamic>{})
              .timeout(const Duration(seconds: 46));
          await user.getIdToken(true);
          await ChurchBindingRepairCoordinator.recordRepairSuccess(user.uid);
          return _loadProfile(user, repairDepth: repairDepth + 1);
        } catch (_) {}
      }
      if (churchData == null &&
          cached != null &&
          (cached['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        churchData = cached['church'] is Map
            ? Map<String, dynamic>.from(cached['church'] as Map)
            : <String, dynamic>{};
      }
      if (churchData == null) {
        return null;
      }

      if (!hasIgrejaInDoc && userDoc.exists) {
        await db
            .collection('users')
            .doc(user.uid)
            .update({'igrejaId': igrejaId, 'tenantId': igrejaId})
            .catchError((_) {});
      }

      // Membro em igrejas/igrejaId/membros: ativo = acesso ao painel; pendente = aguardando aprovação do gestor
      var active = userData['ativo'] == true;
      bool? podeVerFinanceiro;
      bool? podeVerPatrimonio;
      bool? podeVerFornecedores;
      bool? podeEmitirRelatoriosCompletos;
      var permissions = AppPermissions.normalizePermissions(
        userData['permissions'] ?? userData['permissoes'],
      );
      bool memberStatusPending = false;
      if (igrejaId.isNotEmpty) {
        try {
          final membersCol = db.collection('igrejas').doc(igrejaId).collection('membros');
          Map<String, dynamic>? memberData;
          final byDocId = await membersCol.doc(user.uid).get();
          if (byDocId.exists) {
            memberData = byDocId.data() ?? {};
            final status = (memberData['STATUS'] ?? memberData['status'] ?? '').toString().toLowerCase();
            if (status == 'ativo') active = true;
            if (status == 'pendente') { active = false; memberStatusPending = true; }
          }
          if (memberData == null) {
            final byAuthUid = await membersCol.where('authUid', isEqualTo: user.uid).limit(1).get();
            if (byAuthUid.docs.isNotEmpty) {
              memberData = byAuthUid.docs.first.data();
              final status = (memberData['STATUS'] ?? memberData['status'] ?? '').toString().toLowerCase();
              if (status == 'ativo') active = true;
              if (status == 'pendente') { active = false; memberStatusPending = true; }
            }
          }
          if (memberData != null) {
            podeVerFinanceiro = memberData['podeVerFinanceiro'] == true;
            podeVerPatrimonio = memberData['podeVerPatrimonio'] == true;
            podeVerFornecedores = memberData['podeVerFornecedores'] == true;
            podeEmitirRelatoriosCompletos =
                memberData['podeEmitirRelatoriosCompletos'] == true;
            final memberPerms = AppPermissions.normalizePermissions(
              memberData['permissions'] ?? memberData['permissoes'],
            );
            if (memberPerms.isNotEmpty) {
              permissions = {
                ...permissions,
                ...memberPerms,
              }.toList();
            }
            try {
              role = await ChurchFuncoesControleService.effectivePanelRoleFromMember(
                igrejaId,
                memberData,
                role,
              );
            } catch (_) {}
          }
          if (active && userDoc.exists) {
            db.collection('users').doc(user.uid).update({'ativo': true}).catchError((_) {});
          }
        } catch (_) {
          if (cached != null) {
            active = cached['active'] == true;
            memberStatusPending = cached['memberStatusPending'] == true;
            podeVerFinanceiro = cached['podeVerFinanceiro'] as bool?;
            podeVerPatrimonio = cached['podeVerPatrimonio'] as bool?;
            podeVerFornecedores = cached['podeVerFornecedores'] as bool?;
            podeEmitirRelatoriosCompletos =
                cached['podeEmitirRelatoriosCompletos'] as bool?;
            permissions = AppPermissions.normalizePermissions(cached['permissions']);
            final r = (cached['role'] ?? '').toString().trim();
            if (r.isNotEmpty) role = r;
          }
        }
      }

      final result = {
        'igrejaId': igrejaId,
        'role': role,
        'cpf': (userData['cpf'] ?? cached?['cpf'] ?? '').toString(),
        'active': active,
        'memberStatusPending': memberStatusPending,
        'mustChangePass': userData.containsKey('mustChangePass')
            ? userData['mustChangePass'] == true
            : (cached?['mustChangePass'] == true),
        'mustCompleteRegistration': userData.containsKey('mustCompleteRegistration')
            ? userData['mustCompleteRegistration'] == true
            : (cached?['mustCompleteRegistration'] == true),
        'subscription': subData,
        'church': churchData,
        'podeVerFinanceiro': podeVerFinanceiro,
        'podeVerPatrimonio': podeVerPatrimonio,
        'podeVerFornecedores': podeVerFornecedores,
        'podeEmitirRelatoriosCompletos': podeEmitirRelatoriosCompletos,
        'permissions': permissions,
      };
      if (!kIsWeb) {
        await AuthProfileCacheService.instance.save(user.uid, result);
      }
      return result;
    } catch (_) {
      if (!kIsWeb) {
        final c = await AuthProfileCacheService.instance.load(user.uid);
        if (c != null && (c['igrejaId'] ?? '').toString().trim().isNotEmpty) {
          return c;
        }
      }
      if (AppConnectivityService.instance.isOnline) {
        final via = await _loadProfileViaCallable(user);
        if (via != null) {
          if (!kIsWeb) {
            await AuthProfileCacheService.instance.save(user.uid, via);
          }
          return via;
        }
      }
      if (!kIsWeb) {
        final c2 = await AuthProfileCacheService.instance.load(user.uid);
        if (c2 != null && (c2['igrejaId'] ?? '').toString().trim().isNotEmpty) {
          return c2;
        }
      }
      return null;
    }
  }

  /// Busca subscription da igreja (em paralelo com outras operações para reduzir latência).
  static Future<Map<String, dynamic>?> _fetchSubscription(FirebaseFirestore db, String igrejaId) async {
    try {
      final subQs = await db.collection('subscriptions')
          .where('igrejaId', isEqualTo: igrejaId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (subQs.docs.isNotEmpty) return subQs.docs.first.data();
    } catch (_) {
      try {
        final subQs = await db.collection('subscriptions')
            .where('igrejaId', isEqualTo: igrejaId)
            .limit(20)
            .get();
        if (subQs.docs.isNotEmpty) {
          final sorted = subQs.docs.toList()
            ..sort((a, b) {
              final ta = a.data()['createdAt'];
              final tb = b.data()['createdAt'];
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              final aMs = ta is Timestamp ? ta.millisecondsSinceEpoch : (ta is Map ? ((ta['_seconds'] ?? ta['seconds']) as num?)?.toInt() ?? 0 : 0) * 1000;
              final bMs = tb is Timestamp ? tb.millisecondsSinceEpoch : (tb is Map ? ((tb['_seconds'] ?? tb['seconds']) as num?)?.toInt() ?? 0 : 0) * 1000;
              return bMs.compareTo(aMs);
            });
          return sorted.first.data();
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadProfileViaCallable(User user) async {
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('getUserProfile');
      final res = await fn.call<Map<String, dynamic>>(<String, dynamic>{});
      final data = res.data;
      final profile = data['profile'];
      if (profile == null || profile is! Map<String, dynamic>) return null;
      return Map<String, dynamic>.from(profile);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null || user.isAnonymous) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // Sem sessão: não ficar em spinner sobre fundo branco (web após logout).
          if (!_scheduledLoginRedirect) {
            _scheduledLoginRedirect = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser != null && !currentUser.isAnonymous) {
                return;
              }
              final nav = Navigator.of(context, rootNavigator: true);
              if (kIsWeb) {
                try {
                  final p = await SharedPreferences.getInstance();
                  await p.remove('last_route');
                } catch (_) {}
              }
              if (!mounted) return;
              final currentUserAfterCleanup = FirebaseAuth.instance.currentUser;
              if (currentUserAfterCleanup != null &&
                  !currentUserAfterCleanup.isAnonymous) {
                return;
              }
              // Web → site de divulgação (/); app → /login.
              final dest = kIsWeb ? '/' : '/login';
              nav.pushNamedAndRemoveUntil(dest, (_) => false);
            });
          }
          // Web: mostrar divulgação já no 1º frame (evita tela branca até o replace da URL).
          if (kIsWeb) {
            return const SitePublicPage();
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        _scheduledLoginRedirect = false;
        return _AuthGateProfileLoader(
          user: user,
          loadProfile: () => _loadProfile(user),
          initialOpenMemberDocId: widget.initialOpenMemberDocId,
          initialShellIndex: widget.initialShellIndex,
        );
      },
    );
  }
}

class _AuthGateProfileLoader extends StatefulWidget {
  final User user;
  final Future<Map<String, dynamic>?> Function() loadProfile;
  final String? initialOpenMemberDocId;
  final int? initialShellIndex;

  const _AuthGateProfileLoader({
    required this.user,
    required this.loadProfile,
    this.initialOpenMemberDocId,
    this.initialShellIndex,
  });

  @override
  State<_AuthGateProfileLoader> createState() => _AuthGateProfileLoaderState();
}

class _AuthGateProfileLoaderState extends State<_AuthGateProfileLoader> {
  late Future<Map<String, dynamic>?> _profileFuture;
  late Future<bool> _biometricFuture;
  late Future<(Map<String, dynamic>?, bool)> _readyFuture;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocRoleSub;
  Timer? _userRoleSigDebounce;
  String? _userRoleSig;

  /// Evita tela de erro quando há perfil gravado localmente (sessão já abriu com rede antes).
  Future<Map<String, dynamic>?> _profileFutureWithOfflineFallback() async {
    try {
      return await widget.loadProfile();
    } catch (_) {
      if (!kIsWeb) {
        final c = await AuthProfileCacheService.instance.load(widget.user.uid);
        if (c != null && (c['igrejaId'] ?? '').toString().trim().isNotEmpty) {
          return c;
        }
      }
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _profileFuture = _profileFutureWithOfflineFallback();
    // Biometric em paralelo ao perfil para não somar tempo de espera no mobile
    _biometricFuture = kIsWeb
        ? Future.value(false)
        : BiometricService().isEnabled().catchError((_, __) => false);
    _readyFuture = Future.wait([_profileFuture, _biometricFuture])
        .then((list) => (list[0] as Map<String, dynamic>?, list[1] as bool));
    _userDocRoleSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .snapshots()
        .listen(_onUsersDocSnapshotForRole);
  }

  String _roleRelevantSignature(Map<String, dynamic>? d) {
    if (d == null) return '';
    final r = (d['role'] ?? '').toString();
    final roles = d['roles'];
    final rs = roles is List
        ? roles.map((e) => e.toString()).join('\u001f')
        : '';
    final fn = d['FUNCOES'] ?? d['funcoes'];
    final fs = fn is List
        ? fn.map((e) => e.toString()).join('\u001f')
        : '';
    return '$r|$rs|$fs';
  }

  void _onUsersDocSnapshotForRole(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final sig = _roleRelevantSignature(snap.data());
    _userRoleSigDebounce?.cancel();
    _userRoleSigDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_userRoleSig == null) {
        _userRoleSig = sig;
        return;
      }
      if (sig != _userRoleSig) {
        _userRoleSig = sig;
        setState(() {
          _profileFuture = _profileFutureWithOfflineFallback();
          _readyFuture = Future.wait([_profileFuture, _biometricFuture]).then(
              (list) =>
                  (list[0] as Map<String, dynamic>?, list[1] as bool));
        });
      }
    });
  }

  @override
  void dispose() {
    _userRoleSigDebounce?.cancel();
    _userDocRoleSub?.cancel();
    super.dispose();
  }

  void _retryProfile() {
    setState(() {
      _profileFuture = _profileFutureWithOfflineFallback();
      _readyFuture = Future.wait([_profileFuture, _biometricFuture])
          .then((list) => (list[0] as Map<String, dynamic>?, list[1] as bool));
    });
  }

  bool _isConnectionError(Object e) {
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      return code == 'unavailable' ||
          code == 'internal' ||
          code == 'deadline-exceeded' ||
          code == 'aborted' ||
          code == 'cancelled';
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('failed to fetch') ||
        msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('offline') ||
        msg.contains('unreachable') ||
        msg.contains('connection reset') ||
        msg.contains('host lookup') ||
        msg.contains('channel-error');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Map<String, dynamic>?, bool)>(
      future: _readyFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError && _isConnectionError(snap.error!)) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off, size: 64, color: Colors.orange.shade700),
                    const SizedBox(height: 16),
                    const Text(
                      'Não foi possível conectar ao servidor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Verifique sua internet. O app usará dados em cache quando possível.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _retryProfile,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut().then((_) {
                        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
                      }),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Erro ao carregar perfil.', style: TextStyle(color: Colors.grey.shade700)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retryProfile,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final pair = snap.data;
        final p = pair?.$1;
        final bioEnabled = pair?.$2 ?? false;

        if (p == null) return _IgrejaNaoVinculadaPage(user: widget.user);

        final user = widget.user;
        final active = p['active'] == true;
        final mustChangePass = p['mustChangePass'] == true;
        final igrejaId = (p['igrejaId'] ?? '').toString();
        final cpf = (p['cpf'] ?? '').toString();
        final sub = (p['subscription'] as Map<String, dynamic>?);
        final church = p['church'] as Map<String, dynamic>?;

        if (!active) {
          if (p['memberStatusPending'] == true) {
            return _AguardandoAprovacaoPage(user: user);
          }
          return _ContaDesativadaPage(user: user);
        }

        if (mustChangePass) {
          return ChangePasswordPage(
            tenantId: igrejaId,
            cpf: cpf,
            force: true,
          );
        }

        final mustCompleteRegistration = p['mustCompleteRegistration'] == true;
        if (mustCompleteRegistration) {
          return CompletarCadastroMembroPage(
            tenantId: igrejaId,
            cpf: cpf,
            onComplete: () => Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false),
          );
        }

        final expired = AppConnectivityService.instance.isOnline
            ? LicenseAccessPolicy.licenseAccessBlocked(subscription: sub, church: church)
            : false;

        final roleTxt = (p['role'] ?? '').toString().toLowerCase();

        if (!kIsWeb) {
          FcmService.instance.configure(
            uid: user.uid,
            tenantId: igrejaId,
            cpf: cpf,
            role: roleTxt,
            onForegroundMessage: (msg) {
              if (!context.mounted) return;
              final title = (msg.notification?.title ?? '').trim();
              final body = (msg.notification?.body ?? '').trim();
              final text = title.isNotEmpty
                  ? '$title${body.isNotEmpty ? ' — $body' : ''}'
                  : (body.isNotEmpty ? body : 'Nova notificação recebida');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(text),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  backgroundColor: const Color(0xFF0F172A),
                  duration: const Duration(seconds: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              );
            },
          );
        }
        final dashboard = IgrejaCleanShell(
          tenantId: igrejaId,
          cpf: cpf,
          role: roleTxt,
          trialExpired: expired,
          subscription: sub,
          podeVerFinanceiro: p['podeVerFinanceiro'] == true,
          podeVerPatrimonio: p['podeVerPatrimonio'] == true,
          podeVerFornecedores: p['podeVerFornecedores'] == true,
          podeEmitirRelatoriosCompletos:
              p['podeEmitirRelatoriosCompletos'] == true,
          permissions: AppPermissions.normalizePermissions(p['permissions']),
          initialOpenMemberDocId: widget.initialOpenMemberDocId,
          initialShellIndex: widget.initialShellIndex,
        );
        final withAnnouncement =
            GlobalAnnouncementOverlay(child: dashboard);
        // Aviso só depois do desbloqueio por biometria (filho do lock), senão o diálogo competia com a tela de digital.
        if (bioEnabled) {
          if (BiometricService.consumeSkipNextDashboardBiometricLock()) {
            return withAnnouncement;
          }
          return BiometricLockPage(child: withAnnouncement);
        }
        return withAnnouncement;
      },
    );
  }
}
