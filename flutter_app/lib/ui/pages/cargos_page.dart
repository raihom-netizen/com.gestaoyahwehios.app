import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/pages/lideranca_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show SafeCircleAvatarImage, imageUrlFromMap;
import 'members_page.dart' show MembersPage;

class _WelcomeCargoRow {
  final String docId;
  final String name;
  final String key;
  final String permissionTemplate;
  final int hierarchyLevel;
  final int accentColor;
  final bool requiresConsecrationDate;

  const _WelcomeCargoRow({
    required this.docId,
    required this.name,
    required this.key,
    required this.permissionTemplate,
    required this.hierarchyLevel,
    required this.accentColor,
    required this.requiresConsecrationDate,
  });
}

/// Cargos (funções) da igreja — cadastro em Pessoas.
/// Super Premium: cards clicáveis, lista de membros vinculados, remover/alterar cargo.
class CargosPage extends StatefulWidget {
  final String tenantId;
  final String role;

  const CargosPage({super.key, required this.tenantId, required this.role});

  @override
  State<CargosPage> createState() => _CargosPageState();
}

class _CargosPageState extends State<CargosPage> {
  String? _resolvedTenantId;
  late Future<QuerySnapshot<Map<String, dynamic>>> _cargosFuture;
  /// Evita loop ao criar cargos padrão automaticamente.
  bool _triedAutoSeed = false;

  static const _welcomeCargos = <_WelcomeCargoRow>[
    _WelcomeCargoRow(
      docId: 'welcome_pastor_presidente',
      name: 'Pastor Presidente / Administrador',
      key: 'pastor_presidente',
      permissionTemplate: 'pastor_presidente',
      hierarchyLevel: 100,
      accentColor: 0xFF1565C0,
      requiresConsecrationDate: true,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_pastor_auxiliar',
      name: 'Pastor Auxiliar / Ministerial',
      key: 'pastor_auxiliar',
      permissionTemplate: 'pastor_auxiliar',
      hierarchyLevel: 88,
      accentColor: 0xFF5E35B1,
      requiresConsecrationDate: true,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_secretario',
      name: 'Secretário(a)',
      key: 'secretario',
      permissionTemplate: 'secretario',
      hierarchyLevel: 72,
      accentColor: 0xFF00897B,
      requiresConsecrationDate: false,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_tesoureiro',
      name: 'Tesoureiro(a)',
      key: 'tesoureiro',
      permissionTemplate: 'tesoureiro',
      hierarchyLevel: 65,
      accentColor: 0xFF2E7D32,
      requiresConsecrationDate: false,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_lider_departamento',
      name: 'Líder de Departamento',
      key: 'lider_departamento',
      permissionTemplate: 'lider_departamento',
      hierarchyLevel: 55,
      accentColor: 0xFF6A1B9A,
      requiresConsecrationDate: false,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_membro',
      name: 'Membro / Congregado',
      key: 'membro',
      permissionTemplate: 'membro',
      hierarchyLevel: 12,
      accentColor: 0xFF78909C,
      requiresConsecrationDate: false,
    ),
  ];

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore.instance
      .collection('igrejas')
      .doc(_resolvedTenantId ?? widget.tenantId)
      .collection('cargos');

  bool get _canWrite =>
      AppPermissions.canEditAnyChurchMember(widget.role) ||
      AppPermissions.canEditDepartments(widget.role);

  @override
  void initState() {
    super.initState();
    _resolveAndLoad();
  }

  Future<void> _resolveAndLoad() async {
    _resolvedTenantId = await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
    if (mounted) setState(() => _cargosFuture = _col.orderBy('name').get());
  }

