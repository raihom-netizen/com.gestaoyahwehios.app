import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_church_features.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

/// Transmissão estilo lista de difusão — gestor, pastor, secretário (push + grupos chat).
Future<void> showChurchChatBroadcastSheet(
  BuildContext context, {
  required String tenantId,
  required String role,
  List<String>? permissions,
  List<({String id, String name})>? departmentOptions,
}) async {
  if (!AppPermissions.canSendChurchBroadcast(role, permissions: permissions)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sem permissão para enviar transmissão.'),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChurchChatBroadcastSheet(
      tenantId: tenantId,
      departmentOptions: departmentOptions ?? const [],
    ),
  );
}

class _ChurchChatBroadcastSheet extends StatefulWidget {
  final String tenantId;
  final List<({String id, String name})> departmentOptions;

  const _ChurchChatBroadcastSheet({
    required this.tenantId,
    required this.departmentOptions,
  });

  @override
  State<_ChurchChatBroadcastSheet> createState() =>
      _ChurchChatBroadcastSheetState();
}

class _ChurchChatBroadcastSheetState extends State<_ChurchChatBroadcastSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _segment = 'broadcast';
  final Set<String> _selectedDeptIds = {};
  final Set<String> _selectedMemberIds = {};
  bool _alsoPostToChatGroups = true;
  bool _sending = false;
  List<({String id, String label})> _memberItems = [];
  List<({String id, String label})> _deptItems = [];
  bool _loadingPickLists = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPickLists());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPickLists() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) return;
    try {
      if (widget.departmentOptions.isNotEmpty) {
        _deptItems = widget.departmentOptions
            .map((e) => (id: e.id, label: e.name))
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
      } else {
        final snap = await ChurchTenantResilientReads.departamentos(tid);
        _deptItems = snap.docs
            .map((d) {
              final name = churchDepartmentNameFromDoc(d);
              return (id: d.id, label: name);
            })
            .where((e) => e.label.isNotEmpty)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
      }
      final dir = await MembersDirectorySnapshotService.readOnce(tid);
      if (dir.hasEntries) {
        _memberItems = dir.entries
            .map((e) => (id: e.memberDocId, label: e.displayName))
            .where((e) => e.label.isNotEmpty)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
      } else {
        final snap = await ChurchTenantResilientReads.membrosRecent(tid, limit: 600);
        _memberItems = snap.docs
            .map((d) {
              final m = d.data();
              final name = (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '')
                  .toString()
                  .trim();
              return (id: d.id, label: name.isEmpty ? d.id : name);
            })
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPickLists = false);
  }

  Future<Set<String>?> _openMultiPick({
    required String title,
    required List<({String id, String label})> items,
    required Set<String> initial,
  }) async {
    final searchCtrl = TextEditingController();
    var selected = Set<String>.from(initial);
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            final q = searchCtrl.text.trim().toLowerCase();
            final filtered = items
                .where((e) =>
                    q.isEmpty || e.label.toLowerCase().contains(q))
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                height: MediaQuery.sizeOf(ctx).height * 0.72,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, selected),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchCtrl,
                        onChanged: (_) => setS(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          final on = selected.contains(e.id);
                          return CheckboxListTile(
                            value: on,
                            onChanged: (v) {
                              setS(() {
                                if (v == true) {
                                  selected.add(e.id);
                                } else {
                                  selected.remove(e.id);
                                }
                              });
                            },
                            title: Text(e.label),
                            subtitle: Text(e.id, maxLines: 1),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha título e mensagem.')),
      );
      return;
    }
    if (_segment == 'department' && _selectedDeptIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um departamento.')),
      );
      return;
    }
    if (_segment == 'member' && _selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um membro.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendSegmentedPush');
      final payload = <String, dynamic>{
        'tenantId': widget.tenantId,
        'title': title,
        'body': body,
        'segment': _segment,
        if (_segment == 'department' && _selectedDeptIds.isNotEmpty)
          'departmentIds': _selectedDeptIds.toList(),
        if (_segment == 'member' && _selectedMemberIds.isNotEmpty)
          'memberDocIds': _selectedMemberIds.toList(),
      };
      await fn.call(payload);

      if (_alsoPostToChatGroups &&
          (_segment == 'broadcast' || _segment == 'department')) {
        final deptTargets = <({String id, String name})>[];
        if (_segment == 'broadcast') {
          deptTargets.addAll(widget.departmentOptions);
          if (deptTargets.isEmpty) {
            for (final d in _deptItems) {
              deptTargets.add((id: d.id, name: d.label));
            }
          }
        } else {
          for (final id in _selectedDeptIds) {
            final match = _deptItems.where((e) => e.id == id).toList();
            deptTargets.add((
              id: id,
              name: match.isNotEmpty ? match.first.label : id,
            ));
          }
        }
        unawaited(
          ChurchChatChurchFeatures.postBroadcastToDepartmentThreads(
            tenantId: widget.tenantId,
            title: title,
            body: body,
            departments: deptTargets,
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Transmissão enviada${_alsoPostToChatGroups && _segment != 'member' ? ' (push + grupos)' : ''}.',
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Falha ao enviar.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: ThemeCleanPremium.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: churchChatWhatsPremiumLinearGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.campaign_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transmissão',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        Text(
                          'Lista de difusão — push + grupos do chat',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'broadcast',
                          label: Text('Toda igreja'),
                          icon: Icon(Icons.groups_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: 'department',
                          label: Text('Grupos'),
                          icon: Icon(Icons.hub_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: 'member',
                          label: Text('Membros'),
                          icon: Icon(Icons.person_rounded, size: 18),
                        ),
                      ],
                      selected: {_segment},
                      onSelectionChanged: (s) =>
                          setState(() => _segment = s.first),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Título',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bodyCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Mensagem',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (_segment == 'department') ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loadingPickLists
                            ? null
                            : () async {
                                final r = await _openMultiPick(
                                  title: 'Departamentos / grupos',
                                  items: _deptItems,
                                  initial: _selectedDeptIds,
                                );
                                if (r != null) {
                                  setState(() => _selectedDeptIds
                                    ..clear()
                                    ..addAll(r));
                                }
                              },
                        icon: const Icon(Icons.checklist_rounded),
                        label: Text(
                          _selectedDeptIds.isEmpty
                              ? 'Escolher departamentos'
                              : '${_selectedDeptIds.length} departamento(s)',
                        ),
                      ),
                    ],
                    if (_segment == 'member') ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loadingPickLists
                            ? null
                            : () async {
                                final r = await _openMultiPick(
                                  title: 'Membros',
                                  items: _memberItems,
                                  initial: _selectedMemberIds,
                                );
                                if (r != null) {
                                  setState(() => _selectedMemberIds
                                    ..clear()
                                    ..addAll(r));
                                }
                              },
                        icon: const Icon(Icons.checklist_rounded),
                        label: Text(
                          _selectedMemberIds.isEmpty
                              ? 'Escolher membros'
                              : '${_selectedMemberIds.length} membro(s)',
                        ),
                      ),
                    ],
                    if (_segment != 'member') ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Publicar nos grupos do chat'),
                        subtitle: const Text(
                          'Além do push, envia mensagem destacada nos grupos dos departamentos.',
                        ),
                        value: _alsoPostToChatGroups,
                        onChanged: (v) =>
                            setState(() => _alsoPostToChatGroups = v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_sending ? 'A enviar…' : 'Enviar transmissão'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: ThemeCleanPremium.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
