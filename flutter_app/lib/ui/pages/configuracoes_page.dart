import 'dart:async' show TimeoutException, unawaited;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/fcm_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/theme_mode_provider.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/global_tenant_audit_service.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/ui/pages/church_panel_diagnostic_page.dart';
import 'package:gestao_yahweh/ui/pages/church_sync_test_page.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/church_sign_out_navigation.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/utils/firestore_json_safe.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/core/media_cache_preferences.dart';
import 'package:gestao_yahweh/ui/widgets/church_payment_receiving_settings_section.dart';
import 'package:gestao_yahweh/ui/widgets/version_footer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

/// Chaves SharedPreferences para notificações
const String _keyNotifAvisos = 'notif_avisos';
const String _keyNotifEscalas = 'notif_escalas';
const String _keyNotifEventos = 'notif_eventos';
const String _keyNotifAniversariantes = 'notif_aniversariantes';
const String _keyNotifEmail = 'notif_email';
const String _keyNotifCelular = 'notif_celular';
const String _keyNotifWeb = 'notif_web';
const String _keyNotif1Dia = 'notif_1dia';
const String _keyNotif60Min = 'notif_60min';
const String _keyNotifMinutos = 'notif_minutos'; // personalizado

class ConfiguracoesPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Permissões granulares (ex.: `configuracoes_banco`) definidas pelo gestor no cadastro.
  final List<String>? permissions;
  /// Doc `subscriptions` mais recente (mesmo do shell) — exibir estado da licença da igreja.
  final Map<String, dynamic>? subscription;

  const ConfiguracoesPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
    this.subscription,
  });

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  late bool _notifAvisos, _notifEscalas, _notifEventos, _notifChat,
      _notifAniversariantes;
  late String _notifChatAlertMode;
  late bool _notifEmail, _notifCelular, _notifWeb;
  late bool _notif1Dia, _notif60Min;
  late TextEditingController _notifMinutosCtrl;
  bool _loading = true;
  final _sugestaoCtrl = TextEditingController();
  bool _sugestaoEnviando = false;
  bool _sugestaoEnviada = false;
  final _biometricService = BiometricService();
  bool _bioCapable = false;
  bool _bioEnabled = false;
  bool _bioToggling = false;
  bool _cacheFotosPerfilNoAparelho = true;
  SubscriptionGuardState? _subscriptionGuard;
  bool _userAtivoNoPainel = false;
  String _accountEmailDisplay = '';
  String? _operationalTenantId;
  GlobalTenantAuditReport? _globalAudit;
  bool _churchSyncDiagnosticLoading = false;

  String get _effectiveTenantId =>
      (_operationalTenantId ?? widget.tenantId).trim();

  bool get _canManageDiagnostic {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  Future<void> _runChurchSyncDiagnostic() async {
    if (_churchSyncDiagnosticLoading) return;
    setState(() => _churchSyncDiagnosticLoading = true);
    try {
      final report = await GlobalTenantAuditService.run(
        seedTenantId: _effectiveTenantId,
        userUid: FirebaseAuth.instance.currentUser?.uid,
      );
      if (!mounted) return;
      setState(() {
        _globalAudit = report;
        _churchSyncDiagnosticLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _churchSyncDiagnosticLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Diagnóstico falhou: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _notifMinutosCtrl = TextEditingController(text: '60');
    _loadPrefs();
    final seed = widget.tenantId.trim();
    if (seed.isNotEmpty) {
      unawaited(
        ChurchOperationalPaths.resolveCached(seed).then((op) {
          if (!mounted || op.isEmpty) return;
          setState(() => _operationalTenantId = op);
        }),
      );
    }
  }

  @override
  void dispose() {
    _notifMinutosCtrl.dispose();
    _sugestaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final minutos = prefs.getString(_keyNotifMinutos) ?? '60';
    _notifMinutosCtrl.text = minutos;
    final u = FirebaseAuth.instance.currentUser;
    final email = (u?.email ?? '').trim();

    if (!mounted) return;
    setState(() {
      _notifAvisos = prefs.getBool(_keyNotifAvisos) ?? true;
      _notifEscalas = prefs.getBool(_keyNotifEscalas) ?? true;
      _notifEventos = prefs.getBool(_keyNotifEventos) ?? true;
      _notifChat =
          prefs.getBool(ChurchChatNotificationPrefs.sharedPrefsKey) ?? true;
      _notifChatAlertMode = ChurchChatNotificationPrefs.normalizeAlertMode(
        prefs.getString(ChurchChatNotificationPrefs.sharedPrefsAlertModeKey) ??
            ChurchChatNotificationPrefs.alertModeSound,
      );
      _notifAniversariantes = prefs.getBool(_keyNotifAniversariantes) ?? true;
      _notifEmail = prefs.getBool(_keyNotifEmail) ?? true;
      _notifCelular = prefs.getBool(_keyNotifCelular) ?? true;
      _notifWeb = prefs.getBool(_keyNotifWeb) ?? true;
      _notif1Dia = prefs.getBool(_keyNotif1Dia) ?? true;
      _notif60Min = prefs.getBool(_keyNotif60Min) ?? true;
      _cacheFotosPerfilNoAparelho =
          prefs.getBool(kPrefMemberPhotoDiskCacheV1) ?? true;
      _accountEmailDisplay = email.isNotEmpty ? email : '—';
      _userAtivoNoPainel = u != null;
      _loading = false;
    });

    unawaited(_hydrateSettingsFromRemote(prefs));
  }

  /// Firestore / biometria em background — não bloqueia a abertura da página.
  Future<void> _hydrateSettingsFromRemote(SharedPreferences prefs) async {
    if (!kIsWeb) {
      try {
        final capable = await _biometricService
            .isDeviceBiometricCapable()
            .timeout(const Duration(seconds: 4));
        final bioOn =
            await _biometricService.isEnabled().timeout(const Duration(seconds: 4));
        if (mounted) {
          setState(() {
            _bioCapable = capable;
            _bioEnabled = bioOn;
          });
        }
      } catch (_) {}
    }

    var av = prefs.getBool(_keyNotifAvisos) ?? true;
    var ev = prefs.getBool(_keyNotifEventos) ?? true;
    var es = prefs.getBool(_keyNotifEscalas) ?? true;
    var ch = prefs.getBool(ChurchChatNotificationPrefs.sharedPrefsKey) ?? true;
    var aniv = prefs.getBool(_keyNotifAniversariantes) ?? true;
    var chatAlertMode = ChurchChatNotificationPrefs.normalizeAlertMode(
      prefs.getString(ChurchChatNotificationPrefs.sharedPrefsAlertModeKey) ??
          ChurchChatNotificationPrefs.alertModeSound,
    );
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 8));
        final d = doc.data();
        if (d != null) {
          if (d['pushAvisos'] is bool) av = d['pushAvisos'] as bool;
          if (d['pushEventos'] is bool) ev = d['pushEventos'] as bool;
          if (d['pushEscalas'] is bool) es = d['pushEscalas'] as bool;
          if (d['pushChat'] is bool) ch = d['pushChat'] as bool;
          if (d['pushAniversariantes'] is bool) {
            aniv = d['pushAniversariantes'] as bool;
          }
          final rawAlertMode = d['pushChatAlertMode'];
          if (rawAlertMode is String && rawAlertMode.trim().isNotEmpty) {
            chatAlertMode =
                ChurchChatNotificationPrefs.normalizeAlertMode(rawAlertMode);
          }
        }
      } catch (_) {}
    }
    await prefs.setBool(_keyNotifAvisos, av);
    await prefs.setBool(_keyNotifEventos, ev);
    await prefs.setBool(_keyNotifEscalas, es);
    await prefs.setBool(ChurchChatNotificationPrefs.sharedPrefsKey, ch);
    await prefs.setBool(_keyNotifAniversariantes, aniv);
    await prefs.setString(
      ChurchChatNotificationPrefs.sharedPrefsAlertModeKey,
      chatAlertMode,
    );
    await _loadAccountAndLicenseSnapshot();
    if (!mounted) return;
    setState(() {
      _notifAvisos = av;
      _notifEscalas = es;
      _notifEventos = ev;
      _notifChat = ch;
      _notifAniversariantes = aniv;
      _notifChatAlertMode = chatAlertMode;
    });
  }

  Future<void> _loadAccountAndLicenseSnapshot() async {
    final authUser = FirebaseAuth.instance.currentUser;
    final email = (authUser?.email ?? '').trim();
    if (email.isNotEmpty) {
      _accountEmailDisplay = email;
    }
    SubscriptionGuardState? guard;
    try {
      final tid = _effectiveTenantId;
      if (tid.isNotEmpty) {
        final op = await ChurchOperationalPaths.resolveCached(tid);
        final chSnap = await ChurchOperationalPaths.churchDoc(op)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 8));
        guard = SubscriptionGuard.evaluate(
          church: chSnap.data(),
          subscription: widget.subscription,
        );
      } else {
        guard = SubscriptionGuard.evaluate(
          church: null,
          subscription: widget.subscription,
        );
      }
    } catch (_) {
      guard = SubscriptionGuard.evaluate(
        church: null,
        subscription: widget.subscription,
      );
    }
    var userAtivo = authUser != null;
    if (authUser != null) {
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(authUser.uid)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 6));
        userAtivo = uDoc.data()?['ativo'] == true;
      } catch (_) {}
    }
    _subscriptionGuard = guard;
    _userAtivoNoPainel = userAtivo;
  }

  Future<void> _trocarConta(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Trocar de conta'),
        content: const Text(
          'Você sairá desta sessão neste aparelho e poderá entrar com outra conta '
          'Google, Apple ou e-mail e senha.\n\nContinuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair e ir para Entrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BiometricService().disableForThisDevice();
      await ChurchSignOutNavigation.signOutForAccountSwitch();
    } catch (_) {}
  }

  Future<void> _onBiometricSwitch(bool wantOn) async {
    if (kIsWeb || _bioToggling) return;
    if (!wantOn) {
      setState(() => _bioToggling = true);
      await _biometricService.disableForThisDevice();
      if (mounted) {
        setState(() {
          _bioEnabled = false;
          _bioToggling = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Desbloqueio por digital/Face ID desativado neste aparelho.')),
        );
      }
      return;
    }
    setState(() => _bioToggling = true);
    final ok = await _biometricService.enableUnlockWithBiometrics();
    if (!mounted) return;
    setState(() => _bioToggling = false);
    if (ok) {
      setState(() => _bioEnabled = true);
      if (FirebaseAuth.instance.currentUser != null) {
        await ChurchAutoSessionService.persistAfterSuccessfulPainelLogin();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Digital/Face ID ativado só na tela Entrar. Google/Apple ou e-mail guardados '
            'reabrem a sessão. Outra conta: «Trocar de conta».',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível confirmar a biometria. Tente de novo ou verifique as configurações do aparelho.')),
      );
    }
  }

  Future<void> _saveNotif(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  /// Avisos, eventos e escalas: Firestore + tópicos FCM (app instalado). Padrão true.
  Future<void> _savePushPref(String spKey, String firestoreField, bool v) async {
    await _saveNotif(spKey, v);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {firestoreField: v},
        SetOptions(merge: true),
      );
    } catch (_) {}
    if (!kIsWeb) {
      await FcmService.instance.syncPreferencePushTopics(
        uid: user.uid,
        tenantId: widget.tenantId,
      );
    }
  }

  bool get _restrictedMemberSettings => AppPermissions.isRestrictedMember(widget.role);

  bool get _showMercadoPagoChurchSettings =>
      AppPermissions.canViewChurchMercadoPagoSettings(
        widget.role,
        permissions: widget.permissions,
      );

  bool get _showPaymentReceivingSettings =>
      AppPermissions.canManageChurchPaymentReceiving(
        widget.role,
        permissions: widget.permissions,
      );

  /// Método de login atual (texto curto para a secção «Conta Google / e-mail»).
  String get _connectedLoginMethodLabel {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return '—';
    for (final p in u.providerData) {
      switch (p.providerId) {
        case 'google.com':
          return 'Google';
        case 'apple.com':
          return 'Apple';
        case 'password':
          return 'E-mail e senha';
        default:
          break;
      }
    }
    return 'Conta ligada';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(
        title: const Text('Configurações'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: padding,
                children: [
                  if (_restrictedMemberSettings) ...[
                    _SectionTitle(
                      icon: Icons.notifications_active_rounded,
                      title: 'Notificações',
                    ),
                    _buildNotificacoesCard(),
                    const SizedBox(height: 20),
                    _SectionTitle(
                      icon: Icons.fingerprint_rounded,
                      title: 'Acesso ao app',
                    ),
                    _buildBiometricCard(),
                    const SizedBox(height: 20),
                    _SectionTitle(
                      icon: Icons.switch_account_rounded,
                      title: 'Conta',
                    ),
                    _buildTrocarContaCard(context),
                    const SizedBox(height: 24),
                    ..._buildLegalAndVersionSection(context),
                    const SizedBox(height: 32),
                  ] else ...[
                  _SectionTitle(
                    icon: Icons.switch_account_rounded,
                    title: 'Conta Google / e-mail',
                  ),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.smartphone_rounded,
                                color: Color(0xFF0F766E),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Quem está ligado neste aparelho',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey.shade900,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Forma de entrada: $_connectedLoginMethodLabel',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.alternate_email_rounded,
                                color: ThemeCleanPremium.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'E-mail da sessão',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    _accountEmailDisplay,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 20,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Para usar outra conta neste telemóvel',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const _ConfigHelpBullet(
                                text:
                                    'Toque no botão verde «Trocar de conta» abaixo.',
                              ),
                              const _ConfigHelpBullet(
                                text:
                                    'Na tela Entrar, pode escolher outra conta Google, entrar com Apple (iPhone) ou outro e-mail e senha.',
                              ),
                              const _ConfigHelpBullet(
                                text:
                                    'Se usa Google, o telemóvel mostra o seletor de contas para escolher qual usar.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _trocarConta(context),
                          icon: const Icon(Icons.logout_rounded, size: 22),
                          label: const Text('Trocar de conta'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Digital ou Face ID continuam iguais às opções que marcou na tela Entrar '
                          '(«Lembrar neste aparelho» + biometria).',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle(
                    icon: Icons.verified_user_rounded,
                    title: 'Estado e licença da igreja',
                  ),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStatusChip(
                                label: 'Utilizador',
                                value: _userAtivoNoPainel ? 'Ativo' : 'Verificar cadastro',
                                ok: _userAtivoNoPainel,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MiniStatusChip(
                                label: 'Licença igreja',
                                value: _subscriptionGuard?.masterBadgeLabel ?? '—',
                                ok: _subscriptionGuard != null &&
                                    !(_subscriptionGuard!.blocked),
                              ),
                            ),
                          ],
                        ),
                        if (_subscriptionGuard?.dataVencimento != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Referência de vigência: ${_fmtShortDate(_subscriptionGuard!.dataVencimento!)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Divider(height: 1, color: Colors.grey.shade200),
                        const SizedBox(height: 12),
                        Text(
                          'Versão do aplicativo (controlo interno)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          appVersionFull,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'Build $appBuildNumber · marketing $appVersion',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_restrictedMemberSettings) ...[
                    _SectionTitle(icon: Icons.palette_outlined, title: 'Aparência'),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.light_mode_rounded, color: ThemeCleanPremium.primary),
                            ),
                            title: const Text('Modo claro', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text('O app utiliza apenas o tema claro.'),
                            trailing: const Icon(Icons.check_circle_rounded, color: ThemeCleanPremium.success),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Para melhor leitura e consistência, o Gestão YAHWEH está disponível somente no modo claro.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                          if (ThemeModeScope.of(context) != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    ThemeModeScope.of(context)?.setMode(ThemeMode.light);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tema: modo claro ativado.')));
                                  },
                                  icon: const Icon(Icons.light_mode_rounded, size: 18),
                                  label: const Text('Garantir modo claro'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_showPaymentReceivingSettings) ...[
                    ChurchPaymentReceivingSettingsSection(
                      tenantId: widget.tenantId,
                      showMercadoPagoCredentials: _showMercadoPagoChurchSettings,
                    ),
                  ],
                  _SectionTitle(icon: Icons.fingerprint_rounded, title: 'Acesso ao app'),
                  _buildBiometricCard(),
                  if (!kIsWeb) ...[
                    ..._buildNativeAppStoreUpdateSection(context),
                    _SectionTitle(
                        icon: Icons.speed_rounded, title: 'Desempenho do app'),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.photo_library_rounded,
                                  color: ThemeCleanPremium.primary),
                            ),
                            title: const Text(
                              'Guardar fotos de perfil no aparelho',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Membros, escalas e módulos carregam mais rápido com cache local. '
                              'O app sincroniza em segundo plano ao voltar ao painel (sem avisos). '
                              'Desligue para poupar espaço — as fotos voltam a baixar da internet.',
                              style: TextStyle(fontSize: 12.5),
                            ),
                            value: _cacheFotosPerfilNoAparelho,
                            onChanged: (v) async {
                              setState(() => _cacheFotosPerfilNoAparelho = v);
                              await MediaCachePreferences
                                  .setMemberPhotoDiskCacheEnabled(v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _SectionTitle(icon: Icons.notifications_active_rounded, title: 'Notificações e acesso'),
                  _buildNotificacoesCard(),
                  if (_canManageDiagnostic) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(
                      icon: Icons.sync_problem_rounded,
                      title: 'Diagnóstico Firestore + Storage',
                    ),
                    _buildChurchSyncDiagnosticCard(context),
                  ],
                  const SizedBox(height: 24),
                  ..._buildBackupSection(context),
                  ..._buildDicasSection(),
                  const SizedBox(height: 24),
                  ..._buildLegalAndVersionSection(context),
                  const SizedBox(height: 32),
                  ],
                ],
              ),
      ),
    );
  }

  List<Widget> _buildLegalAndVersionSection(BuildContext context) {
    return [
      _SectionTitle(
        icon: Icons.policy_outlined,
        title: 'Legal e versão',
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.description_outlined,
                  color: ThemeCleanPremium.primary),
              title: const Text(
                'Termos de uso',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => VersionFooter.openLegalRoute(context, '/termodeuso'),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.privacy_tip_outlined,
                  color: ThemeCleanPremium.primary),
              title: const Text(
                'Política de privacidade',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () =>
                  VersionFooter.openLegalRoute(context, '/privacidade'),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
              child: Text(
                'Versão ${appVersionPanelLabel}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildNativeAppStoreUpdateSection(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return [
        const SizedBox(height: 24),
        const _SectionTitle(
          icon: Icons.shop_2_outlined,
          title: 'Atualizar na Google Play',
        ),
        _buildPlayStoreUpdateCard(context),
        const SizedBox(height: 24),
      ];
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return [
        const SizedBox(height: 24),
        const _SectionTitle(
          icon: Icons.apple_rounded,
          title: 'Atualizar no iPhone (TestFlight)',
        ),
        _buildTestFlightUpdateCard(context),
        const SizedBox(height: 24),
      ];
    }
    return const [];
  }

  Widget _buildPlayStoreUpdateCard(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Versão instalada: v$appVersion+$appBuildNumber',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Android: abra a Google Play para instalar ou atualizar o app oficial '
            'Gestão Yahweh - Igrejas.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri.parse(AppConstants.gestaoYahwehPlayStoreUrl);
              if (!await canLaunchUrl(uri)) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Não foi possível abrir a Google Play.'),
                  ),
                );
                return;
              }
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            label: const Text('Abrir na Google Play'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF01875F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestFlightUpdateCard(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Versão instalada: v$appVersion+$appBuildNumber',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppConstants.marketingDownloadIosTestFlightHint,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri.parse(AppConstants.gestaoYahwehTestFlightUrl);
              if (!await canLaunchUrl(uri)) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Não foi possível abrir o link do TestFlight.'),
                  ),
                );
                return;
              }
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            label: const Text('Abrir TestFlight — instalar/atualizar'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrocarContaCard(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            _accountEmailDisplay,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _trocarConta(context),
            icon: const Icon(Icons.logout_rounded, size: 22),
            label: const Text('Trocar de conta'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kIsWeb)
            Text(
              'Digital ou Face ID no app instalado (Android e iOS).',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            )
          else if (!_bioCapable)
            Text(
              'Este aparelho não tem biometria disponível.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            )
          else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.fingerprint_rounded,
                color: ThemeCleanPremium.primary,
              ),
              title: const Text(
                'Desbloquear com digital / Face ID',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Só na tela de entrar (login). No painel e no chat não pede digital de novo.',
                style: TextStyle(fontSize: 12.5),
              ),
              value: _bioEnabled,
              onChanged: _bioToggling ? null : _onBiometricSwitch,
            ),
        ],
      ),
    );
  }

  Widget _buildChurchSyncDiagnosticCard(BuildContext context) {
    final audit = _globalAudit;
    final d = audit?.syncReport;
    final counts = audit?.moduleCounts;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Firestore e Storage são uma única estrutura — o mesmo '
            '`churchId` em `igrejas/{id}` e `igrejas/{id}/`.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          if (_churchSyncDiagnosticLoading)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (d != null) ...[
            _diagLine('Church ID', d.resolvedChurchId),
            _diagLine('Seed (entrada)', d.seedTenantId),
            _diagLine('Firestore Path', d.firestorePath),
            _diagLine('Storage Path', d.storageRootPath ?? '—'),
            _diagLine('Bucket', d.storageBucket),
            _diagLine(
              'Firestore ativo',
              d.firestoreActive == true ? 'sim' : (d.firestoreActive == false ? 'não' : '—'),
            ),
            _diagLine(
              'Storage ativo',
              d.storageActive == true ? 'sim' : (d.storageActive == false ? 'não' : '—'),
            ),
            _diagLine(
              'Alinhado',
              d.storageAligned ? 'sim' : 'NÃO — abortar uploads',
            ),
            _diagLine('Campos Firestore', '${d.fieldCount}'),
            _diagLine(
              'Última leitura',
              d.lastReadAt?.toIso8601String() ?? '—',
            ),
            _diagLine(
              'Último upload',
              d.lastUploadPath != null
                  ? '${d.lastUploadAt?.toIso8601String() ?? ''}\n${d.lastUploadPath}'
                  : '—',
            ),
            _diagLine(
              'Último download',
              d.lastDownloadPath != null
                  ? '${d.lastDownloadAt?.toIso8601String() ?? ''}\n${d.lastDownloadPath}'
                  : '—',
            ),
            if (d.tenantMismatch || !d.storageAligned)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  d.tenantMismatch
                      ? 'WEB_FIRESTORE_MISMATCH detectado'
                      : 'STORAGE_TENANT_MISMATCH detectado',
                  style: TextStyle(
                    color: ThemeCleanPremium.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (d.lastError != null)
              Text(
                'Último erro: ${d.lastError}',
                style: TextStyle(fontSize: 12, color: ThemeCleanPremium.error),
              ),
            if (counts != null) ...[
              const SizedBox(height: 12),
              Text(
                'Documentos (amostra até ${YahwehPerformanceV4.dashboardStatsSampleLimit}/coleção)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              _diagLine('Membros', '${counts.membros}'),
              _diagLine('Eventos', '${counts.eventos}'),
              _diagLine('Avisos', '${counts.avisos}'),
              _diagLine('Departamentos', '${counts.departamentos}'),
              _diagLine('Cargos', '${counts.cargos}'),
              _diagLine('Patrimônios', '${counts.patrimonio}'),
              _diagLine('Chats', '${counts.chats}'),
              _diagLine('Escalas', '${counts.escalas}'),
              _diagLine('Financeiro', '${counts.financeiro}'),
              _diagLine('Fornecedores', '${counts.fornecedores}'),
              _diagLine('Pedidos Oração', '${counts.pedidosOracao}'),
              _diagLine('Cartas/Transfer.', '${counts.cartasHistorico}'),
              _diagLine('Certificados', '${counts.certificados}'),
            ],
            if (audit?.moduleStatuses.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                'Módulos padronizados',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              for (final m in audit!.moduleStatuses)
                _diagLine(
                  m.module,
                  m.standardized
                      ? 'OK — ${m.firestoreCollection ?? ''}'
                      : (m.lastError ?? 'pendente'),
                ),
            ],
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.speed_rounded, color: ThemeCleanPremium.primary),
            title: const Text(
              'Diagnóstico permanente',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Firestore, Storage, tempos de Dashboard/Login e contadores',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChurchPanelDiagnosticPage(
                    tenantId: _effectiveTenantId,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _churchSyncDiagnosticLoading
                      ? null
                      : () => unawaited(_runChurchSyncDiagnostic()),
                  icon: const Icon(Icons.medical_information_outlined, size: 18),
                  label: const Text('Executar diagnóstico'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChurchSyncTestPage(
                          tenantId: _effectiveTenantId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('Tela de teste'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _diagLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificacoesCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Push no celular (Android e iPhone)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Escolha o que deseja receber. Pastoral e devocional usam o tópico geral da igreja.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 14),
          _PushPrefTile(
            icon: Icons.campaign_rounded,
            color: const Color(0xFF0EA5E9),
            title: 'Avisos do mural',
            subtitle: 'Novidades publicadas no mural da igreja',
            value: _notifAvisos,
            onChanged: (v) {
              setState(() => _notifAvisos = v);
              unawaited(_savePushPref(_keyNotifAvisos, 'pushAvisos', v));
            },
          ),
          _PushPrefTile(
            icon: Icons.event_rounded,
            color: const Color(0xFFF97316),
            title: 'Eventos',
            subtitle: 'Agenda, cultos e atividades',
            value: _notifEventos,
            onChanged: (v) {
              setState(() => _notifEventos = v);
              unawaited(_savePushPref(_keyNotifEventos, 'pushEventos', v));
            },
          ),
          _PushPrefTile(
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFF14B8A6),
            title: 'Escalas',
            subtitle: 'Publicação e lembretes de escala',
            value: _notifEscalas,
            onChanged: (v) {
              setState(() => _notifEscalas = v);
              unawaited(_savePushPref(_keyNotifEscalas, 'pushEscalas', v));
            },
          ),
          _PushPrefTile(
            icon: Icons.cake_rounded,
            color: const Color(0xFFE11D48),
            title: 'Aniversariantes',
            subtitle: 'Lembrete diário às 8h (horário de Brasília)',
            value: _notifAniversariantes,
            onChanged: (v) {
              setState(() => _notifAniversariantes = v);
              unawaited(_savePushPref(
                _keyNotifAniversariantes,
                'pushAniversariantes',
                v,
              ));
            },
          ),
          _PushPrefTile(
            icon: Icons.chat_bubble_rounded,
            color: const Color(0xFF8B5CF6),
            title: 'Chat da igreja',
            subtitle: 'Mensagens e menções',
            value: _notifChat,
            onChanged: (v) {
              setState(() => _notifChat = v);
              unawaited(_savePushPref(
                ChurchChatNotificationPrefs.sharedPrefsKey,
                'pushChat',
                v,
              ));
            },
          ),
          if (!_restrictedMemberSettings) ...[
            const Divider(height: 24),
            Text(
              'Cadastros (gestores)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded,
                      color: Color(0xFF2563EB)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pastores, gestores e secretários recebem push automático '
                      'quando há novo membro ou cadastro pelo site.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            _SwitchRow('E-mail', _notifEmail, (v) {
              setState(() => _notifEmail = v);
              _saveNotif(_keyNotifEmail, v);
            }),
            _SwitchRow('Push no celular', _notifCelular, (v) {
              setState(() => _notifCelular = v);
              _saveNotif(_keyNotifCelular, v);
            }),
            _SwitchRow('Navegador / Web', _notifWeb, (v) {
              setState(() => _notifWeb = v);
              _saveNotif(_keyNotifWeb, v);
            }),
            _ChatAlertModeRow(
              value: _notifChatAlertMode,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _notifChatAlertMode = v);
                unawaited(
                  ChurchChatNotificationPrefs.setChatAlertMode(mode: v),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildBackupSection(BuildContext context) {
    if (_restrictedMemberSettings) return const [];
    return [
      _SectionTitle(icon: Icons.backup_rounded, title: 'Backup'),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Exportar e importar dados do painel.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _exportarBackup(context),
                    icon: const Icon(Icons.upload_file_rounded, size: 20),
                    label: const Text('Exportar'),
                    style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.primary, padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _importarBackup(context),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text('Importar'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildDicasSection() {
    if (_restrictedMemberSettings) return const [];
    return [
      _SectionTitle(icon: Icons.lightbulb_outline_rounded, title: 'Dicas, sugestões e críticas'),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Envie sua opinião ao criador do sistema. Sua mensagem será lida e agradecemos pelo feedback!', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _sugestaoCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Digite dicas, sugestões ou críticas...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              enabled: !_sugestaoEnviando && !_sugestaoEnviada,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_sugestaoEnviando || _sugestaoEnviada) ? null : _enviarSugestao,
                icon: _sugestaoEnviando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(_sugestaoEnviada ? 'Enviado!' : (_sugestaoEnviando ? 'Enviando...' : 'Enviar')),
                style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            if (_sugestaoEnviada)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ThemeCleanPremium.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.thumb_up_rounded, color: ThemeCleanPremium.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Obrigado! Sua mensagem foi recebida. O criador do sistema agradece sua contribuição e retornará quando possível.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeCleanPremium.success),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Future<void> _exportarBackup(BuildContext context) async {
    try {
      final resolvedTenantId = await _resolveEffectiveTenantId();
      final op = await ChurchOperationalPaths.resolveCached(resolvedTenantId.trim());
      final ref = ChurchOperationalPaths.churchDoc(op);
      final sample = YahwehPerformanceV4.dashboardStatsSampleLimit;
      final membersSnap = await ref.collection('membros').limit(sample).get();
      final noticiasSnap = await ref.collection('eventos').limit(sample).get();
      final data = {
        'tenantId': resolvedTenantId,
        'exportedAt': DateTime.now().toIso8601String(),
        'members': membersSnap.docs
            .map((d) => {'id': d.id, 'data': firestoreToJsonSafe(d.data())})
            .toList(),
        'noticias': noticiasSnap.docs
            .map((d) => {'id': d.id, 'data': firestoreToJsonSafe(d.data())})
            .toList(),
      };
      final json = const JsonEncoder.withIndent('  ').convert(data);
      await Share.share(
        json,
        subject: 'Backup Gestão YAHWEH - ${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      );
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exportação gerada. Use Compartilhar para salvar.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
    }
  }

  /// Usa o serviço centralizado para garantir mesmo path que AuthGate, dashboard e MembersPage (import/export no mesmo tenant).
  Future<String> _resolveEffectiveTenantId() async {
    final op = await ChurchOperationalPaths.resolveCached(
      widget.tenantId,
      userUid: FirebaseAuth.instance.currentUser?.uid,
    );
    if (mounted && op.isNotEmpty) {
      setState(() => _operationalTenantId = op);
    }
    return op;
  }

  Future<void> _importarBackup(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Importar backup'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cole aqui o conteúdo JSON exportado anteriormente. Atenção: isso pode sobrescrever dados.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 8,
                decoration: const InputDecoration(hintText: '{"tenantId": "...", "members": [...]}', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final resolvedTenantId = await _resolveEffectiveTenantId();
      final data = jsonDecode(ctrl.text.trim()) as Map<String, dynamic>;
      final members = (data['members'] as List?) ?? [];
      final batch = FirebaseFirestore.instance.batch();
      final op = await ChurchOperationalPaths.resolveCached(resolvedTenantId.trim());
      final col = ChurchOperationalPaths.churchDoc(op).collection('membros');
      for (final m in members) {
        final map = m as Map<String, dynamic>;
        final id = (map['id'] ?? '').toString();
        final docData = map['data'] as Map<String, dynamic>?;
        if (id.isEmpty || docData == null) continue;
        batch.set(col.doc(id), docData, SetOptions(merge: true));
      }
      await batch.commit();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Importados ${members.length} registros.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao importar: $e')));
    }
  }

  Future<void> _enviarSugestao() async {
    final texto = _sugestaoCtrl.text.trim();
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Digite sua mensagem.')));
      return;
    }
    setState(() => _sugestaoEnviando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('suggestions').add({
        'tenantId': widget.tenantId,
        'userId': user?.uid ?? '',
        'userEmail': user?.email ?? '',
        'userName': user?.displayName ?? '',
        'text': texto,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pendente',
        'tipo': 'dica_sugestao_critica',
      });
      _sugestaoCtrl.clear();
      setState(() { _sugestaoEnviando = false; _sugestaoEnviada = true; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Obrigado! Sua mensagem foi enviada ao criador do sistema.'), backgroundColor: ThemeCleanPremium.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
        setState(() => _sugestaoEnviando = false);
      }
    }
  }
}

class _ConfigHelpBullet extends StatelessWidget {
  final String text;

  const _ConfigHelpBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.arrow_right_rounded,
              size: 18,
              color: ThemeCleanPremium.primary,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.38,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: ThemeCleanPremium.primary),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: child,
    );
  }
}

String _fmtShortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _MiniStatusChip extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;

  const _MiniStatusChip({
    required this.label,
    required this.value,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ok
            ? ThemeCleanPremium.success.withOpacity(0.08)
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok
              ? ThemeCleanPremium.success.withOpacity(0.35)
              : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ok ? ThemeCleanPremium.success : Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ],
      ),
    );
  }
}

class _ChatAlertModeRow extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _ChatAlertModeRow({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = ChurchChatNotificationPrefs.normalizeAlertMode(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Alerta das conversas',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: normalized,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: ChurchChatNotificationPrefs.alertModeSound,
                  child: Text('Som Whats + vibrar'),
                ),
                DropdownMenuItem(
                  value: ChurchChatNotificationPrefs.alertModeVibrate,
                  child: Text('Só vibrar'),
                ),
                DropdownMenuItem(
                  value: ChurchChatNotificationPrefs.alertModeSilent,
                  child: Text('Silencioso'),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PushPrefTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PushPrefTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          secondary: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
