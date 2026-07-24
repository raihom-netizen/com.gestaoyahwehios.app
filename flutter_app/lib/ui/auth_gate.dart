import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/license_access_policy.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import '../services/ios_payments_gate.dart';

import 'pages/biometric_lock_page.dart';
import 'pages/change_password_page.dart';
import 'pages/completar_cadastro_membro_page.dart';
import 'login_page.dart';
import 'igreja_clean_shell.dart';
import 'widgets/global_announcement_overlay.dart';
import 'widgets/gestao_foreground_notification_snackbar.dart';
import '../services/app_connectivity_service.dart';
import '../services/app_shell_session_cache.dart';
import '../services/auth_profile_cache_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/church_funcoes_controle_service.dart';
import '../services/fcm_service.dart';
import '../services/internal_notification_inbox_service.dart';
import '../services/app_permissions.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/church_panel_tenant_gateway.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import '../services/church_panel_access_bootstrap.dart';
import '../services/church_binding_repair_coordinator.dart';
import '../services/church_chat_alert_notification_service.dart';
import '../services/church_chat_notification_prefs.dart';
import '../services/church_auto_session_service.dart';
import '../services/persistent_auth_session_service.dart';
import '../services/session_restore_service.dart';
import '../services/church_sign_out_navigation.dart';
import '../services/app_session_stability.dart';
import '../services/web_panel_stability.dart';
import '../core/firebase_auth_token_guard.dart';
import '../core/roles_permissions.dart';
import '../core/app_constants.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/auth_gate_panel_role.dart';
import 'package:gestao_yahweh/services/auth_gate_member_active.dart';
import 'package:gestao_yahweh/services/auth_gate_panel_access_service.dart';

/// Reaplica regras de gestor/master num perfil já em cache (evita «conta desativada» stale).
Map<String, dynamic> authGateNormalizeProfile(
  Map<String, dynamic> profile, {
  String? userEmail,
}) {
  final church = profile['church'] is Map
      ? Map<String, dynamic>.from(profile['church'] as Map)
      : null;
  final roleRaw = (profile['role'] ?? '').toString();
  final resolvedRole = AuthGatePanelRole.resolve(
    roleFromClaims: roleRaw,
    roleFromUserDoc: roleRaw,
    roleFromCache: roleRaw,
    churchData: church,
    userEmail: userEmail,
    cpfDigitsOrRaw: (profile['cpf'] ?? '').toString(),
  );
  final access = AuthGatePanelAccessService.resolve(
    activeFromMemberOrUser:
        profile['active'] == true || profile['ativo'] == true,
    role: resolvedRole,
    churchData: church,
    userEmail: userEmail,
    cpfDigitsOrRaw: (profile['cpf'] ?? '').toString(),
    userDocAtivo: profile['ativo'] == true,
    claimsActive: profile['claimsActive'] == true,
  );
  final active = access.active;
  return {
    ...profile,
    'role': resolvedRole,
    'active': active,
    'memberStatusPending': active ? false : access.memberStatusPending,
  };
}