  /// Cria na base os cargos padrão quando a coleção está vazia (novas igrejas).
  Future<void> _seedPadroes() async {
    try {
      final snap = await _col.limit(1).get();
      if (snap.docs.isNotEmpty) return;
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final batch = FirebaseFirestore.instance.batch();
      for (var i = 0; i < _welcomeCargos.length; i++) {
        final row = _welcomeCargos[i];
        batch.set(_col.doc(row.docId), <String, dynamic>{
          'name': row.name,
          'key': row.key,
          'permissionTemplate': row.permissionTemplate,
          'hierarchyLevel': row.hierarchyLevel,
          'accentColor': row.accentColor,
          'requiresConsecrationDate': row.requiresConsecrationDate,
          'order': i,
          'isDefaultPreset': true,
          'isWelcomeKit': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('CargosPage _seedPadroes: $e');
    }
    if (mounted) setState(() => _cargosFuture = _col.orderBy('name').get());
  }

  static String _nameToKey(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâã]'), 'a')
        .replaceAll(RegExp(r'[éèê]'), 'e')
        .replaceAll(RegExp(r'[íì]'), 'i')
        .replaceAll(RegExp(r'[óòôõ]'), 'o')
        .replaceAll(RegExp(r'[úù]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  void _refresh() {
    setState(() => _cargosFuture = _col.orderBy('name').get());
  }

  Future<void> _addOrEdit({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    if (!_canWrite) return;
    final data = doc?.data() ?? {};
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: Text(doc == null ? 'Novo cargo' : 'Editar cargo'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nome do cargo',
            prefixIcon: Icon(Icons.badge_rounded),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do cargo.')));
      return;
    }
    final key = _nameToKey(name);
    if (key.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nome inválido para o cargo.')));
      return;
    }
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (doc == null) {
        await _col.doc(key).set({
          'name': name,
          'key': key,
          'order': 999,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo cadastrado!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      } else {
        await doc.reference.update({'name': name, 'key': key, 'updatedAt': FieldValue.serverTimestamp()});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo atualizado!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      }
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  Future<void> _delete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_canWrite) return;
    final name = (doc.data()?['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(children: [Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)), SizedBox(width: 10), Text('Excluir cargo')]),
        content: Text('Excluir o cargo "$name"? Membros com este cargo continuarão com o valor no cadastro, mas o cargo não aparecerá mais na lista.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo excluído.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  void _openCargoMembros(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final name = (data['name'] ?? doc.id).toString();
    final key = (data['key'] ?? doc.id).toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CargoMembrosPage(
          tenantId: _resolvedTenantId ?? widget.tenantId,
          role: widget.role,
          cargoName: name,
          cargoKey: key,
          canWrite: _canWrite,
          onChanged: _refresh,
        ),
      ),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile
          ? null
          : AppBar(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              title: const Text('Cargos', style: TextStyle(fontWeight: FontWeight.w800)),
              elevation: 0,
              actions: [
                IconButton(
                  tooltip: 'Liderança (organograma)',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => LiderancaPage(
                          tenantId: _resolvedTenantId ?? widget.tenantId,
                          role: widget.role,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_tree_rounded),
                  style: IconButton.styleFrom(
                      minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget)),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                ),
                if (_canWrite)
                  IconButton(
                    tooltip: 'Novo cargo',
                    onPressed: () => _addOrEdit(),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                  ),
              ],
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Container(
                padding: EdgeInsets.fromLTRB(padding.left, 16, padding.right, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary,
                      ThemeCleanPremium.primary.withOpacity(0.9),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                      child: const Icon(Icons.badge_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cargos',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                          ),
                          Text(
                            'Toque em um cargo para ver membros',
                            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Liderança',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => LiderancaPage(
                              tenantId: _resolvedTenantId ?? widget.tenantId,
                              role: widget.role,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.account_tree_rounded,
                          color: Colors.white),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget)),
                    ),
                    IconButton(
                      tooltip: 'Atualizar',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                    ),
                    if (_canWrite)
                      IconButton(
                        tooltip: 'Novo cargo',
                        onPressed: () => _addOrEdit(),
                        icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                        style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _cargosFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const ChurchPanelLoadingBody();
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: ChurchPanelErrorBody(
                        title: 'Não foi possível carregar os cargos',
                        error: snap.error,
                        onRetry: _refresh,
                      ),
                    );
                  }
                  var docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    if (_canWrite && !_triedAutoSeed) {
                      _triedAutoSeed = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await _seedPadroes();
                        if (mounted) _refresh();
                      });
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(strokeWidth: 3, color: ThemeCleanPremium.primary),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Preparando cargos padrão…',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.onSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_welcomeCargos.length} cargos com hierarquia e permissões. Você pode editar ou excluir depois.',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (_canWrite) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Icon(Icons.badge_rounded, size: 64, color: ThemeCleanPremium.primary.withOpacity(0.7)),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Nenhum cargo cadastrado',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ThemeCleanPremium.onSurface),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Não foi possível criar os padrões automaticamente. Tente de novo ou cadastre manualmente.',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () async {
                                  await _seedPadroes();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Cargos padrão criados!', style: TextStyle(color: Colors.white)),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.add_box_rounded),
                                label: const Text('Criar cargos padrão'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _addOrEdit(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Novo cargo manual'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nenhum cargo cadastrado nesta igreja.',
                          style: TextStyle(fontSize: 15, color: ThemeCleanPremium.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  docs = List.from(docs)
                    ..sort((a, b) => ((a.data()['name'] ?? '').toString().toLowerCase()).compareTo((b.data()['name'] ?? '').toString().toLowerCase()));
                  return RefreshIndicator(
                    onRefresh: () async {
                      _refresh();
                      await _cargosFuture;
                    },
                    color: ThemeCleanPremium.primary,
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, isMobile ? 100 : padding.bottom),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final name = (d.data()['name'] ?? d.id).toString();
                        final key = (d.data()['key'] ?? d.id).toString();
                        return _CargoCardSuperPremium(
                          cargoName: name,
                          cargoKey: key,
                          canWrite: _canWrite,
                          onTap: () => _openCargoMembros(d),
                          onEdit: () => _addOrEdit(doc: d),
                          onDelete: () => _delete(d),
                          onViewMembros: () => _openCargoMembros(d),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _addOrEdit(),
              backgroundColor: ThemeCleanPremium.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Novo cargo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

/// Card de cargo Super Premium — clicável, abre membros vinculados
class _CargoCardSuperPremium extends StatelessWidget {
  final String cargoName;
  final String cargoKey;
  final bool canWrite;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewMembros;

  const _CargoCardSuperPremium({
    required this.cargoName,
    required this.cargoKey,
    required this.canWrite,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onViewMembros,
  });

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Container(
      margin: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    ),
                    child: Icon(Icons.badge_rounded, color: ThemeCleanPremium.primary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cargoName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Toque para ver membros vinculados',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                  if (canWrite) ...[
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600, size: 22),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'delete') onDelete();
                        if (v == 'view') onViewMembros();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.people_rounded, size: 20), SizedBox(width: 10), Text('Ver membros')])),
                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 10), Text('Editar')])),
                        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFDC2626)), SizedBox(width: 10), Text('Excluir', style: TextStyle(color: Color(0xFFDC2626)))]))
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Página de membros vinculados a um cargo — remover ou alterar cargo
class _CargoMembrosPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String cargoName;
  final String cargoKey;
  final bool canWrite;
  final VoidCallback onChanged;

  const _CargoMembrosPage({
    required this.tenantId,
    required this.role,
    required this.cargoName,
    required this.cargoKey,
    required this.canWrite,
    required this.onChanged,
  });

  @override
  State<_CargoMembrosPage> createState() => _CargoMembrosPageState();
}

