import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/department_member_integration_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// Folha para vincular membros ao departamento (mesmo fluxo do módulo Departamentos) e
/// incluir contas no thread do grupo em [ChurchChatService.ensureDepartmentThread].
Future<bool?> showChurchDepartmentAddMembersSheet(
  BuildContext context, {
  required String tenantId,
  required String departmentId,
  required String departmentName,
  required String role,
  List<String>? permissions,
  Map<String, dynamic>? departmentDocData,
  String memberCpfDigits = '',
}) {
  if (!AppPermissions.canManageDepartmentChatMembers(
    role: role,
    permissions: permissions,
    departmentData: departmentDocData,
    memberCpfDigits: memberCpfDigits,
  )) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sem permissão para gerir membros deste grupo.'),
      ),
    );
    return Future<bool>.value(false);
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChurchDepartmentAddMembersBody(
      tenantId: tenantId,
      departmentId: departmentId,
      departmentName: departmentName,
    ),
  );
}

class _ChurchDepartmentAddMembersBody extends StatefulWidget {
  final String tenantId;
  final String departmentId;
  final String departmentName;

  const _ChurchDepartmentAddMembersBody({
    required this.tenantId,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<_ChurchDepartmentAddMembersBody> createState() =>
      _ChurchDepartmentAddMembersBodyState();
}

class _ChurchDepartmentAddMembersBodyState
    extends State<_ChurchDepartmentAddMembersBody> {
  final _searchCtrl = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loading = true;
  bool _saving = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final op = await ChurchOperationalPaths.resolveCached(widget.tenantId.trim());
      final q = await           ChurchUiCollections.membros(op)
          .limit(600)
          .get();
      if (!mounted) return;
      setState(() {
        _docs = q.docs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _docs = [];
        _loading = false;
      });
    }
  }

  bool _alreadyLinked(Map<String, dynamic> d) {
    final ids = (d['departamentosIds'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        {};
    return ids.contains(widget.departmentId);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visibleDocs() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in _docs) {
      final d = doc.data();
      final st = (d['STATUS'] ?? d['status'] ?? '').toString().toLowerCase();
      if (st != 'ativo') continue;
      if (_alreadyLinked(d)) continue;
      final nome =
          (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim().toLowerCase();
      final cpf =
          (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (q.isNotEmpty) {
        if (!nome.contains(q) && !cpf.contains(q)) continue;
      }
      out.add(doc);
    }
    out.sort((a, b) {
      final na =
          (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '').toString();
      final nb =
          (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '').toString();
      return na.toLowerCase().compareTo(nb.toLowerCase());
    });
    return out;
  }

  Future<void> _confirmAdd() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    final byId = {for (final d in _docs) d.id: d};
    var okCount = 0;
    String? firstErr;
    try {
      for (final id in _selected) {
        final doc = byId[id];
        if (doc == null) continue;
        final data = doc.data();
        try {
          await DepartmentMemberIntegrationService.linkMember(
            tenantId: widget.tenantId,
            departmentId: widget.departmentId,
            memberDocId: doc.id,
            memberData: data,
          );
          final auth = (data['authUid'] ?? data['firebaseUid'] ?? '')
              .toString()
              .trim();
          if (auth.isNotEmpty) {
            await ChurchChatService.ensureDepartmentThread(
              tenantId: widget.tenantId,
              departmentId: widget.departmentId,
              departmentName: widget.departmentName,
              participantUids: [auth],
            );
          }
          okCount++;
        } catch (e) {
          firstErr ??= e.toString();
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (okCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            okCount == 1
                ? '1 membro vinculado ao departamento.'
                : '$okCount membros vinculados ao departamento.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          firstErr ?? 'Não foi possível vincular. Tente de novo.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final visible = _visibleDocs();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ThemeCleanPremium.surface,
                const Color(0xFFE0F2FE).withValues(alpha: 0.55),
                const Color(0xFFEDE9FE).withValues(alpha: 0.45),
              ],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.onSurfaceVariant
                        .withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: Row(
                  children: [
                    Icon(Icons.group_add_rounded,
                        color: ThemeCleanPremium.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adicionar ao grupo',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                          Text(
                            widget.departmentName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Pesquisar por nome ou CPF…',
                    filled: true,
                    fillColor: ThemeCleanPremium.cardBackground,
                    prefixIcon: Icon(Icons.search_rounded,
                        color: ThemeCleanPremium.primary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _docs.isEmpty
                                  ? 'Não foi possível carregar a lista de membros.'
                                  : 'Todos os membros ativos já estão neste departamento ou o filtro não encontrou ninguém.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ThemeCleanPremium.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : Stack(
                    children: [
                      ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final doc = visible[i];
                          final d = doc.data();
                          final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
                              .toString()
                              .trim();
                          final auth = (d['authUid'] ?? d['firebaseUid'] ?? '')
                              .toString()
                              .trim();
                          final label =
                              nome.isEmpty ? (auth.isEmpty ? doc.id : auth) : nome;
                          final sel = _selected.contains(doc.id);
                          final fotoUrl = imageUrlFromMap(d);
                          final dpr = MediaQuery.devicePixelRatioOf(context);
                          final mem = (44 * dpr).round().clamp(96, 220);
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            elevation: 0,
                            color: ThemeCleanPremium.cardBackground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: sel
                                    ? ThemeCleanPremium.primary
                                        .withValues(alpha: 0.45)
                                    : ThemeCleanPremium.primary
                                        .withValues(alpha: 0.08),
                              ),
                            ),
                            child: CheckboxListTile(
                              value: sel,
                              onChanged: _saving
                                  ? null
                                  : (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selected.add(doc.id);
                                        } else {
                                          _selected.remove(doc.id);
                                        }
                                      });
                                    },
                              secondary: FotoMembroWidget(
                                tenantId: widget.tenantId,
                                memberId: doc.id,
                                memberData: d,
                                imageUrl: fotoUrl.isEmpty ? null : fotoUrl,
                                size: 44,
                                memCacheWidth: mem,
                                preferListThumbnail: true,
                              ),
                              title: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                auth.isEmpty
                                    ? 'Sem login no app — entra no módulo Membros'
                                    : 'Conta vinculada — entra no chat do grupo',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_saving)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.12),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
                  child: FilledButton.icon(
                    onPressed: (_saving || _selected.isEmpty) ? null : _confirmAdd,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      _selected.isEmpty
                          ? 'Selecione membros'
                          : 'Vincular ${_selected.length} membro(s)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
