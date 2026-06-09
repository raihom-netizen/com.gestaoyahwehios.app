import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/billing_license_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import '../../services/app_permissions.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// Item exibido na lista: `igrejas/{churchId}/users` ou `igrejas/{churchId}/membros`.
class _UserOrMemberRow {
  final String id;
  final Map<String, dynamic> data;
  final bool isPanelUser; // true = doc em igrejas/{id}/users
  _UserOrMemberRow(this.id, this.data, {this.isPanelUser = false});

  String get nome => (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? data['displayName'] ?? 'Usuário').toString().trim();
  String get email => (data['email'] ?? '').toString();
  String get funcao => (data['funcao'] ?? data['FUNCAO'] ?? data['cargo'] ?? data['role'] ?? 'membro').toString();
  String get status => (data['status'] ?? data['STATUS'] ?? (data['ativo'] == true ? 'ativo' : 'inativo')).toString();
  List<String> get roles => (data['roles'] as List?)?.map((e) => e.toString()).toList() ?? ['membro'];
  List<String> get permissions =>
      (data['permissions'] as List?)?.map((e) => e.toString().trim().toLowerCase()).where((e) => e.isNotEmpty).toList() ?? const [];
}

class UsuariosPermissoesPage extends StatefulWidget {
  final String tenantId;
  final String gestorRole;
  final String? nomeIgreja;
  const UsuariosPermissoesPage({super.key, required this.tenantId, required this.gestorRole, this.nomeIgreja});

  @override
  State<UsuariosPermissoesPage> createState() => _UsuariosPermissoesPageState();
}

class _UsuariosPermissoesPageState extends State<UsuariosPermissoesPage> {
  CollectionReference<Map<String, dynamic>>? _usersCol;
  String? _operationalTenantId;
  static const int _membersLoadLimit = 2000;
  List<_UserOrMemberRow> _membersFromCollections = [];
  String _busca = '';