class _CargoMembrosPageState extends State<_CargoMembrosPage> {
  List<_MemberWithRef> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    var allIds = await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(widget.tenantId);
    if (allIds.isEmpty) allIds = [widget.tenantId];
    final db = FirebaseFirestore.instance;
    final seen = <String>{};
    final list = <_MemberWithRef>[];
    final cargoKeyNorm = widget.cargoKey.toLowerCase().trim();
    final cargoNameNorm = widget.cargoName.toLowerCase().trim();

    for (final tid in allIds) {
      for (final col in [
        db.collection('igrejas').doc(tid).collection('membros'),
        db.collection('igrejas').doc(tid).collection('membros'),
        db.collection('igrejas').doc(tid).collection('membros'),
        db.collection('igrejas').doc(tid).collection('membros'),
      ]) {
        try {
          final snap = await col.limit(500).get();
          for (final doc in snap.docs) {
            if (seen.contains(doc.id)) continue;
            final d = doc.data();
            final funcoes = d['FUNCOES'] ?? d['funcoes'];
            final cargo = (d['CARGO'] ?? d['cargo'] ?? d['funcao'] ?? d['role'] ?? '').toString().trim().toLowerCase();
            bool hasCargo = false;
            if (funcoes is List) {
              for (final f in funcoes) {
                final s = (f ?? '').toString().trim().toLowerCase();
                if (s == cargoKeyNorm || s == cargoNameNorm) {
                  hasCargo = true;
                  break;
                }
              }
            }
            if (!hasCargo && (cargo == cargoKeyNorm || cargo == cargoNameNorm)) hasCargo = true;
            if (hasCargo) {
              seen.add(doc.id);
              list.add(_MemberWithRef(id: doc.id, data: d, ref: doc.reference));
            }
          }
        } catch (_) {}
      }
    }
    list.sort((a, b) {
      final na = _nome(a.data).toLowerCase();
      final nb = _nome(b.data).toLowerCase();
      return na.compareTo(nb);
    });
    if (mounted) setState(() {
      _members = list;
      _loading = false;
    });
  }

  static String _nome(Map<String, dynamic> d) =>
      (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? 'Membro').toString().trim();

  static String? _fotoUrl(Map<String, dynamic> d) {
    final u = imageUrlFromMap(d);
    return u.isNotEmpty ? u : null;
  }

  Future<void> _removeCargo(_MemberWithRef m) async {
    if (!widget.canWrite) return;
    final name = _nome(m.data);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Remover cargo'),
        content: Text('Remover o cargo "${widget.cargoName}" de "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
      List<String> funcoes = funcoesRaw is List
          ? funcoesRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toList()
          : [];
      final cargoKeyNorm = widget.cargoKey.toLowerCase().trim();
      final cargoNameNorm = widget.cargoName.toLowerCase().trim();
      funcoes.removeWhere((f) {
        final s = f.toLowerCase();
        return s == cargoKeyNorm || s == cargoNameNorm;
      });
      if (funcoes.isEmpty) funcoes = ['membro'];
      final funcaoFinal = funcoes.first;
      final updates = <String, dynamic>{
        'FUNCOES': funcoes,
        'CARGO': funcaoFinal,
        'funcao': funcaoFinal,
        'role': funcaoFinal.toLowerCase(),
      };
      var allIds = await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(widget.tenantId);
      if (allIds.isEmpty) allIds = [widget.tenantId];
      final db = FirebaseFirestore.instance;
      for (final tid in allIds) {
        for (final col in [
          db.collection('igrejas').doc(tid).collection('membros'),
          db.collection('igrejas').doc(tid).collection('membros'),
          db.collection('igrejas').doc(tid).collection('membros'),
          db.collection('igrejas').doc(tid).collection('membros'),
        ]) {
          try {
            await col.doc(m.id).set(updates, SetOptions(merge: true));
          } catch (_) {}
        }
      }
      final authUid = (m.data['authUid'] ?? '').toString().trim();
      if (authUid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(authUid).set({
            'role': funcaoFinal.toLowerCase(),
            'funcao': funcaoFinal,
            'cargo': funcaoFinal,
            'FUNCOES': funcoes,
            'CARGO': funcaoFinal,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo removido.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        _loadMembers();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _changeCargo(_MemberWithRef m) async {
    if (!_canWrite) return;
    final cargosSnap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('cargos')
        .orderBy('name')
        .get();
    final cargos = cargosSnap.docs
        .map((d) => (key: (d.data()['key'] ?? d.id).toString(), name: (d.data()['name'] ?? d.id).toString()))
        .where((c) => c.key != widget.cargoKey)
        .toList();
    if (cargos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não há outros cargos para alterar.')));
      return;
    }
    String? selectedKey;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
          title: Text('Alterar cargo de ${_nome(m.data)}'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Selecione o novo cargo:', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                ...cargos.map((c) => RadioListTile<String>(
                      title: Text(c.name),
                      value: c.key,
                      groupValue: selectedKey,
                      onChanged: (v) {
                        selectedKey = v;
                        setDlg(() {});
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: selectedKey != null ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Alterar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || selectedKey == null || !mounted) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
      List<String> funcoes = funcoesRaw is List
          ? funcoesRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toList()
          : [];
      final cargoKeyNorm = widget.cargoKey.toLowerCase().trim();
      funcoes.removeWhere((f) => f.toLowerCase() == cargoKeyNorm);
      funcoes.add(selectedKey!);
      final funcaoFinal = selectedKey!;
      final updates = <String, dynamic>{
        'FUNCOES': funcoes,
        'CARGO': funcaoFinal,
        'funcao': funcaoFinal,
        'role': funcaoFinal.toLowerCase(),
      };
      var allIds = await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(widget.tenantId);
      if (allIds.isEmpty) allIds = [widget.tenantId];
      final db = FirebaseFirestore.instance;
      for (final tid in allIds) {
        for (final col in [
          db.collection('igrejas').doc(tid).collection('membros'),
          db.collection('igrejas').doc(tid).collection('membros'),
          db.collection('igrejas').doc(tid).collection('membros'),
          db.collection('igrejas').doc(tid).collection('membros'),
        ]) {
          try {
            await col.doc(m.id).set(updates, SetOptions(merge: true));
          } catch (_) {}
        }
      }
      final authUid = (m.data['authUid'] ?? '').toString().trim();
      if (authUid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(authUid).set({
            'role': funcaoFinal.toLowerCase(),
            'funcao': funcaoFinal,
            'cargo': funcaoFinal,
            'FUNCOES': funcoes,
            'CARGO': funcaoFinal,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo alterado.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        _loadMembers();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  bool get _canWrite => widget.canWrite;

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.cargoName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${_members.length} membro${_members.length != 1 ? 's' : ''} vinculado${_members.length != 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9))),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadMembers,
            tooltip: 'Atualizar',
            style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2.5, color: ThemeCleanPremium.primary)),
                  const SizedBox(height: 16),
                  Text('Carregando membros...', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                ],
              ),
            )
          : _members.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum membro com este cargo',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vincule membros no cadastro de Membros.',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MembersPage(tenantId: widget.tenantId, role: widget.role))),
                          icon: const Icon(Icons.people_rounded),
                          label: const Text('Ir para Membros'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMembers,
                  color: ThemeCleanPremium.primary,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(padding.left, 16, padding.right, padding.bottom + 24),
                    itemCount: _members.length,
                    itemBuilder: (_, i) {
                      final m = _members[i];
                      final foto = _fotoUrl(m.data);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MembersPage(tenantId: widget.tenantId, role: widget.role))),
                            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SafeCircleAvatarImage(
                                      imageUrl: foto,
                                      radius: 26,
                                      fallbackIcon: Icons.person_rounded,
                                      fallbackColor: ThemeCleanPremium.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_nome(m.data), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                                        Text(
                                          (m.data['EMAIL'] ?? m.data['email'] ?? '').toString(),
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_canWrite)
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                      onSelected: (v) {
                                        if (v == 'remove') _removeCargo(m);
                                        if (v == 'change') _changeCargo(m);
                                        if (v == 'edit') Navigator.push(context, MaterialPageRoute(builder: (_) => MembersPage(tenantId: widget.tenantId, role: widget.role)));
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'change', child: Row(children: [Icon(Icons.swap_horiz_rounded, size: 20), SizedBox(width: 10), Text('Alterar cargo')])),
                                        const PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.person_remove_rounded, size: 20, color: Color(0xFFDC2626)), SizedBox(width: 10), Text('Remover cargo', style: TextStyle(color: Color(0xFFDC2626)))])),
                                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 10), Text('Editar membro')])),
                                      ],
                                    ),
                                ],
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

class _MemberWithRef {
  final String id;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> ref;
  _MemberWithRef({required this.id, required this.data, required this.ref});
}
