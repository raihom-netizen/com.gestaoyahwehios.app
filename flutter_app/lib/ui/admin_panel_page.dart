import 'dart:async';

import 'admin_multi_admin_page.dart';
import 'admin_suporte_page.dart';
import 'admin_customizacao_page.dart';
import 'admin_auditoria_page.dart';
import 'admin_planos_cobranca_page.dart';
import 'admin_alertas_page.dart';
import 'admin_usuarios_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/billing_license_service.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/app_theme.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/ui/admin_menu_lateral.dart';
import 'pages/mercado_pago_admin_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_niveis_acesso_page.dart';
import 'editar_precos_planos_page.dart';
import 'admin_recebimentos_page.dart';
import 'admin_gestores_page.dart';
import 'admin_acessos_dominio_page.dart';
import 'admin_forcar_atualizacao_page.dart';
import 'admin_migrar_membros_page.dart';
import 'admin_sugestoes_page.dart';
import 'admin_divulgacao_media_page.dart';
import 'master_saas_command_center_page.dart';
import 'admin_aviso_global_page.dart';
import 'pages/storage_usage_page.dart';
import 'widgets/version_footer.dart';
import 'widgets/global_announcement_overlay.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';

part 'admin_igrejas_tab.dart';

/// Título do AppBar no painel master em telas estreitas (celular / web estreito).
String _masterMenuTitle(AdminMenuItem item) {
  switch (item) {
    case AdminMenuItem.igrejasDashboard:
      return 'Painel Igrejas';
    case AdminMenuItem.igrejasLista:
      return 'Lista Igrejas';
    case AdminMenuItem.igrejasPlanos:
      return 'Planos e cobranças';
    case AdminMenuItem.igrejasUsuarios:
      return 'Usuários e igrejas';
    case AdminMenuItem.igrejasMercadoPago:
      return 'Mercado Pago';
    case AdminMenuItem.igrejasRecebimentos:
      return 'Recebimentos';
    case AdminMenuItem.igrejasGestores:
      return 'Ativar gestores';
    case AdminMenuItem.igrejasTorreComando:
      return 'Torre SaaS';
    case AdminMenuItem.sistemaDashboard:
      return 'Dashboard geral';
    case AdminMenuItem.sistemaAlertas:
      return 'Alertas';
    case AdminMenuItem.sistemaAuditoria:
      return 'Auditoria';
    case AdminMenuItem.sistemaCustomizacao:
      return 'Customização';
    case AdminMenuItem.sistemaSuporte:
      return 'Suporte';
    case AdminMenuItem.sistemaMultiAdmin:
      return 'Multi-Admin';
    case AdminMenuItem.sistemaPrecos:
      return 'Preços dos planos';
    case AdminMenuItem.sistemaNiveisAcesso:
      return 'Níveis de acesso';
    case AdminMenuItem.sistemaSugestoes:
      return 'Sugestões';
    case AdminMenuItem.sistemaDivulgacao:
      return 'Mídias divulgação';
    case AdminMenuItem.sistemaAcessos:
      return 'Acessos ao domínio';
    case AdminMenuItem.sistemaArmazenamento:
      return 'Armazenamento';
    case AdminMenuItem.sistemaAvisoGlobal:
      return 'Aviso global';
    case AdminMenuItem.sistemaVersaoMinima:
      return 'Forçar atualização';
    case AdminMenuItem.sistemaMigrarMembros:
      return 'Migrar membros';
    case AdminMenuItem.sistemaHome:
      return 'Início';
  }
}

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _q = '';
  late AdminMenuItem _selectedItem;
  bool _menuCollapsed = false;
  late AdminContext _adminContext;
  late Future<bool> _isAdminFuture;
  Timer? _idleTimer;
  DateTime _lastActivityAt = DateTime.now();
  static const Duration _idleTimeout = Duration(minutes: 20);
  bool _reportedSuspiciousAccess = false;
  String _masterRole = '';
  List<String> _masterPermissions = const [];

  @override
  void initState() {
    super.initState();
    _selectedItem = AdminMenuItem.sistemaDashboard;
    _adminContext = AdminContext.igrejas;
    // Timeout 10s: se a verificação do token travar, negar acesso master por segurança.
    _isAdminFuture = Future.any<bool>([
      _isAdmin(),
      Future.delayed(const Duration(seconds: 10), () => false),
    ]);
    unawaited(_loadMasterRbac());
    _touchActivity();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  /// Verifica se o usuário tem claim ADMIN. Nunca lança — em timeout/erro retorna false por segurança.
  Future<bool> _isAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return false;
      final token = await u.getIdTokenResult(true).timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException('Verificação de admin'),
          );
      final role = (token.claims?['role'] ?? token.claims?['nivel'] ?? '')
          .toString()
          .toUpperCase();
      return role == 'ADMIN' || role == 'ADM' || role == 'MASTER';
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadMasterRbac() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      final db = FirebaseFirestore.instance;
      final usersDoc = await db.collection('users').doc(u.uid).get();
      final usuariosDoc = await db.collection('usuarios').doc(u.uid).get();
      final usersData = usersDoc.data() ?? <String, dynamic>{};
      final usuariosData = usuariosDoc.data() ?? <String, dynamic>{};
      final role = (usersData['role'] ??
              usersData['nivel'] ??
              usuariosData['papel'] ??
              usuariosData['role'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      final permissions = AppPermissions.normalizePermissions(
        usersData['masterPermissions'] ??
            usersData['permissions'] ??
            usuariosData['masterPermissions'] ??
            usuariosData['permissions'] ??
            usuariosData['permissoes'],
      );
      if (!mounted) return;
      setState(() {
        _masterRole = role;
        _masterPermissions = permissions;
      });
    } catch (_) {}
  }

  bool _canAccessMasterItem(AdminMenuItem item) {
    // Admin/master mantém acesso total por padrão.
    if (_masterRole == 'adm' ||
        _masterRole == 'admin' ||
        _masterRole == 'master') return true;
    // Compatibilidade retroativa: sem permissões explícitas, mantém visível para não quebrar operações atuais.
    if (_masterPermissions.isEmpty) return true;
    if (item == AdminMenuItem.sistemaHome) return true;
    const map = <AdminMenuItem, String>{
      AdminMenuItem.igrejasDashboard: 'igrejas',
      AdminMenuItem.igrejasLista: 'igrejas',
      AdminMenuItem.igrejasPlanos: 'planos',
      AdminMenuItem.igrejasUsuarios: 'usuarios',
      AdminMenuItem.igrejasMercadoPago: 'financeiro',
      AdminMenuItem.igrejasRecebimentos: 'financeiro',
      AdminMenuItem.igrejasGestores: 'gestores',
      AdminMenuItem.igrejasTorreComando: 'igrejas',
      AdminMenuItem.sistemaDashboard: 'dashboard',
      AdminMenuItem.sistemaAlertas: 'alertas',
      AdminMenuItem.sistemaAuditoria: 'auditoria',
      AdminMenuItem.sistemaCustomizacao: 'customizacao',
      AdminMenuItem.sistemaSuporte: 'suporte',
      AdminMenuItem.sistemaMultiAdmin: 'multi_admin',
      AdminMenuItem.sistemaPrecos: 'precos',
      AdminMenuItem.sistemaNiveisAcesso: 'niveis_acesso',
      AdminMenuItem.sistemaSugestoes: 'sugestoes',
      AdminMenuItem.sistemaDivulgacao: 'divulgacao',
      AdminMenuItem.sistemaAcessos: 'acessos',
      AdminMenuItem.sistemaArmazenamento: 'armazenamento',
      AdminMenuItem.sistemaAvisoGlobal: 'aviso_global',
      AdminMenuItem.sistemaVersaoMinima: 'versao',
      AdminMenuItem.sistemaMigrarMembros: 'migracao',
    };
    final key = map[item];
    if (key == null) return true;
    return _masterPermissions.contains(key);
  }

  void _touchActivity() {
    _lastActivityAt = DateTime.now();
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _onIdleTimeout);
  }

  Future<void> _onIdleTimeout() async {
    if (!mounted) return;
    final since = DateTime.now().difference(_lastActivityAt);
    if (since < _idleTimeout) return;
    await _writeAuditLog(
      action: 'master_session_timeout',
      resource: 'admin_panel',
      details: 'Logout por inatividade',
    );
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
          'Sessão encerrada por segurança (inatividade).'),
    );
  }

  Future<void> _writeAuditLog({
    required String action,
    required String resource,
    String? details,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdTokenResult();
      final igrejaId =
          (token?.claims?['igrejaId'] ?? token?.claims?['tenantId'] ?? '')
              .toString();
      await FirebaseFirestore.instance.collection('auditoria').add({
        'acao': action,
        'resource': resource,
        'details': (details ?? '').trim(),
        'usuario': user?.email ?? user?.uid ?? 'sistema',
        'uid': user?.uid,
        'igrejaId': igrejaId,
        'data': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Auditoria nunca deve quebrar o fluxo principal.
    }
  }

  Future<void> _reportSecurityEvent({
    required String event,
    required String resource,
    String? details,
    String severity = "medium",
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable("reportSecurityEvent");
      await callable.call({
        "event": event,
        "resource": resource,
        "details": (details ?? "").trim(),
        "severity": severity,
      });
    } catch (_) {
      // Evento de segurança não deve quebrar navegação.
    }
  }

  Future<void> _bootstrapAdmin(BuildContext context) async {
    final ctrl = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tornar este usuário ADMIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se você é o primeiro administrador (raihom@gmail.com), pode deixar em branco e confirmar.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            const Text(
              'Para outros usuários: a chave é definida por você no Firebase. Google Cloud Console → Cloud Functions → bootstrapAdmin → Editar → Variáveis de ambiente → ADMIN_SETUP_KEY = sua_chave. Use a mesma chave aqui.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Chave de setup (ADMIN_SETUP_KEY)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (key == null) return;

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('bootstrapAdmin');
      final res = await callable.call({'setupKey': key.trim()});
      final ok =
          (res.data is Map && (res.data['ok'] == true)) || res.data == true;
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(ok
            ? 'Pronto! Você agora é ADMIN. Recarregando...'
            : 'Resposta recebida.'),
      );

      if (!ok) return;
      await _writeAuditLog(
        action: 'bootstrap_admin_success',
        resource: 'admin_panel',
        details: 'Elevação de privilégio concluída',
      );
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (!context.mounted) return;
      // Na web, recarrega a página para garantir que o novo token (claim ADMIN) seja usado
      VersionService.reloadWeb();
      setState(() {});
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      final msg = e.message ?? e.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Falha ao virar ADMIN: $msg'),
            backgroundColor: Colors.red.shade700),
      );
      await _writeAuditLog(
        action: 'bootstrap_admin_error',
        resource: 'admin_panel',
        details: 'FirebaseFunctionsException: $msg',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Falha ao virar ADMIN: $e'),
            backgroundColor: Colors.red.shade700),
      );
      await _writeAuditLog(
        action: 'bootstrap_admin_error',
        resource: 'admin_panel',
        details: 'Erro: $e',
      );
    }
  }

  Widget _buildAdminContent(BuildContext context, bool isAdmin) {
    if (!isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 44, color: Colors.orange),
                  const SizedBox(height: 10),
                  const Text(
                    'Acesso restrito ao Painel Master',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seu usuário atual não possui perfil ADMIN. As igrejas não sumiram; faça login com o usuário administrador para visualizar os dados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/', (_) => false);
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Entrar com usuário admin'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget content;
    switch (_selectedItem) {
      case AdminMenuItem.igrejasDashboard:
        content = _IgrejasTab(
            query: _q,
            onQueryChanged: (v) => setState(() => _q = v),
            canEdit: isAdmin);
        break;
      case AdminMenuItem.igrejasLista:
        content = _IgrejasTab(
            query: _q,
            onQueryChanged: (v) => setState(() => _q = v),
            canEdit: isAdmin);
        break;
      case AdminMenuItem.igrejasPlanos:
        content = const AdminPlanosCobrancaPage();
        break;
      case AdminMenuItem.igrejasUsuarios:
        content = const AdminUsuariosPage();
        break;
      case AdminMenuItem.igrejasMercadoPago:
        content = const MercadoPagoAdminPage(embeddedInMaster: true);
        break;
      case AdminMenuItem.igrejasRecebimentos:
        content = const AdminRecebimentosPage();
        break;
      case AdminMenuItem.igrejasGestores:
        content = const AdminGestoresPage();
        break;
      case AdminMenuItem.igrejasTorreComando:
        content = const MasterSaasCommandCenterPage();
        break;
      case AdminMenuItem.sistemaDashboard:
        content = AdminDashboardPage(
          embedInPanel: true,
          onNavigateTo: (item) => _selectMenuItem(context, item),
        );
        break;
      case AdminMenuItem.sistemaAlertas:
        content = const AdminAlertasPage();
        break;
      case AdminMenuItem.sistemaAuditoria:
        content = const AdminAuditoriaPage();
        break;
      case AdminMenuItem.sistemaCustomizacao:
        content = const AdminCustomizacaoPage();
        break;
      case AdminMenuItem.sistemaSuporte:
        content = const AdminSuportePage();
        break;
      case AdminMenuItem.sistemaMultiAdmin:
        content = const AdminMultiAdminPage();
        break;
      case AdminMenuItem.sistemaPrecos:
        content = const EditarPrecosPlanosPage();
        break;
      case AdminMenuItem.sistemaNiveisAcesso:
        content = const AdminNiveisAcessoPage();
        break;
      case AdminMenuItem.sistemaSugestoes:
        content = const AdminSugestoesPage();
        break;
      case AdminMenuItem.sistemaDivulgacao:
        content = const AdminDivulgacaoMediaPage();
        break;
      case AdminMenuItem.sistemaAcessos:
        content = const AdminAcessosDominioPage();
        break;
      case AdminMenuItem.sistemaArmazenamento:
        content = const StorageUsageMasterPage();
        break;
      case AdminMenuItem.sistemaAvisoGlobal:
        content = const AdminAvisoGlobalPage();
        break;
      case AdminMenuItem.sistemaVersaoMinima:
        content = const AdminForcarAtualizacaoPage();
        break;
      case AdminMenuItem.sistemaMigrarMembros:
        content = const AdminMigrarMembrosPage();
        break;
      case AdminMenuItem.sistemaHome:
        content = const Center(child: Text('Voltar ao Início'));
        break;
    }
    return content;
  }

  void _selectMenuItem(BuildContext context, AdminMenuItem item) {
    _touchActivity();
    if (!_canAccessMasterItem(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acesso negado para este módulo do painel master.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (item == AdminMenuItem.sistemaHome) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      return;
    }
    unawaited(_writeAuditLog(
      action: 'master_navigate',
      resource: 'menu/${item.name}',
      details: 'Navegação no painel master',
    ));
    setState(() => _selectedItem = item);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false)
      Navigator.of(context).pop();
  }

  Widget _buildDrawer(BuildContext context, bool isAdmin) {
    final drawerW = (MediaQuery.sizeOf(context).width * 0.88)
        .clamp(280.0, 360.0)
        .toDouble();
    return Drawer(
      width: drawerW,
      child: Container(
        color: ThemeCleanPremium.navSidebar,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Row(
                  children: [
                    SizedBox(
                      height: 36,
                      child: Image.asset(
                        'assets/LOGO_GESTAO_YAHWEH.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Colors.white,
                            size: 32),
                      ),
                    ),
                    const SizedBox(width: ThemeCleanPremium.spaceSm),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Gestão YAHWEH',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18)),
                          Text('Painel Admin',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.church_rounded, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text('Igrejas',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  children: [
                    ..._drawerTilesForContext(context),
                    const Divider(height: 24, color: Colors.white24),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaDashboard))
                      _drawerTile(context, Icons.analytics_rounded,
                          'Dashboard Geral', AdminMenuItem.sistemaDashboard),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaAlertas))
                      _drawerTile(context, Icons.notifications_rounded,
                          'Alertas', AdminMenuItem.sistemaAlertas),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaAuditoria))
                      _drawerTile(context, Icons.history_rounded, 'Auditoria',
                          AdminMenuItem.sistemaAuditoria),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaCustomizacao))
                      _drawerTile(context, Icons.settings_rounded,
                          'Customização', AdminMenuItem.sistemaCustomizacao),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaSuporte))
                      _drawerTile(context, Icons.support_agent_rounded,
                          'Suporte', AdminMenuItem.sistemaSuporte),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaMultiAdmin))
                      _drawerTile(context, Icons.admin_panel_settings_rounded,
                          'Multi-Admin', AdminMenuItem.sistemaMultiAdmin),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaPrecos))
                      _drawerTile(context, Icons.edit_note_rounded,
                          'Editar Preços', AdminMenuItem.sistemaPrecos),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaNiveisAcesso))
                      _drawerTile(
                          context,
                          Icons.security_rounded,
                          'Níveis de Acesso',
                          AdminMenuItem.sistemaNiveisAcesso),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaSugestoes))
                      _drawerTile(
                          context,
                          Icons.feedback_rounded,
                          'Sugestões / Críticas',
                          AdminMenuItem.sistemaSugestoes),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaDivulgacao))
                      _drawerTile(
                          context,
                          Icons.perm_media_rounded,
                          'Mídias Divulgação',
                          AdminMenuItem.sistemaDivulgacao),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaAcessos))
                      _drawerTile(context, Icons.show_chart_rounded,
                          'Acessos ao domínio', AdminMenuItem.sistemaAcessos),
                    if (_canAccessMasterItem(
                        AdminMenuItem.sistemaArmazenamento))
                      _drawerTile(context, Icons.storage_rounded,
                          'Armazenamento', AdminMenuItem.sistemaArmazenamento),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaAvisoGlobal))
                      _drawerTile(
                          context,
                          Icons.campaign_rounded,
                          'Aviso global / Manutenção',
                          AdminMenuItem.sistemaAvisoGlobal),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaVersaoMinima))
                      _drawerTile(
                          context,
                          Icons.system_update_rounded,
                          'Forçar atualização',
                          AdminMenuItem.sistemaVersaoMinima),
                    if (_canAccessMasterItem(
                        AdminMenuItem.sistemaMigrarMembros))
                      _drawerTile(context, Icons.people_alt_rounded,
                          'Migrar membros', AdminMenuItem.sistemaMigrarMembros),
                    if (_canAccessMasterItem(AdminMenuItem.sistemaHome))
                      _drawerTile(context, Icons.home_rounded,
                          'Voltar ao Início', AdminMenuItem.sistemaHome),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _drawerTilesForContext(BuildContext context) {
    return [
      if (_canAccessMasterItem(AdminMenuItem.igrejasDashboard))
        _drawerTile(context, Icons.dashboard_rounded, 'Painel Igrejas',
            AdminMenuItem.igrejasDashboard),
      if (_canAccessMasterItem(AdminMenuItem.igrejasLista))
        _drawerTile(context, Icons.church_rounded, 'Lista Igrejas',
            AdminMenuItem.igrejasLista),
      if (_canAccessMasterItem(AdminMenuItem.igrejasPlanos))
        _drawerTile(context, Icons.credit_card_rounded, 'Planos & Cobranças',
            AdminMenuItem.igrejasPlanos),
      if (_canAccessMasterItem(AdminMenuItem.igrejasUsuarios))
        _drawerTile(context, Icons.people_rounded, 'Usuários',
            AdminMenuItem.igrejasUsuarios),
      if (_canAccessMasterItem(AdminMenuItem.igrejasMercadoPago))
        _drawerTile(context, Icons.payment_rounded, 'Mercado Pago',
            AdminMenuItem.igrejasMercadoPago),
      if (_canAccessMasterItem(AdminMenuItem.igrejasRecebimentos))
        _drawerTile(context, Icons.receipt_long_rounded,
            'Recebimentos Licenças', AdminMenuItem.igrejasRecebimentos),
      if (_canAccessMasterItem(AdminMenuItem.igrejasGestores))
        _drawerTile(context, Icons.person_add_rounded, 'Ativar mais gestores',
            AdminMenuItem.igrejasGestores),
      if (_canAccessMasterItem(AdminMenuItem.igrejasTorreComando))
        _drawerTile(context, Icons.hub_rounded, 'Torre SaaS',
            AdminMenuItem.igrejasTorreComando),
    ];
  }

  ListTile _drawerTile(
      BuildContext context, IconData icon, String label, AdminMenuItem item) {
    final selected = _selectedItem == item;
    final isNarrow =
        MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointTablet;
    return ListTile(
      leading: Icon(icon,
          color: selected ? ThemeCleanPremium.navSidebarAccent : Colors.white70,
          size: 22),
      title: Text(label,
          style: TextStyle(
              color:
                  selected ? ThemeCleanPremium.navSidebarAccent : Colors.white,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14)),
      selected: selected,
      selectedTileColor: ThemeCleanPremium.navSidebarHover,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
      minVerticalPadding: isNarrow ? 16 : 14,
      onTap: () => _selectMenuItem(context, item),
    );
  }

  void _openDrawerMobile() {
    // No celular (iOS/Android) o drawer às vezes não abre no mesmo frame; agenda para o próximo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openDrawer();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snap) {
        final isNarrow = MediaQuery.sizeOf(context).width <
            ThemeCleanPremium.breakpointTablet;
        if (snap.hasError) {
          return Scaffold(
            backgroundColor: ThemeCleanPremium.surfaceVariant,
            appBar: AppBar(
              backgroundColor: ThemeCleanPremium.navSidebar,
              foregroundColor: Colors.white,
              title: const Text('Painel Master',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 56, color: Colors.orange),
                    const SizedBox(height: 16),
                    Text(
                      'Erro ao carregar o painel: ${snap.error}',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () =>
                          setState(() => _isAdminFuture = _isAdmin()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final loading = !snap.hasData;
        final isAdmin = snap.data ?? true;
        if (!loading && !_canAccessMasterItem(_selectedItem)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedItem = AdminMenuItem.sistemaDashboard);
          });
        }
        if (!loading && !isAdmin && !_reportedSuspiciousAccess) {
          _reportedSuspiciousAccess = true;
          unawaited(_reportSecurityEvent(
            event: "master_access_without_claim",
            resource: "admin_panel",
            details: "Usuário acessou painel master sem claim ADMIN.",
            severity: "high",
          ));
        }

        return Listener(
          onPointerDown: (_) => _touchActivity(),
          onPointerMove: (_) => _touchActivity(),
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: ThemeCleanPremium.surfaceVariant,
            drawer: isNarrow ? _buildDrawer(context, isAdmin) : null,
            drawerEdgeDragWidth: isNarrow ? 56 : null,
            appBar: isNarrow
                ? AppBar(
                    backgroundColor: ThemeCleanPremium.navSidebar,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    scrolledUnderElevation: 0.5,
                    shadowColor: const Color(0x22000000),
                    leading: IconButton(
                      icon: const Icon(Icons.menu_rounded, size: 28),
                      onPressed: _openDrawerMobile,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      tooltip: 'Abrir menu',
                    ),
                    title: Text(
                      _masterMenuTitle(_selectedItem),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 22),
                        onPressed: () async {
                          await _writeAuditLog(
                            action: 'master_logout',
                            resource: 'admin_panel',
                            details: 'Logout manual (mobile)',
                          );
                          await FirebaseAuth.instance.signOut();
                          if (!context.mounted) return;
                          Navigator.pushNamedAndRemoveUntil(
                              context, '/', (_) => false);
                        },
                        tooltip: 'Sair',
                        style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                      ),
                    ],
                  )
                : null,
            body: GlobalAnnouncementOverlay(
              child: SafeArea(
                top: !isNarrow,
                bottom: isNarrow,
                left: false,
                right: false,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isNarrow)
                            AdminMenuLateral(
                              selectedItem: _selectedItem,
                              isCollapsed: _menuCollapsed,
                              context: _adminContext,
                              onContextChanged: (ctx) => setState(() {
                                _adminContext = ctx;
                                _selectedItem =
                                    AdminMenuLateral.firstItemFor(ctx);
                              }),
                              itemVisible: _canAccessMasterItem,
                              onItemSelected: (item) =>
                                  _selectMenuItem(context, item),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (isNarrow)
                                  const _AdminMobileContextStrip(),
                                if (!isNarrow)
                                  _AdminHeader(
                                    onMenuToggle: () => setState(
                                        () => _menuCollapsed = !_menuCollapsed),
                                    onLogout: () async {
                                      await _writeAuditLog(
                                        action: 'master_logout',
                                        resource: 'admin_panel',
                                        details: 'Logout manual (desktop)',
                                      );
                                      await FirebaseAuth.instance.signOut();
                                      if (!mounted) return;
                                      Navigator.pushNamedAndRemoveUntil(
                                          context, '/', (_) => false);
                                    },
                                  ),
                                if (!isNarrow)
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
                                    child: _MasterSecurityStrip(),
                                  ),
                                if (!isAdmin)
                                  _WarnBox(
                                    text:
                                        'Este usuário não tem claim ADMIN. Para editar, use "Virar ADMIN agora".',
                                    action: FilledButton.tonalIcon(
                                      onPressed: () => _bootstrapAdmin(context),
                                      icon: const Icon(Icons.security_outlined),
                                      label: const Text('Virar ADMIN agora'),
                                    ),
                                  ),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (_, __) {
                                      return Container(
                                        margin: EdgeInsets.zero,
                                        decoration: BoxDecoration(
                                          color:
                                              ThemeCleanPremium.cardBackground,
                                          borderRadius:
                                              BorderRadius.circular(0),
                                          boxShadow: null,
                                          border: null,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: loading
                                            ? Center(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 48,
                                                      height: 48,
                                                      child: CircularProgressIndicator(
                                                          strokeWidth: 3,
                                                          color:
                                                              ThemeCleanPremium
                                                                  .primary),
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      'Carregando painel...',
                                                      style: TextStyle(
                                                          fontSize: 15,
                                                          color: Colors
                                                              .grey.shade600),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : SaaSContentViewport(
                                                child: _buildAdminContent(
                                                    context, isAdmin),
                                              ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VersionFooter(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/* =========================
   Header Clean Premium (igual painel igreja)
========================= */

class _AdminHeader extends StatelessWidget {
  final VoidCallback onMenuToggle;
  final VoidCallback onLogout;

  const _AdminHeader({required this.onMenuToggle, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = user?.displayName ?? user?.email ?? 'Admin';
    final shortName = fullName.contains(' ')
        ? fullName.split(RegExp(r'\s+')).first.trim()
        : fullName;
    final hora = DateTime.now().hour;
    final periodo = hora < 12
        ? 'bom dia'
        : hora < 18
            ? 'boa tarde'
            : 'boa noite';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 20),
            onPressed: onMenuToggle,
            tooltip: 'Menu',
            style: IconButton.styleFrom(
              foregroundColor: ThemeCleanPremium.onSurface,
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.all(8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: fullName,
              child: Text(
                'Olá, $shortName — $periodo.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: ThemeCleanPremium.onSurface.withValues(alpha: 0.88),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: onLogout,
            tooltip: 'Sair',
            style: IconButton.styleFrom(
              foregroundColor: ThemeCleanPremium.onSurface,
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.all(8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          const _AdminStatsCard(),
        ],
      ),
    );
  }
}

/// Faixa compacta no topo do conteúdo (celular): estatísticas + chips de segurança em scroll horizontal.
class _AdminMobileContextStrip extends StatelessWidget {
  const _AdminMobileContextStrip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeCleanPremium.cardBackground,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _AdminStatsCard(),
              const SizedBox(width: 10),
              const _SecurityChip(
                icon: Icons.shield_rounded,
                label: 'Sessão protegida',
                tooltip: 'Timeout automático por inatividade',
                tone: Color(0xFF166534),
                bg: Color(0xFFECFDF5),
              ),
              const SizedBox(width: 8),
              const _SecurityChip(
                icon: Icons.history_rounded,
                label: 'Auditoria',
                tooltip: 'Registro de ações no painel master',
                tone: Color(0xFF1D4ED8),
                bg: Color(0xFFEFF6FF),
              ),
              const SizedBox(width: 8),
              const _SecurityChip(
                icon: Icons.storage_rounded,
                label: 'Regras',
                tooltip: 'Firestore e Storage com regras no Firebase',
                tone: Color(0xFF7C3AED),
                bg: Color(0xFFF5F3FF),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterSecurityStrip extends StatelessWidget {
  const _MasterSecurityStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: const [
          _SecurityChip(
            icon: Icons.shield_rounded,
            label: 'Sessão protegida',
            tooltip: 'Timeout automático por inatividade',
            tone: Color(0xFF166534),
            bg: Color(0xFFECFDF5),
          ),
          _SecurityChip(
            icon: Icons.history_rounded,
            label: 'Auditoria ativa',
            tooltip: 'Registro de ações no painel master',
            tone: Color(0xFF1D4ED8),
            bg: Color(0xFFEFF6FF),
          ),
          _SecurityChip(
            icon: Icons.storage_rounded,
            label: 'Regras centralizadas',
            tooltip: 'Firestore e Storage com regras no Firebase',
            tone: Color(0xFF7C3AED),
            bg: Color(0xFFF5F3FF),
          ),
        ],
      ),
    );
  }
}

class _SecurityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color tone;
  final Color bg;

  const _SecurityChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.tone,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.15,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminStatsCard extends StatelessWidget {
  const _AdminStatsCard();

  static bool _isRevenueStatusCountable(String rawStatus) {
    final s = rawStatus.trim().toLowerCase();
    return s == 'approved' || s == 'paid' || s == 'accredited';
  }

  /// Carrega igrejas e vendas em separado: falha em `sales` (permissão) não zera a lista de igrejas.
  static Future<({int igrejas, double receita})> _loadStats() async {
    var igrejas = 0;
    var receita = 0.0;
    try {
      final igSnap =
          await FirebaseFirestore.instance.collection('igrejas').get();
      igrejas = igSnap.size;
    } catch (_) {}
    try {
      final salesSnap =
          await FirebaseFirestore.instance.collection('sales').get();
      for (final d in salesSnap.docs) {
        final status = (d.data()['status'] ?? '').toString();
        if (!_isRevenueStatusCountable(status)) continue;
        final amt = d.data()['amount'];
        if (amt is num) receita += amt.toDouble();
      }
    } catch (_) {}
    return (igrejas: igrejas, receita: receita);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({int igrejas, double receita})>(
      future: _loadStats(),
      builder: (context, snap) {
        int igrejas = 0;
        double receita = 0;
        if (snap.hasData) {
          igrejas = snap.data!.igrejas;
          receita = snap.data!.receita;
        }
        return Material(
          elevation: 0,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  color: ThemeCleanPremium.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Igrejas: $igrejas',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ThemeCleanPremium.onSurface,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      'Receita MP: R\$ ${receita.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/* Lista de igrejas: admin_igrejas_tab.dart (part) */

class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
  const _MetricCard({required this.label, required this.value});
  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(label), subtitle: Text(value.toString()));
}

class _WarnBox extends StatelessWidget {
  final String text;
  final Widget action;
  const _WarnBox({required this.text, required this.action});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: [Text(text), action]));
}

/// Diálogo para inclusão manual de nova igreja: nome, slug, plano e data para testar.
class _NovaIgrejaDialog extends StatefulWidget {
  const _NovaIgrejaDialog();

  @override
  State<_NovaIgrejaDialog> createState() => _NovaIgrejaDialogState();
}

class _NovaIgrejaDialogState extends State<_NovaIgrejaDialog> {
  final _nomeCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  String _plano = 'free';
  DateTime? _dataTeste;
  bool _saving = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o nome da igreja.')));
      return;
    }
    var slug = _slugCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (slug.isEmpty)
      slug = nome
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
    if (slug.isEmpty) slug = 'igreja_${DateTime.now().millisecondsSinceEpoch}';

    setState(() => _saving = true);
    try {
      final ref = FirebaseFirestore.instance.collection('igrejas').doc(slug);
      final exists = (await ref.get()).exists;
      if (exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Já existe uma igreja com este slug. Escolha outro.')));
        setState(() => _saving = false);
        return;
      }
      final data = <String, dynamic>{
        'name': nome,
        'nome': nome,
        'slug': slug,
        'alias': slug,
        'plano': _plano,
        'status': 'ativa',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_plano == 'premium' && _dataTeste != null) {
        data['licenseExpiresAt'] = Timestamp.fromDate(_dataTeste!);
        data['trialEndsAt'] = Timestamp.fromDate(_dataTeste!);
      } else if (_plano == 'free' && _dataTeste != null) {
        data['trialEndsAt'] = Timestamp.fromDate(_dataTeste!);
      }
      await ref.set(data);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar(
          'Igreja cadastrada. Você pode editar e cadastrar o gestor em Ativar mais gestores.'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova igreja'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nomeCtrl,
              decoration: InputDecoration(
                labelText: 'Nome da igreja',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                prefixIcon: const Icon(Icons.church_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _slugCtrl,
              decoration: InputDecoration(
                labelText: 'Slug (identificador único na URL)',
                hintText: 'ex: minha-igreja',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _plano,
              decoration: InputDecoration(
                labelText: 'Plano',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm)),
              ),
              items: const [
                DropdownMenuItem(value: 'free', child: Text('Free')),
                DropdownMenuItem(value: 'premium', child: Text('Premium')),
              ],
              onChanged: (v) => setState(() => _plano = v ?? 'free'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dataTeste ??
                      DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) setState(() => _dataTeste = picked);
              },
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Data para testar (vencimento trial)',
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                  prefixIcon: const Icon(Icons.calendar_today_rounded),
                ),
                child: Text(
                  _dataTeste != null
                      ? DateFormat('dd/MM/yyyy').format(_dataTeste!)
                      : 'Selecionar data',
                  style: TextStyle(
                      color: _dataTeste != null ? null : Colors.grey.shade600),
                ),
              ),
            ),
            if (_dataTeste != null)
              TextButton.icon(
                icon: const Icon(Icons.clear_rounded, size: 18),
                label: const Text('Limpar data'),
                onPressed: () => setState(() => _dataTeste = null),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _salvar,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Cadastrar'),
        ),
      ],
    );
  }
}

class _EditIgrejaDialog extends StatefulWidget {
  final String title;
  final bool canEdit;
  final String? tenantId;
  final Map<String, dynamic>? igreja;
  const _EditIgrejaDialog(
      {required this.title, required this.canEdit, this.tenantId, this.igreja});
  @override
  State<_EditIgrejaDialog> createState() => _EditIgrejaDialogState();
}

class _EditIgrejaDialogState extends State<_EditIgrejaDialog> {
  late String _plano;
  DateTime? _vencimento;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _plano = (widget.igreja?['plano'] ?? 'free').toString();
    if (widget.igreja?['licenseExpiresAt'] is Timestamp) {
      _vencimento = (widget.igreja!['licenseExpiresAt'] as Timestamp).toDate();
    } else if (widget.igreja?['license'] is Map) {
      final exp = (widget.igreja!['license'] as Map)['expiresAt'];
      if (exp is Timestamp) _vencimento = exp.toDate();
    }
  }

  Future<void> _salvar() async {
    final tenantId = widget.tenantId;
    if (tenantId == null || tenantId.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final billing = BillingLicenseService();
      await billing.setTenantPlano(tenantId, _plano,
          licenseExpiresAt: _plano == 'free' ? null : _vencimento);
      if (_plano != 'free' && _vencimento != null) {
        await billing.setTenantLicenseExpiresAt(tenantId, _vencimento);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Igreja atualizada.'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tenantId == null || widget.tenantId!.isEmpty) {
      return AlertDialog(
        title: Text(widget.title),
        content: const Text(
            'Cadastro manual de nova igreja em breve. Use o fluxo de cadastro pelo site.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'))
        ],
      );
    }
    final nome =
        (widget.igreja?['name'] ?? widget.igreja?['nome'] ?? widget.tenantId)
            .toString();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$nome',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _plano == 'premium' ? 'premium' : 'free',
              decoration: InputDecoration(
                labelText: 'Plano',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm)),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'free', child: Text('Free (sem licença)')),
                DropdownMenuItem(value: 'premium', child: Text('Premium')),
              ],
              onChanged: (v) => setState(() => _plano = v ?? 'free'),
            ),
            const SizedBox(height: 12),
            if (_plano == 'premium') ...[
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _vencimento ??
                        DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setState(() => _vencimento = picked);
                },
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data de vencimento da licença',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.calendar_today_rounded),
                  ),
                  child: Text(
                    _vencimento != null
                        ? DateFormat('dd/MM/yyyy').format(_vencimento!)
                        : 'Selecionar data',
                    style: TextStyle(
                        color:
                            _vencimento != null ? null : Colors.grey.shade600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_vencimento != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Limpar data'),
                  onPressed: () => setState(() => _vencimento = null),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _salvar,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

class _DetalhesIgrejaDialog extends StatelessWidget {
  final Map<String, dynamic> igreja;
  const _DetalhesIgrejaDialog({required this.igreja});
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(igreja['nome'] ?? 'Igreja'),
          content: const Text('Detalhes em breve.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'))
          ]);
}
