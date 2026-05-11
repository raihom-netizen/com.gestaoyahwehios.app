import 'dart:async' show unawaited;
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
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart'
    show appGoogleSignOutForAccountPicker;
import 'package:gestao_yahweh/utils/firestore_json_safe.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/core/media_cache_preferences.dart';
import 'package:gestao_yahweh/ui/widgets/mercado_pago_church_settings_section.dart';
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

  @override
  void initState() {
    super.initState();
    _notifMinutosCtrl = TextEditingController(text: '60');
    _loadPrefs();
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
    var capable = false;
    var bioOn = false;
    if (!kIsWeb) {
      capable = await _biometricService.isDeviceBiometricCapable();
      bioOn = await _biometricService.isEnabled();
    }
    var av = prefs.getBool(_keyNotifAvisos) ?? true;
    var ev = prefs.getBool(_keyNotifEventos) ?? true;
    var es = prefs.getBool(_keyNotifEscalas) ?? true;
    var ch = prefs.getBool(ChurchChatNotificationPrefs.sharedPrefsKey) ?? true;
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
            .get();
        final d = doc.data();
        if (d != null) {
          if (d['pushAvisos'] is bool) av = d['pushAvisos'] as bool;
          if (d['pushEventos'] is bool) ev = d['pushEventos'] as bool;
          if (d['pushEscalas'] is bool) es = d['pushEscalas'] as bool;
          if (d['pushChat'] is bool) ch = d['pushChat'] as bool;
          final rawAlertMode = d['pushChatAlertMode'];
          if (rawAlertMode is String && rawAlertMode.trim().isNotEmpty) {
            chatAlertMode = ChurchChatNotificationPrefs.normalizeAlertMode(rawAlertMode);
          }
        }
      } catch (_) {}
    }
    await prefs.setBool(_keyNotifAvisos, av);
    await prefs.setBool(_keyNotifEventos, ev);
    await prefs.setBool(_keyNotifEscalas, es);
    await prefs.setBool(ChurchChatNotificationPrefs.sharedPrefsKey, ch);
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
      _notifChatAlertMode = chatAlertMode;
      _notifAniversariantes = prefs.getBool(_keyNotifAniversariantes) ?? true;
      _notifEmail = prefs.getBool(_keyNotifEmail) ?? true;
      _notifCelular = prefs.getBool(_keyNotifCelular) ?? true;
      _notifWeb = prefs.getBool(_keyNotifWeb) ?? true;
      _notif1Dia = prefs.getBool(_keyNotif1Dia) ?? true;
      _notif60Min = prefs.getBool(_keyNotif60Min) ?? true;
      _bioCapable = capable;
      _bioEnabled = bioOn;
      _cacheFotosPerfilNoAparelho =
          prefs.getBool(kPrefMemberPhotoDiskCacheV1) ?? true;
      _loading = false;
    });
  }

  Future<void> _loadAccountAndLicenseSnapshot() async {
    final authUser = FirebaseAuth.instance.currentUser;
    final email = (authUser?.email ?? '').trim();
    var userAtivo = authUser != null;
    SubscriptionGuardState? guard;
    try {
      final resolved =
          await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      final chSnap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(resolved)
          .get();
      guard = SubscriptionGuard.evaluate(
        church: chSnap.data(),
        subscription: widget.subscription,
      );
      if (authUser != null) {
        try {
          final uDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(authUser.uid)
              .get();
          userAtivo = uDoc.data()?['ativo'] == true;
        } catch (_) {}
      }
    } catch (_) {}
    _subscriptionGuard = guard;
    _userAtivoNoPainel = userAtivo;
    _accountEmailDisplay = email.isNotEmpty ? email : '—';
  }

  Future<void> _trocarConta(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Trocar de conta'),
        content: const Text(
          'Você sairá desta sessão e poderá entrar com outra conta Google, Apple '
          '(iPhone) ou outro e-mail e senha.\n\nContinuar?',
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
    if (ok != true || !context.mounted) return;
    try {
      await LoginPreferences.clearOAuthHints();
      if (!kIsWeb) {
        await appGoogleSignOutForAccountPicker();
      }
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!context.mounted) return;
    if (kIsWeb) {
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove('last_route');
      } catch (_) {}
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/login', (_) => false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digital/Face ID ativado. Na entrada do app, marque também «Lembrar usuário e senha» para usar o acesso rápido.'),
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
      AppPermissions.canViewChurchMercadoPagoSettings(widget.role, permissions: widget.permissions);

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
                  if (_showMercadoPagoChurchSettings) ...[
                    MercadoPagoChurchSettingsSection(tenantId: widget.tenantId),
                  ],
                  _SectionTitle(icon: Icons.fingerprint_rounded, title: 'Acesso ao app'),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (kIsWeb)
                          Text(
                            'Desbloqueio por digital ou Face ID está disponível no aplicativo instalado (Android e iOS), na tela de login e aqui em Configurações.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                          )
                        else if (!_bioCapable)
                          Text(
                            'Este aparelho não tem biometria configurada ou o sensor não está disponível para o app.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                          )
                        else ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.fingerprint_rounded, color: ThemeCleanPremium.primary),
                            ),
                            title: const Text('Desbloquear com digital / Face ID', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text(
                              'Ao abrir o app, pede digital ou rosto antes do painel — igual à opção da tela Entrar. Para login rápido com um toque, use também «Lembrar usuário e senha» no login.',
                              style: TextStyle(fontSize: 12.5),
                            ),
                            value: _bioEnabled,
                            onChanged: _bioToggling ? null : _onBiometricSwitch,
                          ),
                          if (_bioToggling)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(minHeight: 3),
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 24),
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
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Onde receber lembretes e avisos',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ative por canal: no celular (app Android/iOS), no navegador (painel web / PWA) e por e-mail. O mesmo login em web e mobile usa estas preferências neste aparelho.',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 14),
                        _SwitchRow('E-mail', _notifEmail, (v) => setState(() { _notifEmail = v; _saveNotif(_keyNotifEmail, v); })),
                        _SwitchRow('Celular / app (push no aparelho)', _notifCelular, (v) => setState(() { _notifCelular = v; _saveNotif(_keyNotifCelular, v); })),
                        _SwitchRow('Navegador / Web (painel e PWA)', _notifWeb, (v) => setState(() { _notifWeb = v; _saveNotif(_keyNotifWeb, v); })),
                        const Divider(height: 24),
                        Text('O que notificar:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                        const SizedBox(height: 10),
                        _SwitchRow('Avisos', _notifAvisos, (v) {
                          setState(() => _notifAvisos = v);
                          unawaited(_savePushPref(_keyNotifAvisos, 'pushAvisos', v));
                        }),
                        _SwitchRow('Escalas', _notifEscalas, (v) {
                          setState(() => _notifEscalas = v);
                          unawaited(_savePushPref(_keyNotifEscalas, 'pushEscalas', v));
                        }),
                        _SwitchRow('Eventos', _notifEventos, (v) {
                          setState(() => _notifEventos = v);
                          unawaited(_savePushPref(_keyNotifEventos, 'pushEventos', v));
                        }),
                        _SwitchRow('Chat da igreja (mensagens)', _notifChat, (v) {
                          setState(() => _notifChat = v);
                          unawaited(_savePushPref(
                            ChurchChatNotificationPrefs.sharedPrefsKey,
                            'pushChat',
                            v,
                          ));
                        }),
                        const SizedBox(height: 8),
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
                        _SwitchRow('Aniversariantes do dia', _notifAniversariantes, (v) => setState(() { _notifAniversariantes = v; _saveNotif(_keyNotifAniversariantes, v); })),
                        const Divider(height: 24),
                        Text('Antecedência:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                        const SizedBox(height: 10),
                        _SwitchRow('1 dia antes', _notif1Dia, (v) => setState(() { _notif1Dia = v; _saveNotif(_keyNotif1Dia, v); })),
                        _SwitchRow('60 minutos antes', _notif60Min, (v) => setState(() { _notif60Min = v; _saveNotif(_keyNotif60Min, v); })),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Personalizado (minutos): ', style: TextStyle(fontSize: 13)),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                controller: _notifMinutosCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                onChanged: (v) => _saveNotif(_keyNotifMinutos, v.isEmpty ? '60' : v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          kIsWeb
                              ? 'Neste navegador, use os interruptores acima. No celular (app), as mesmas preferências de tipo de aviso podem ser ajustadas no app — cada ambiente guarda o que for suportado (push no app, e-mail, etc.).'
                              : 'No app, avisos/eventos/escalas novos podem gerar push (padrão ligado). No painel web, ative o canal «Navegador / Web» se usar o painel no computador. E-mail segue o interruptor de e-mail.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...(_restrictedMemberSettings
                      ? <Widget>[..._buildDicasSection(), ..._buildBackupSection(context)]
                      : <Widget>[..._buildBackupSection(context), ..._buildDicasSection()]),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildBackupSection(BuildContext context) {
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
      final ref = FirebaseFirestore.instance.collection('igrejas').doc(resolvedTenantId);
      final membersSnap = await ref.collection('membros').limit(2000).get();
      final noticiasSnap = await ref.collection('noticias').limit(500).get();
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
  Future<String> _resolveEffectiveTenantId() async =>
      TenantResolverService.resolveEffectiveTenantId(widget.tenantId);

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
      final col = FirebaseFirestore.instance.collection('igrejas').doc(resolvedTenantId).collection('membros');
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