  String get _effectiveTenantId =>
      (_operationalTenantId ?? widget.tenantId).trim();

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapOperationalTenant());
  }

  Future<void> _bootstrapOperationalTenant() async {
    final seed = widget.tenantId.trim();
    if (seed.isEmpty) return;
    final op = ChurchRepository.churchId(seed);
    if (!mounted) return;
    setState(() {
      _operationalTenantId = op;
      _usersCol = ChurchUiCollections.churchDoc(op).collection('users');
    });
    await _loadMembersAndMembros();
  }

  Future<void> _loadMembersAndMembros() async {
    try {
      final churchId = await TenantResolverService.operationalChurchId(
        seed: widget.tenantId,
      );
      if (churchId.isEmpty) {
        if (mounted) setState(() => _membersFromCollections = []);
        return;
      }
      final snap = await ChurchUiCollections.membros(churchId)
          .limit(_membersLoadLimit)
          .get();
      final list = snap.docs
          .map((d) => _UserOrMemberRow(d.id, d.data(), isPanelUser: false))
          .toList();
      if (mounted) setState(() => _membersFromCollections = list);
    } catch (_) {
      if (mounted) setState(() => _membersFromCollections = []);
    }
  }

  Future<void> _editarPermissoes(String userId, List<String> roles) async {
    final col = _usersCol;
    if (col == null) return;
    await col.doc(userId).set({'roles': roles}, SetOptions(merge: true));
    setState(() {});
  }

  Future<void> _editarModulos(String userId, List<String> permissions) async {
    final col = _usersCol;
    if (col == null) return;
    final normalized = permissions.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet().toList();
    await col.doc(userId).set({'permissions': normalized}, SetOptions(merge: true));
    setState(() {});
  }

  static const List<(String key, String label)> _moduleOptions = [
    ('eventos', 'Eventos / mural de publicações'),
    ('membros', 'Membros'),
    ('departamentos', 'Departamentos'),
    ('financeiro', 'Financeiro'),
    ('patrimonio', 'Patrimônio'),
    ('fornecedores', 'Fornecedores'),
    ('certificados', 'Certificados'),
    ('escalas', 'Escalas'),
    ('relatorios', 'Relatórios'),
  ];

  Future<void> _confirmarRemoverIgreja() async {
    final nome = widget.nomeIgreja ?? widget.tenantId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Remover igreja e limpar dados')),
          ],
        ),
        content: Text(
          'Remover "$nome" e apagar TODOS os dados vinculados (membros, eventos, notícias, etc.) do banco? '
          'Esta ação é irreversível. Confirma?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, remover e limpar tudo'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removendo igreja e limpando dados...'), duration: Duration(seconds: 5)),
      );
      await BillingLicenseService().removerIgrejaELimparDados(widget.tenantId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Igreja e todos os dados vinculados foram removidos.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao remover: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    if (!AppPermissions.canEditDepartments(widget.gestorRole)) {
      return const Scaffold(body: Center(child: Text('Acesso restrito à gestão de permissões.')));
    }
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile
          ? null
          : AppBar(
              title: Text(widget.nomeIgreja != null ? 'Usuários — ${widget.nomeIgreja}' : 'Usuários & Permissões'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_forever_rounded),
                  tooltip: 'Remover igreja e limpar todos os dados',
                  onPressed: () => _confirmarRemoverIgreja(),
                ),
              ],
            ),
      body: SafeArea(
        child: _usersCol == null
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _usersCol!.watchSafe(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro ao carregar usuários.', style: TextStyle(color: Colors.grey.shade600)));
            }
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final userDocs = snap.data?.docs ?? [];
            final userIds = userDocs.map((d) => d.id).toSet();
            // Usuários com acesso ao painel (igrejas/{churchId}/users)
            final panelUsers = userDocs.map((d) => _UserOrMemberRow(d.id, d.data(), isPanelUser: true)).toList();
            // Membros que NÃO estão em users (evita duplicata)
            final onlyMembers = _membersFromCollections.where((m) => !userIds.contains(m.id)).toList();
            var merged = <_UserOrMemberRow>[...panelUsers, ...onlyMembers];
            merged.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
            final q = _busca.trim().toLowerCase();
            if (q.isNotEmpty) {
              merged = merged.where((r) =>
                r.nome.toLowerCase().contains(q) ||
                r.email.toLowerCase().contains(q) ||
                r.funcao.toLowerCase().contains(q) ||
                r.status.toLowerCase().contains(q)).toList();
            }

            if (merged.isEmpty) {
              return Column(
                children: [
                  if (isMobile) _buildRemoverIgrejaButton(),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Nenhum usuário ou membro cadastrado.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                ],
              );
            }
            return RefreshIndicator(
              onRefresh: _loadMembersAndMembros,
              child: ListView(
                padding: ThemeCleanPremium.pagePadding(context),
                children: [
                  if (isMobile) _buildRemoverIgrejaButton(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome, função ou status...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (v) => setState(() => _busca = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Total: ${merged.length}', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  ),
                  ...merged.map((row) {
                    final nome = row.nome.isEmpty ? 'Sem nome' : row.nome;
                    final ativo = row.status.toLowerCase() == 'ativo';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: ativo ? ThemeCleanPremium.primary.withValues(alpha: 0.1) : Colors.grey.shade300,
                                child: Text(nome[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, color: ativo ? ThemeCleanPremium.primary : Colors.grey.shade600)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  if (row.email.isNotEmpty) Text(row.email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  if (row.email.isEmpty && (row.funcao.isNotEmpty || row.status.isNotEmpty))
                                    Text('${row.funcao} • ${row.status}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ]),
                              ),
                            ]),
                            if (row.isPanelUser) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: AppRoles.values.map((role) => FilterChip(
                                  label: Text(role, style: TextStyle(fontSize: 12, fontWeight: row.roles.contains(role) ? FontWeight.w700 : FontWeight.normal)),
                                  selected: row.roles.contains(role),
                                  onSelected: (sel) async {
                                    final newRoles = List<String>.from(row.roles);
                                    if (sel && !newRoles.contains(role)) newRoles.add(role);
                                    if (!sel && newRoles.contains(role)) newRoles.remove(role);
                                    await _editarPermissoes(row.id, newRoles);
                                  },
                                )).toList(),
                              ),
                              const SizedBox(height: 8),
                              Text('Módulos permitidos', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _moduleOptions.map((m) {
                                  final selected = row.permissions.contains(m.$1);
                                  return FilterChip(
                                    label: Text(m.$2, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                                    selected: selected,
                                    onSelected: (sel) async {
                                      final list = List<String>.from(row.permissions);
                                      if (sel && !list.contains(m.$1)) list.add(m.$1);
                                      if (!sel && list.contains(m.$1)) list.remove(m.$1);
                                      await _editarModulos(row.id, list);
                                    },
                                  );
                                }).toList(),
                              ),
                            ] else if (row.funcao.isNotEmpty || row.status.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('${row.funcao} • ${row.status}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRemoverIgrejaButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.delete_forever_rounded, size: 20),
        label: const Text('Remover esta igreja e limpar todos os dados'),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        onPressed: _confirmarRemoverIgreja,
      ),
    );
  }
}