String _forceCanonicalChurchId(String raw) {
  final t = raw.trim();
  if (t.startsWith('v_igreja_') && t.length > 2) {
    return t.substring(2);
  }
  if (t.startsWith('id_igreja_') && t.length > 3) {
    return t.substring(3);
  }
  return t;
}

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
        final syncFn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('syncGestorBrasilParaCristo');
        await syncFn.call(<String, dynamic>{});
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'permission-denied' || e.code == 'unauthenticated') rethrow;
        final fullFn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('ensureBrasilParaCristoAccess');
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
                      IosPaymentsGate.hideOrganizationSignup
                          ? 'No app iOS não há cadastro de nova igreja — apenas login com conta existente. '
                              'Abra gestaoyahweh.com.br no navegador para cadastrar sua igreja. '
                              'Se já é gestor ou membro, saia e entre com o e-mail vinculado.'
                          : 'Se você está abrindo uma igreja nova: use o botão abaixo e siga em duas etapas (seu nome e CPF, depois nome da igreja). Se já é membro de uma igreja no sistema, use a página inicial com seu e-mail para localizar o painel.',
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
                    if (!IosPaymentsGate.hideOrganizationSignup) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context, '/signup/completar-dados', (_) => false),
                        icon: const Icon(Icons.add_business),
                        label: const Text(
                            'Nova igreja — continuar cadastro (30 dias grátis)'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => unawaited(
                            IosPaymentsGate.openOrganizationSignupExternally()),
                        icon: const Icon(Icons.open_in_browser_rounded),
                        label: const Text('Cadastrar igreja no site'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ],
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
class _ContaDesativadaPage extends StatefulWidget {
  final User user;

  const _ContaDesativadaPage({required this.user});

  @override
  State<_ContaDesativadaPage> createState() => _ContaDesativadaPageState();
}

class _ContaDesativadaPageState extends State<_ContaDesativadaPage> {
  bool _repairing = false;
  bool _autoRepairAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoRepairIfStale());
    });
  }

  /// Cache antigo com `active: false` — tenta reparar uma vez antes de bloquear de vez.
  Future<void> _autoRepairIfStale() async {
    if (_autoRepairAttempted || _repairing) return;
    _autoRepairAttempted = true;
    if (!AppConnectivityService.instance.isOnline) return;
    await _repairAccess(silent: true);
  }

  Future<void> _repairAccess({bool silent = false}) async {
    setState(() => _repairing = true);
    try {
      final fn = FirebaseFunctions.instanceFor(
        app: firebaseDefaultApp,
        region: 'us-central1',
      )
          .httpsCallable(
        'repairMyChurchBinding',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      await fn.call<Map<dynamic, dynamic>>({});
      await AuthProfileCacheService.instance.clear(widget.user.uid);
      await widget.user.getIdToken(true);
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acesso reparado. Recarregando painel…'),
            backgroundColor: Colors.green,
          ),
        );
      }
      Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false);
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível reparar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isGestorEmail = AppConstants.isProductMasterAccount(email: user.email);

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
                      isGestorEmail
                          ? 'Seu perfil de gestor existe, mas o vínculo ativo não foi reconhecido. Use «Reparar acesso» ou saia e entre de novo.'
                          : 'Se o cadastro está ativo na igreja, toque em «Reparar acesso» para sincronizar. Caso contrário, fale com o administrador.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                        onPressed: _repairing ? null : () => _repairAccess(),
                        icon: _repairing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.healing_rounded),
                        label: Text(_repairing ? 'Reparando…' : 'Reparar acesso'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    const SizedBox(height: 10),
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

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _scheduledLoginRedirect = false;
  Timer? _signOutConfirmTimer;
  Timer? _webSessionCapTimer;
  bool _webSessionCapHit = false;
  bool _restoreInFlight = false;
  int _webSessionCapAttempts = 0;
  static const _kMaxWebSessionCapAttempts = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSessionStability.rememberUser(FirebaseAuth.instance.currentUser);
    WebPanelStability.bindLoginSession(FirebaseAuth.instance.currentUser);
    if (kIsWeb) {
      _scheduleWebSessionCap();
      unawaited(_kickEarlyWebSessionRestore());
    }
  }

  /// Web: restaura sessão persistida cedo — evita spinner infinito em authStateChanges «waiting».
  Future<void> _kickEarlyWebSessionRestore() async {
    try {
      final restored = await PersistentAuthSessionService.currentPersistedUser()
          .timeout(const Duration(milliseconds: 1800));
      if (restored != null && mounted) {
        AppSessionStability.rememberUser(restored);
        _webSessionCapAttempts = 0;
        setState(() {});
      }
    } catch (_) {}
  }

  /// Web: só redireciona ao login após restaurar sessão persistida (padrão Controle Total).
  void _scheduleWebSessionCap() {
    if (!kIsWeb) return;
    _webSessionCapTimer?.cancel();
    final delay = AppSessionStability.hasReturningSessionHints()
        ? const Duration(milliseconds: 1800)
        : const Duration(milliseconds: 700);
    _webSessionCapTimer = Timer(delay, () async {
      if (!mounted) return;
      final sync = FirebaseAuth.instance.currentUser;
      if (sync != null && !sync.isAnonymous) {
        AppSessionStability.rememberUser(sync);
        _webSessionCapAttempts = 0;
        return;
      }
      final restored =
          await PersistentAuthSessionService.currentPersistedUser();
      if (!mounted) return;
      if (restored != null) {
        AppSessionStability.rememberUser(restored);
        _webSessionCapAttempts = 0;
        setState(() {});
        return;
      }
      if (AppSessionStability.hasReturningSessionHints()) {
        _webSessionCapAttempts++;
        if (_webSessionCapAttempts < _kMaxWebSessionCapAttempts) {
          _scheduleWebSessionCap();
          return;
        }
      }
      setState(() => _webSessionCapHit = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signOutConfirmTimer?.cancel();
    _webSessionCapTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppSessionStability.onGlobalResume();
      if (kIsWeb) {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null && !u.isAnonymous) return;
      }
      _kickSessionRestore();
      if (mounted) setState(() {});
    }
  }

  void _kickSessionRestore() {
    if (_restoreInFlight) return;
    _restoreInFlight = true;
    unawaited(() async {
      try {
        final restored =
            await PersistentAuthSessionService.currentPersistedUser();
        if (restored != null && mounted) {
          AppSessionStability.rememberUser(restored);
          _scheduledLoginRedirect = false;
          setState(() {});
        }
      } finally {
        _restoreInFlight = false;
      }
    }());
  }

  void _scheduleSignOutIfStillLoggedOut() {
    _signOutConfirmTimer?.cancel();
    final hasHints = AppSessionStability.hasReturningSessionHints();
    final delay = hasHints
        ? (kIsWeb
            ? const Duration(milliseconds: 3200)
            : const Duration(milliseconds: 1800))
        : (kIsWeb
            ? const Duration(milliseconds: 900)
            : const Duration(milliseconds: 900));
    _signOutConfirmTimer = Timer(delay, () async {
      if (!mounted) return;
      final current = FirebaseAuth.instance.currentUser;
      if (current != null && !current.isAnonymous) {
        AppSessionStability.rememberUser(current);
        _scheduledLoginRedirect = false;
        if (mounted) setState(() {});
        return;
      }
      if (hasHints || AppSessionStability.hasReturningSessionHints()) {
        final restored =
            await PersistentAuthSessionService.currentPersistedUser();
        if (restored != null && mounted) {
          AppSessionStability.rememberUser(restored);
          _scheduledLoginRedirect = false;
          setState(() {});
          return;
        }
      }
      if (!mounted) return;
      await AppShellSessionCache.clear();
      AppSessionStability.clearStickyUser();
      await ChurchSignOutNavigation.redirectAfterSignOut();
    });
  }

  Future<Map<String, dynamic>?> _loadProfile(User user, {int repairDepth = 0}) async {
    final cached = await AuthProfileCacheService.instance.load(user.uid);
    if (repairDepth == 0 &&
        cached != null &&
        (cached['igrejaId'] ?? '').toString().trim().isNotEmpty) {
      final normalized = authGateNormalizeProfile(cached, userEmail: user.email);
      if (normalized['active'] == true) {
        if (normalized['active'] != cached['active']) {
          unawaited(AuthProfileCacheService.instance.save(user.uid, normalized));
        }
        return normalized;
      }
      if (AppConnectivityService.instance.isOnline) {
        final claimsFast = await _loadProfileFromClaimsFast(user, cached);
        if (claimsFast != null && claimsFast['active'] == true) {
          await AuthProfileCacheService.instance.save(user.uid, claimsFast);
          unawaited(_enrichProfileWithMemberAsync(user, claimsFast));
          return claimsFast;
        }
      }
    }
    if (repairDepth == 0 && AppConnectivityService.instance.isOnline) {
      final claimsFast = await _loadProfileFromClaimsFast(user, cached);
      if (claimsFast != null) {
        await AuthProfileCacheService.instance.save(user.uid, claimsFast);
        unawaited(_enrichProfileWithMemberAsync(user, claimsFast));
        return claimsFast;
      }
      if (AppConnectivityService.instance.isOnline) {
        final fast = await _loadProfileOnlineFast(user, cached);
        if (fast != null) {
          await AuthProfileCacheService.instance.save(user.uid, fast);
          unawaited(_enrichProfileWithMemberAsync(user, fast));
          return fast;
        }
      }
    }
    try {
      final db = firebaseDefaultFirestore;
      final loadTimeout =
          kIsWeb ? const Duration(seconds: 4) : const Duration(seconds: 6);

      // `false` = não força refresh na rede; permite abrir com sessão persistida sem internet.
      late final IdTokenResult token;
      try {
        token = await user.getIdTokenResult(false).timeout(loadTimeout);
      } catch (_) {
        if (cached != null &&
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
      // Fallback: resolve igreja pelo e-mail do gestor — omitido na web (2 queries lentas no cold start).
      if (!kIsWeb &&
          AppConnectivityService.instance.isOnline &&
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

      final igrejaSeedBeforeBind = igrejaId;
      try {
        final bound = await ChurchContextService.resolveAndBind(
          seed: igrejaId,
          userUid: user.uid,
        ).timeout(ChurchContextService.kResolveTimeout);
        if (bound.trim().isNotEmpty) igrejaId = bound.trim();
      } catch (_) {}
      if (igrejaId.trim().isEmpty) {
        final mapped =
            TenantResolverService.mapLegacySeedToCanonical(igrejaSeedBeforeBind);
        igrejaId = (mapped ?? igrejaSeedBeforeBind).trim();
        if (igrejaId.isNotEmpty) {
          try {
            await ChurchContextService.resolveAndBind(
              seed: igrejaId,
              userUid: user.uid,
            );
          } catch (_) {}
        }
      }
      igrejaId = ChurchPanelTenant.resolve(igrejaId);
      ChurchContextService.bindPanelIdImmediate(
        seed: igrejaSeedBeforeBind,
        canonicalId: igrejaId,
        userUid: user.uid,
      );

      final storedTenant = (userData['igrejaId'] ?? userData['tenantId'] ?? '')
          .toString()
          .trim();
      if (storedTenant.isNotEmpty &&
          storedTenant != igrejaId &&
          userDoc.exists) {
        await db
            .collection('users')
            .doc(user.uid)
            .update({'igrejaId': igrejaId, 'tenantId': igrejaId})
            .catchError((_) {});
      }

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
        final op = ChurchContextService.panelChurchId(igrejaId);
        try {
          return await ChurchUiCollections.churchDoc(op).get().timeout(loadTimeout);
        } catch (_) {
          return ChurchUiCollections.churchDoc(op).get(
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
        unawaited(_scheduleChurchBindingRepair(user));
        churchData = cached?['church'] is Map
            ? Map<String, dynamic>.from(cached!['church'] as Map)
            : <String, dynamic>{'id': igrejaId};
      }
      if (churchData == null &&
          cached != null &&
          (cached['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        churchData = cached['church'] is Map
            ? Map<String, dynamic>.from(cached['church'] as Map)
            : <String, dynamic>{'id': igrejaId};
      }
      if (churchData == null) {
        return null;
      }

      ChurchContextService.bindChurchData(
        churchId: igrejaId,
        data: churchData,
      );

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
      Map<String, dynamic>? memberData;
      if (igrejaId.isNotEmpty) {
        try {
          final binding = await AuthGatePanelAccessService.findMemberForUser(
            igrejaId: igrejaId,
            user: user,
            userData: userData,
          );
          memberData = binding.memberData;
          active = authGateMergeMemberUserActive(
            activeFromUser: active,
            memberData: memberData,
          );
          if (authGateMemberDocIsPending(memberData)) {
            active = false;
            memberStatusPending = true;
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
            if (ChurchRolePermissions.isDepartmentLeaderRoleKey(role)) {
              permissions = AppPermissions.mergeDepartmentLeaderModulePermissions(
                permissions,
              );
            }
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

      final access = AuthGatePanelAccessService.resolve(
        activeFromMemberOrUser: active,
        role: role,
        memberData: memberData,
        churchData: churchData,
        userEmail: user.email,
        cpfDigitsOrRaw: (userData['cpf'] ?? cached?['cpf'] ?? '').toString(),
        claimsActive: claims['active'] == true,
        userDocAtivo: userData['ativo'] == true || userData['active'] == true,
      );
      active = access.active;
      memberStatusPending = access.memberStatusPending;
      if (active && userDoc.exists) {
        unawaited(
          db.collection('users').doc(user.uid).set(
            {'ativo': true, 'active': true},
            SetOptions(merge: true),
          ).catchError((_) {}),
        );
      }

      // Regras do Firestore leem `users/{uid}.role` + vínculo à igreja; o papel efetivo do painel
      // vem muitas vezes só da ficha em `membros` (FUNCOES). Sincroniza para liberar mural/avisos.
      if (userDoc.exists && role.toString().trim().isNotEmpty) {
        try {
          final normalizedRole =
              ChurchRolePermissions.normalize(role.toString());
          if (normalizedRole.isNotEmpty) {
            final prevStored = ChurchRolePermissions.normalize(
                (userData['role'] ?? '').toString());
            final tidStored = (userData['igrejaId'] ?? userData['tenantId'] ?? '')
                .toString()
                .trim();
            if (prevStored != normalizedRole || tidStored != igrejaId) {
              unawaited(
                db.collection('users').doc(user.uid).set(
                  {
                    'role': normalizedRole,
                    'igrejaId': igrejaId,
                    'tenantId': igrejaId,
                  },
                  SetOptions(merge: true),
                ).catchError((_) {}),
              );
            }
          }
        } catch (_) {}
      }

      final result = AuthGateProfileCachePolicy.stampVerified(
        {
        'igrejaId': igrejaId,
        'role': role,
        'cpf': (userData['cpf'] ?? cached?['cpf'] ?? '').toString(),
        'active': active,
        'memberStatusPending': memberStatusPending,
        'claimsActive': claims['active'] == true,
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
        },
        source: 'server',
      );
      await AuthProfileCacheService.instance.save(user.uid, result);
      return result;
    } catch (_) {
      final c = await AuthProfileCacheService.instance.load(user.uid);
      if (c != null && (c['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        return c;
      }
      if (AppConnectivityService.instance.isOnline) {
        final via = await _loadProfileViaCallable(user);
        if (via != null) {
          await AuthProfileCacheService.instance.save(user.uid, via);
          return via;
        }
      }
      final c2 = await AuthProfileCacheService.instance.load(user.uid);
      if (c2 != null && (c2['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        return c2;
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

  /// Web + mobile: abre o painel com claims + cache local — sem esperar callable (12s+).
  Future<Map<String, dynamic>?> _loadProfileFromClaimsFast(
    User user,
    Map<String, dynamic>? cached,
  ) async {
    if (FirebaseAuthTokenGuard.isInQuotaBackoff) {
      if (cached != null &&
          (cached['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        return cached;
      }
      return null;
    }
    try {
      final token = await user
          .getIdTokenResult(false)
          .timeout(const Duration(seconds: 3));
      final claims = token.claims ?? {};
      var igrejaId =
          (claims['igrejaId'] ?? claims['tenantId'] ?? '').toString().trim();
      var role = (claims['role'] ?? '').toString().trim();
      if (igrejaId.isEmpty && cached != null) {
        igrejaId = (cached['igrejaId'] ?? '').toString().trim();
      }
      if (role.isEmpty && cached != null) {
        role = (cached['role'] ?? '').toString().trim();
      }
      if (igrejaId.isEmpty) {
        try {
          final userDoc = await firebaseDefaultFirestore
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 3));
          final userData = userDoc.data() ?? {};
          igrejaId = (userData['igrejaId'] ?? userData['tenantId'] ?? '')
              .toString()
              .trim();
          if (role.isEmpty) {
            role = (userData['role'] ?? '').toString().trim();
          }
        } catch (_) {
          try {
            final userDoc = await firebaseDefaultFirestore
                .collection('users')
                .doc(user.uid)
                .get(const GetOptions(source: Source.cache))
                .timeout(const Duration(seconds: 2));
            final userData = userDoc.data() ?? {};
            igrejaId = (userData['igrejaId'] ?? userData['tenantId'] ?? '')
                .toString()
                .trim();
            if (role.isEmpty) {
              role = (userData['role'] ?? '').toString().trim();
            }
          } catch (_) {}
        }
      }
      if (igrejaId.isEmpty) return null;

      final seedIgrejaId = igrejaId;
      try {
        igrejaId = await ChurchContextService.resolveAndBind(
          seed: igrejaId,
          userUid: user.uid,
        ).timeout(ChurchContextService.kResolveTimeout);
      } catch (_) {
        final fallback = ChurchRepository.churchId(seedIgrejaId);
        if (fallback.isNotEmpty) {
          igrejaId = fallback;
          unawaited(
            ChurchContextService.resolveAndBind(
              seed: seedIgrejaId,
              userUid: user.uid,
            ),
          );
        }
      }

      if (igrejaId.isNotEmpty) {
        final synced = await TenantResolverService.syncUserToCanonicalChurchId(
          userUid: user.uid,
          canonicalId: igrejaId,
        );
        if (synced) {
          try {
            await user.getIdToken(true);
          } catch (_) {}
        }
      }

      Map<String, dynamic> churchData;
      if (cached?['church'] is Map &&
          (cached!['igrejaId'] ?? '').toString().trim() == igrejaId) {
        churchData = Map<String, dynamic>.from(cached['church'] as Map);
      } else {
        try {
          final ch = await ChurchUiCollections.churchDoc(igrejaId)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 2));
          churchData = ch.exists
              ? (ch.data() ?? <String, dynamic>{'id': igrejaId})
              : <String, dynamic>{'id': igrejaId};
        } catch (_) {
          churchData = <String, dynamic>{'id': igrejaId};
        }
      }

      final resolvedRole = AuthGatePanelRole.resolve(
        roleFromClaims: role,
        roleFromUserDoc: role,
        roleFromCache: (cached?['role'] ?? '').toString(),
        churchData: churchData,
        userEmail: user.email,
        cpfDigitsOrRaw: (cached?['cpf'] ?? '').toString(),
      );

      final access = AuthGatePanelAccessService.resolve(
        activeFromMemberOrUser: cached?['active'] == true ||
            cached?['ativo'] == true ||
            claims['active'] == true,
        role: resolvedRole,
        churchData: churchData,
        userEmail: user.email,
        cpfDigitsOrRaw: (cached?['cpf'] ?? '').toString(),
        claimsActive: claims['active'] == true,
        userDocAtivo: cached?['ativo'] == true,
      );
      if (!access.active) return null;

      ChurchContextService.bindChurchData(
        churchId: igrejaId,
        data: churchData,
      );

      return AuthGateProfileCachePolicy.stampVerified(
        authGateNormalizeProfile(
        {
          'igrejaId': igrejaId,
          'role': resolvedRole,
          'cpf': (cached?['cpf'] ?? '').toString(),
          'active': true,
          'claimsActive': claims['active'] == true,
          'memberStatusPending': access.memberStatusPending,
          'mustChangePass': cached?['mustChangePass'] == true,
          'mustCompleteRegistration':
              cached?['mustCompleteRegistration'] == true,
          'church': churchData,
          if (cached?['subscription'] is Map)
            'subscription':
                Map<String, dynamic>.from(cached!['subscription'] as Map),
          'permissions': AppPermissions.normalizePermissions(
            cached?['permissions'],
          ),
        },
        userEmail: user.email,
      ),
        source: 'claims',
      );
    } catch (e) {
      if (FirebaseAuthTokenGuard.isQuotaExceeded(e)) {
        FirebaseAuthTokenGuard.recordQuotaExceeded(e);
      }
      if (cached != null &&
          (cached['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        return cached;
      }
      return null;
    }
  }

  /// Uma ida ao servidor (users + subscription + igreja) — evita dezenas de leituras no cliente.
  Future<Map<String, dynamic>?> _loadProfileOnlineFast(
    User user,
    Map<String, dynamic>? cached,
  ) async {
    try {
      final fn = FirebaseFunctions.instanceFor(
        app: firebaseDefaultApp,
        region: 'us-central1',
      )
          .httpsCallable(
        'getUserProfile',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
      );
      final res = await fn
          .call<Map<String, dynamic>>(<String, dynamic>{})
          .timeout(kIsWeb ? const Duration(seconds: 7) : const Duration(seconds: 8));
      final data = res.data;
      final profile = data['profile'];
      if (profile == null || profile is! Map) return null;
      final p = Map<String, dynamic>.from(profile);
      final igrejaId = (p['igrejaId'] ?? '').toString().trim();
      if (igrejaId.isEmpty) return null;

      Map<String, dynamic>? churchData;
      if (p['church'] is Map) {
        churchData = Map<String, dynamic>.from(p['church'] as Map);
      } else if (cached?['church'] is Map) {
        churchData = Map<String, dynamic>.from(cached!['church'] as Map);
      } else {
        try {
          final op = ChurchPanelTenantGateway.churchId(igrejaId.trim());
          final ch = await               ChurchUiCollections.churchDoc(op)
              .get(const GetOptions(source: Source.cache));
          if (ch.exists) churchData = ch.data();
        } catch (_) {}
      }
      churchData ??= <String, dynamic>{'id': igrejaId};

      final permissions = AppPermissions.normalizePermissions(
        p['permissions'] ?? cached?['permissions'],
      );
      final roleTxt = (p['role'] ?? cached?['role'] ?? '').toString();
      final access = AuthGatePanelAccessService.resolve(
        activeFromMemberOrUser: p['active'] == true ||
            cached?['active'] == true ||
            cached?['ativo'] == true,
        role: roleTxt,
        churchData: churchData,
        userEmail: user.email,
        cpfDigitsOrRaw: (p['cpf'] ?? cached?['cpf'] ?? '').toString(),
        claimsActive: p['active'] == true,
      );
      ChurchContextService.bindChurchData(
        churchId: igrejaId,
        data: churchData,
      );
      return AuthGateProfileCachePolicy.stampVerified(
        {
        'igrejaId': igrejaId,
        'role': roleTxt,
        'cpf': (p['cpf'] ?? cached?['cpf'] ?? '').toString(),
        'active': access.active,
        'memberStatusPending': access.memberStatusPending,
        'mustChangePass': p['mustChangePass'] == true,
        'mustCompleteRegistration': p['mustCompleteRegistration'] == true,
        'subscription': p['subscription'] is Map
            ? Map<String, dynamic>.from(p['subscription'] as Map)
            : cached?['subscription'],
        'church': churchData,
        'podeVerFinanceiro': p['podeVerFinanceiro'] ?? cached?['podeVerFinanceiro'],
        'podeVerPatrimonio': p['podeVerPatrimonio'] ?? cached?['podeVerPatrimonio'],
        'podeVerFornecedores':
            p['podeVerFornecedores'] ?? cached?['podeVerFornecedores'],
        'podeEmitirRelatoriosCompletos': p['podeEmitirRelatoriosCompletos'] ??
            cached?['podeEmitirRelatoriosCompletos'],
        'permissions': permissions,
        },
        source: 'callable',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _scheduleChurchBindingRepair(User user) async {
    if (EcoFireFlow.disableRepairMyChurchBinding) return;
    await ChurchPanelAccessBootstrap.ensureFirestoreAccess(force: false);
  }

  Future<void> _enrichProfileWithMemberAsync(
    User user,
    Map<String, dynamic> base,
  ) async {
    try {
      final enriched = await _loadProfile(user, repairDepth: 1);
      if (enriched != null) {
        await AuthProfileCacheService.instance.save(user.uid, enriched);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadProfileViaCallable(User user) async {
    return _loadProfileOnlineFast(user, null);
  }

  Widget _authGateWaitingScaffold({String? message}) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = AppSessionStability.effectiveAuthUser(
          snap.data,
          connectionState: snap.connectionState,
        );

        if (user == null || user.isAnonymous) {
          final hasHints = AppSessionStability.hasReturningSessionHints();

          // Mobile: sem sessão nem pistas — login imediato (evita tela branca após chat/mídia).
          if (!kIsWeb &&
              !hasHints &&
              snap.connectionState == ConnectionState.active) {
            return LoginPage(
              title: 'Entrar — Painel da Igreja',
              afterLoginRoute: '/painel',
              showFleetBranding: false,
            );
          }

          if (kIsWeb && _webSessionCapHit) {
            if (!_scheduledLoginRedirect) {
              _scheduledLoginRedirect = true;
              _scheduleSignOutIfStillLoggedOut();
            }
            return _authGateWaitingScaffold(message: 'A ir para o login…');
          }

          final sessionRestorePending = !_webSessionCapHit &&
              hasHints &&
              snap.connectionState == ConnectionState.waiting;
          if (sessionRestorePending) {
            _kickSessionRestore();
            final sticky = AppSessionStability.effectiveAuthUser(
              snap.data,
              connectionState: snap.connectionState,
            );
            if (sticky != null) {
              _webSessionCapTimer?.cancel();
              return _AuthGateProfileLoader(
                user: sticky,
                loadProfile: () => _loadProfile(sticky),
                initialOpenMemberDocId: widget.initialOpenMemberDocId,
                initialShellIndex: widget.initialShellIndex,
              );
            }
            return _authGateWaitingScaffold(
              message: kIsWeb ? 'A restaurar a sua sessão…' : 'A restaurar a sua sessão…',
            );
          }

          if (!_scheduledLoginRedirect) {
            _scheduledLoginRedirect = true;
            _scheduleSignOutIfStillLoggedOut();
          }
          if (kIsWeb) {
            return _authGateWaitingScaffold(message: 'A carregar…');
          }
          return _authGateWaitingScaffold();
        }

        _signOutConfirmTimer?.cancel();
        _webSessionCapTimer?.cancel();
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

class _AuthGateProfileLoaderState extends State<_AuthGateProfileLoader>
    with WidgetsBindingObserver {
  late Future<Map<String, dynamic>?> _profileFuture;
  late Future<bool> _biometricFuture;
  late Future<(Map<String, dynamic>?, bool)> _readyFuture;

  /// Perfil em RAM/disco — pinta o shell no 1.º frame sem esperar rede.
  Map<String, dynamic>? _bootstrapProfile;

  /// Mantém o painel visível ao voltar de outra aba (não repõe spinner completo).
  bool _panelEverShown = false;

  Timer? _emergencyBootstrapTimer;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocRoleSub;
  Timer? _userRoleSigDebounce;
  String? _userRoleSig;
  String _lastCachedPanelRole = '';

  void _onAuthProfileCacheUpdated(String uid, Map<String, dynamic> profile) {
    if (uid != widget.user.uid || !mounted) return;
    final normalized = authGateNormalizeProfile(
      profile,
      userEmail: widget.user.email,
    );
    final role = (normalized['role'] ?? '').toString();
    if (role == _lastCachedPanelRole && _panelEverShown) return;
    _lastCachedPanelRole = role;
    setState(() {
      _bootstrapProfile = normalized;
      _profileFuture = Future.value(normalized);
      _readyFuture = Future.wait([_profileFuture, _biometricFuture]).then(
        (list) => (list[0] as Map<String, dynamic>?, list[1] as bool),
      );
    });
  }

  /// Evita tela de erro quando há perfil gravado localmente (sessão já abriu com rede antes).
  Future<Map<String, dynamic>?> _profileFutureWithOfflineFallback() async {
    try {
      return await widget.loadProfile();
    } catch (_) {
      final c = await AuthProfileCacheService.instance.load(widget.user.uid);
      if (c != null && (c['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        return c;
      }
      rethrow;
    }
  }

  /// Abertura mais rápida: perfil em disco primeiro (web + mobile), rede em paralelo.
  Future<Map<String, dynamic>?> _profileFutureCacheFirst() async {
    final cached = await AuthProfileCacheService.instance.load(widget.user.uid);
    if (cached != null &&
        (cached['igrejaId'] ?? '').toString().trim().isNotEmpty) {
      final normalized = authGateNormalizeProfile(
        cached,
        userEmail: widget.user.email,
      );
      if (normalized['active'] == true) {
        if (normalized['active'] != cached['active']) {
          unawaited(
            AuthProfileCacheService.instance.save(widget.user.uid, normalized),
          );
        }
        unawaited(_silentRefreshProfileCache());
        unawaited(
          ChurchAutoSessionService.preheatPanelCachesCoordinated(
            tenantIdHint: (cached['igrejaId'] ?? '').toString(),
          ),
        );
        return normalized;
      }
      if (AppConnectivityService.instance.isOnline) {
        try {
          final fresh = await widget.loadProfile();
          if (fresh != null && fresh['active'] == true) {
            await AuthProfileCacheService.instance.save(widget.user.uid, fresh);
            return fresh;
          }
        } catch (_) {}
      }
      if (normalized['active'] != cached['active']) {
        unawaited(
          AuthProfileCacheService.instance.save(widget.user.uid, normalized),
        );
      }
      unawaited(_silentRefreshProfileCache());
      unawaited(
        ChurchAutoSessionService.preheatPanelCachesCoordinated(
          tenantIdHint: (cached['igrejaId'] ?? '').toString(),
        ),
      );
      return normalized;
    }
    return _profileFutureWithOfflineFallback();
  }

  Future<void> _silentRefreshProfileCache() async {
    try {
      final fresh = await widget.loadProfile();
      if (fresh != null) {
        await AuthProfileCacheService.instance.save(widget.user.uid, fresh);
      }
    } catch (_) {}
  }

  /// Evita ecrã em branco com spinner quando o cache em disco ainda não carregou.
  Future<void> _tryEmergencyBootstrapFromLocalFirestore() async {
    if (!mounted || _bootstrapProfile != null) return;
    try {
      final userDoc = await firebaseDefaultFirestore
          .collection('users')
          .doc(widget.user.uid)
          .get(const GetOptions(source: Source.cache));
      final userData = userDoc.data() ?? {};
      var igrejaId = (userData['igrejaId'] ?? userData['tenantId'] ?? '')
          .toString()
          .trim();
      if (igrejaId.isEmpty) {
        final token = await widget.user
            .getIdTokenResult(false)
            .timeout(kIsWeb ? const Duration(seconds: 2) : const Duration(seconds: 4));
        final claims = token.claims ?? {};
        igrejaId = (claims['igrejaId'] ?? claims['tenantId'] ?? '')
            .toString()
            .trim();
      }
      if (igrejaId.isEmpty || !mounted) return;
      Map<String, dynamic> churchData = <String, dynamic>{'id': igrejaId};
      try {
        final ch = await ChurchUiCollections.churchDoc(igrejaId.trim())
            .get(const GetOptions(source: Source.cache));
        final chData = ch.data();
        if (ch.exists && chData != null) {
          churchData = Map<String, dynamic>.from(chData);
        }
      } catch (_) {}
      final access = AuthGatePanelAccessService.resolve(
        activeFromMemberOrUser: userData['ativo'] == true || userData['active'] == true,
        role: (userData['role'] ?? '').toString(),
        churchData: churchData,
        userEmail: widget.user.email,
      );
      if (!access.active) return;
      final stub = AuthGateProfileCachePolicy.stampVerified(
        authGateNormalizeProfile(
        {
          'igrejaId': igrejaId,
          'role': (userData['role'] ?? '').toString(),
          'cpf': (userData['cpf'] ?? '').toString(),
          'active': true,
          'memberStatusPending': access.memberStatusPending,
          'mustChangePass': userData['mustChangePass'] == true,
          'mustCompleteRegistration':
              userData['mustCompleteRegistration'] == true,
          'church': churchData,
          'permissions': AppPermissions.normalizePermissions(
            userData['permissions'] ?? userData['permissoes'],
          ),
        },
        userEmail: widget.user.email,
      ),
        source: 'local_cache',
      );
      await AuthProfileCacheService.instance.save(widget.user.uid, stub);
      if (mounted) setState(() => _bootstrapProfile = stub);
      unawaited(
        ChurchAutoSessionService.preheatPanelCachesCoordinated(
          tenantIdHint: igrejaId,
        ),
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    AuthProfileCacheService.instance.addListener(_onAuthProfileCacheUpdated);
    WidgetsBinding.instance.addObserver(this);
    unawaited(PersistentAuthSessionService.currentPersistedUser());
    final peek = AuthProfileCacheService.instance.peek(widget.user.uid);
    if (peek != null && (peek['igrejaId'] ?? '').toString().trim().isNotEmpty) {
      final normalized = authGateNormalizeProfile(
        peek,
        userEmail: widget.user.email,
      );
      if (normalized['active'] == true ||
          normalized[AuthGateProfileMeta.accessVerified] == true) {
        _bootstrapProfile = normalized;
      }
    }
    unawaited(() async {
      final c = await AuthProfileCacheService.instance.load(widget.user.uid);
      if (!mounted) return;
      if (c != null && (c['igrejaId'] ?? '').toString().trim().isNotEmpty) {
        final normalized = authGateNormalizeProfile(
          c,
          userEmail: widget.user.email,
        );
        if (normalized['active'] == true ||
            normalized[AuthGateProfileMeta.accessVerified] == true) {
          setState(() => _bootstrapProfile = normalized);
        }
      }
    }());
    unawaited(_tryEmergencyBootstrapFromLocalFirestore());
    _emergencyBootstrapTimer = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(_tryEmergencyBootstrapFromLocalFirestore()),
    );
    _profileFuture = _profileFutureCacheFirst();
    // Biometric em paralelo ao perfil para não somar tempo de espera no mobile
    _biometricFuture = kIsWeb
        ? Future.value(false)
        : AuthService.shouldRequireBiometricUnlock()
            .catchError((_, __) => false);
    _readyFuture = Future.wait([_profileFuture, _biometricFuture])
        .then((list) => (list[0] as Map<String, dynamic>?, list[1] as bool))
        .timeout(
          kIsWeb ? const Duration(seconds: 2) : const Duration(seconds: 5),
          onTimeout: () async {
            final peek = AuthProfileCacheService.instance.peek(widget.user.uid);
            if (peek != null &&
                (peek['igrejaId'] ?? '').toString().trim().isNotEmpty) {
              return (peek, false);
            }
            final c =
                await AuthProfileCacheService.instance.load(widget.user.uid);
            if (c != null &&
                (c['igrejaId'] ?? '').toString().trim().isNotEmpty) {
              return (c, false);
            }
            throw TimeoutException('profile_load');
          },
        );
    _userDocRoleSub = firebaseDefaultFirestore
        .collection('users')
        .doc(widget.user.uid)
        .watchSafe()
        .listen(_onUsersDocSnapshotForRole);
  }

  String _roleRelevantSignature(Map<String, dynamic>? d) {
    if (d == null) return '';
    final r = (d['role'] ?? '').toString();
    final ativo = d['ativo'] == true || d['active'] == true;
    final roles = d['roles'];
    final rs = roles is List
        ? roles.map((e) => e.toString()).join('\u001f')
        : '';
    final fn = d['FUNCOES'] ?? d['funcoes'];
    final fs = fn is List
        ? fn.map((e) => e.toString()).join('\u001f')
        : '';
    final perm = d['permissoes'] ?? d['permissions'];
    final ps = perm is List
        ? (perm.map((e) => e.toString()).toList()..sort()).join('\u001f')
        : '';
    return '$r|$ativo|$rs|$fs|$ps';
  }

  void _onUsersDocSnapshotForRole(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final sig = _roleRelevantSignature(snap.data());
    _userRoleSigDebounce?.cancel();
    _userRoleSigDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      if (_userRoleSig == null) {
        _userRoleSig = sig;
        return;
      }
      if (sig == _userRoleSig) return;
      _userRoleSig = sig;
      // Força refresh dos custom claims (ex.: rebaixa admin→membro ou mudança de
      // acessos granulares) para que a alteração de papel surta efeito SEM logout.
      try {
        await widget.user
            .getIdToken(true)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // ignora falha de rede — o rebuild abaixo ainda lê users/{uid} em saliva.
      }
      if (!mounted) return;
      unawaited(_silentRefreshProfileCache());
      setState(() {
        _profileFuture = _profileFutureWithOfflineFallback();
        _readyFuture = Future.wait([_profileFuture, _biometricFuture]).then(
            (list) =>
                (list[0] as Map<String, dynamic>?, list[1] as bool));
      });
    });
  }

  @override
  void dispose() {
    AuthProfileCacheService.instance.removeListener(_onAuthProfileCacheUpdated);
    WidgetsBinding.instance.removeObserver(this);
    _emergencyBootstrapTimer?.cancel();
    _userRoleSigDebounce?.cancel();
    _userDocRoleSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    AppSessionStability.onGlobalResume();
    unawaited(_silentRefreshProfileCache());
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

  Widget _buildPanelShellFromProfile(Map<String, dynamic> p) {
    _panelEverShown = true;
    final user = widget.user;
    final active = p['active'] == true;
    final mustChangePass = p['mustChangePass'] == true;
    final churchMap = p['church'] as Map<String, dynamic>?;
    final churchDocId = (churchMap?['id'] ?? '').toString();
    final igrejaSeed = churchDocId.trim().isNotEmpty
        ? churchDocId
        : (p['igrejaId'] ?? p['tenantId'] ?? '').toString();
    final igrejaId = ChurchPanelTenant.resolve(_forceCanonicalChurchId(igrejaSeed));
    final cpf = (p['cpf'] ?? '').toString();
    final sub = (p['subscription'] as Map<String, dynamic>?);
    final church = churchMap;

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
        onComplete: () =>
            Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false),
      );
    }

    final expired = AppConnectivityService.instance.isOnline
        ? LicenseAccessPolicy.licenseAccessBlocked(
            subscription: sub,
            church: church,
          )
        : false;

    final roleTxt = (p['role'] ?? '').toString().toLowerCase();

    if (igrejaId.isNotEmpty) {
      final churchMap = church != null && church.isNotEmpty
          ? Map<String, dynamic>.from(church)
          : <String, dynamic>{'id': igrejaId};
      ChurchContextService.bindChurchData(
        churchId: igrejaId,
        data: churchMap,
      );
    }

    if (!kIsWeb) {
      unawaited(
        FcmService.instance.configure(
          uid: user.uid,
          tenantId: igrejaId,
          cpf: cpf,
          role: roleTxt,
          forceRefresh: true,
          onForegroundMessage: (msg) {
          unawaited(() async {
            if (!context.mounted) return;
            if (await ChurchChatNotificationPrefs.shouldSuppressForegroundSnack(
              msg,
            )) {
              return;
            }
            final showedChatBanner =
                await ChurchChatAlertNotificationService.instance
                    .showForegroundAlertIfNeeded(msg);
            if (!context.mounted) return;
            final isChat =
                ChurchChatNotificationPrefs.looksLikeChatNotification(msg);
            if (!(isChat && showedChatBanner)) {
              showGestaoForegroundNotificationSnackBar(context, msg);
            }
            final uid = user.uid;
            if (uid.isNotEmpty) {
              final title = (msg.notification?.title ?? msg.data['title'] ?? '')
                  .toString()
                  .trim();
              final body = (msg.notification?.body ?? msg.data['body'] ?? '')
                  .toString()
                  .trim();
              final type = (msg.data['type'] ?? msg.data['gy_module'] ?? 'generico')
                  .toString();
              if (title.isNotEmpty) {
                await InternalNotificationInboxService.deliverFromRemoteMessage(
                  uid: uid,
                  type: type,
                  title: title,
                  body: body.isEmpty ? null : body,
                  tenantId: msg.data['tenantId']?.toString(),
                  meta: Map<String, dynamic>.from(msg.data),
                );
              }
            }
          }());
        },
        ),
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
    return GlobalAnnouncementOverlay(child: dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Map<String, dynamic>?, bool)>(
      future: _readyFuture,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        Map<String, dynamic>? p;
        if (done && !snap.hasError) {
          p = snap.data?.$1;
        } else {
          p = _bootstrapProfile;
        }

        if (p != null && (!done || _panelEverShown)) {
          final mustVerifyOnline = AuthGateProfileCachePolicy.requiresOnlineVerification(p) &&
              AppConnectivityService.instance.isOnline &&
              !done;
          if (mustVerifyOnline) {
            return Scaffold(
              backgroundColor: const Color(0xFFF0F4FF),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2.8),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'A confirmar o seu acesso…',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final shell = _buildPanelShellFromProfile(p);
          if (!kIsWeb) {
            final bioEnabled = done && (snap.data?.$2 == true);
            if (bioEnabled &&
                !BiometricService.isSessionBiometricUnlocked &&
                !BiometricService.consumeSkipNextDashboardBiometricLock()) {
              return BiometricLockPage(child: shell);
            }
          }
          return shell;
        }

        if (!done) {
          return Scaffold(
            backgroundColor: const Color(0xFFF0F4FF),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 2.8),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'A preparar o seu painel…',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
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
        final resolved = pair?.$1;
        if (resolved == null) return _IgrejaNaoVinculadaPage(user: widget.user);
        return _buildPanelShellFromProfile(resolved);
      },
    );
  }
}
