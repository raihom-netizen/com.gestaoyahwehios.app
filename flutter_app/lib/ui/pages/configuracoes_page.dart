import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/theme_mode_provider.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/pages/completar_cadastro_membro_page.dart';
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
  /// CPF do usuário (login) — usado em "Meu cadastro" para papel [membro].
  final String? cpf;

  const ConfiguracoesPage({super.key, required this.tenantId, required this.role, this.cpf});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  late bool _notifAvisos, _notifEscalas, _notifEventos, _notifAniversariantes;
  late bool _notifEmail, _notifCelular, _notifWeb;
  late bool _notif1Dia, _notif60Min;
  late TextEditingController _notifMinutosCtrl;
  bool _loading = true;
  final _sugestaoCtrl = TextEditingController();
  bool _sugestaoEnviando = false;
  bool _sugestaoEnviada = false;
  bool _bulkAuthLoading = false;

  bool get _podeCriarLoginsEmMassa {
    final r = widget.role.toLowerCase();
    return r == 'gestor' || r == 'adm' || r == 'admin' || r == 'master';
  }

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
    setState(() {
      _notifAvisos = prefs.getBool(_keyNotifAvisos) ?? true;
      _notifEscalas = prefs.getBool(_keyNotifEscalas) ?? true;
      _notifEventos = prefs.getBool(_keyNotifEventos) ?? true;
      _notifAniversariantes = prefs.getBool(_keyNotifAniversariantes) ?? true;
      _notifEmail = prefs.getBool(_keyNotifEmail) ?? true;
      _notifCelular = prefs.getBool(_keyNotifCelular) ?? true;
      _notifWeb = prefs.getBool(_keyNotifWeb) ?? true;
      _notif1Dia = prefs.getBool(_keyNotif1Dia) ?? true;
      _notif60Min = prefs.getBool(_keyNotif60Min) ?? true;
      _loading = false;
    });
  }

  Future<void> _saveNotif(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
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
                  if (AppPermissions.isRestrictedMember(widget.role) &&
                      (widget.cpf ?? '').replaceAll(RegExp(r'\D'), '').length == 11) ...[
                    _SectionTitle(icon: Icons.person_outline_rounded, title: 'Minha conta'),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.edit_note_rounded, color: ThemeCleanPremium.primary),
                            ),
                            title: const Text('Meus dados e senha', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text(
                              'Atualize telefone, endereço e outros dados. Troque sua senha com senha atual e nova senha — só o seu login.',
                              style: TextStyle(fontSize: 13),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              final cpfDigits = widget.cpf!.replaceAll(RegExp(r'\D'), '');
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (ctx) => CompletarCadastroMembroPage(
                                    tenantId: widget.tenantId,
                                    cpf: cpfDigits,
                                    appBarTitle: 'Meu cadastro',
                                    onComplete: () => Navigator.of(ctx).pop(),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
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
                  _SectionTitle(icon: Icons.notifications_active_rounded, title: 'Notificações'),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Receber lembretes por:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                        const SizedBox(height: 10),
                        _SwitchRow('E-mail', _notifEmail, (v) => setState(() { _notifEmail = v; _saveNotif(_keyNotifEmail, v); })),
                        _SwitchRow('Celular / App', _notifCelular, (v) => setState(() { _notifCelular = v; _saveNotif(_keyNotifCelular, v); })),
                        _SwitchRow('Web (quando instalado)', _notifWeb, (v) => setState(() { _notifWeb = v; _saveNotif(_keyNotifWeb, v); })),
                        const Divider(height: 24),
                        Text('O que notificar:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                        const SizedBox(height: 10),
                        _SwitchRow('Avisos', _notifAvisos, (v) => setState(() { _notifAvisos = v; _saveNotif(_keyNotifAvisos, v); })),
                        _SwitchRow('Escalas', _notifEscalas, (v) => setState(() { _notifEscalas = v; _saveNotif(_keyNotifEscalas, v); })),
                        _SwitchRow('Eventos', _notifEventos, (v) => setState(() { _notifEventos = v; _saveNotif(_keyNotifEventos, v); })),
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
                        Text('As notificações serão enviadas por e-mail e no app conforme suas preferências.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
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
                  if (_podeCriarLoginsEmMassa) ...[
                    _SectionTitle(icon: Icons.verified_user_rounded, title: 'Login dos membros (Firebase Auth)'),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cria conta de acesso (e-mail da pessoa + senha 123456) para todos os membros desta igreja que ainda não têm login. Cadastros pendentes continuam bloqueados no painel até aprovação.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _bulkAuthLoading ? null : () => _criarLoginsMembrosEmMassa(context),
                              icon: _bulkAuthLoading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                              label: Text(_bulkAuthLoading ? 'Processando...' : 'Criar logins para membros sem conta'),
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669), padding: const EdgeInsets.symmetric(vertical: 14)),
                            ),
                          ),
                          if (widget.role.toLowerCase() == 'master')
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'Conta MASTER: sem informar igreja, a função em nuvem pode processar todas as igrejas (use o console Firebase ou extensão).',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
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
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
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
        'members': membersSnap.docs.map((d) => {'id': d.id, 'data': d.data()}).toList(),
        'noticias': noticiasSnap.docs.map((d) => {'id': d.id, 'data': d.data()}).toList(),
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

  Future<void> _criarLoginsMembrosEmMassa(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Criar logins em massa?'),
        content: const Text(
          'Serão criadas contas Firebase Auth (e-mail + senha 123456) para membros sem login nesta igreja. Membros pendentes só entram no painel após aprovação.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Executar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulkAuthLoading = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final tid = await _resolveEffectiveTenantId();
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('bulkEnsureMembersAuth')
          .call<Map<String, dynamic>>({'tenantId': tid});
      final data = res.data;
      final msg = (data?['message'] ?? 'Concluído.').toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 8)),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? e.code), backgroundColor: ThemeCleanPremium.error),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _bulkAuthLoading = false);
    }
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
