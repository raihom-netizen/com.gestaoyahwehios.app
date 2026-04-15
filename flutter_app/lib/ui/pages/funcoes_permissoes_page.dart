import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_funcoes_controle_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Funções e permissões — gerenciável pelo gestor/admin: CRUD + restaurar padrões + UI premium.
class FuncoesPermissoesPage extends StatefulWidget {
  final String tenantId;
  final String role;

  const FuncoesPermissoesPage({super.key, required this.tenantId, required this.role});

  @override
  State<FuncoesPermissoesPage> createState() => _FuncoesPermissoesPageState();
}

class _FuncoesPermissoesPageState extends State<FuncoesPermissoesPage> {
  late Future<String> _resolvedIdFuture;
  bool _busy = false;

  bool get _canManage {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  @override
  void initState() {
    super.initState();
    _resolvedIdFuture = TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
  }

  List<String> _chipsForDoc(Map<String, dynamic>? data) {
    if (data == null) return [];
    final custom = data['customModules'];
    if (custom is List && custom.isNotEmpty) {
      return custom.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    final inherit = (data['permissionTemplate'] ?? data['key'] ?? '').toString();
    return ChurchFuncoesControleService.permissoesLabelsParaFuncao(inherit);
  }

  Future<void> _restorePadroes(BuildContext context, String tid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: Row(
          children: [
            Icon(Icons.restore_page_rounded, color: ThemeCleanPremium.primary, size: 28),
            const SizedBox(width: 10),
            const Expanded(child: Text('Restaurar padrões')),
          ],
        ),
        content: const Text(
          'Todas as funções personalizadas serão removidas e a lista voltará ao conjunto padrão do sistema. Membros já cadastrados mantêm a FUNCAO gravada; ajuste manualmente se necessário.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ChurchFuncoesControleService.restoreDefaults(tid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Funções restauradas aos padrões.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.feedbackSnackBar('Erro: $e'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addOrEdit(BuildContext context, String tid, {QueryDocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? {};
    final isEdit = doc != null;
    final keyCtrl = TextEditingController(text: isEdit ? (data['key'] ?? doc!.id).toString() : '');
    final labelCtrl = TextEditingController(text: (data['label'] ?? '').toString());
    final descCtrl = TextEditingController(text: (data['descricao'] ?? '').toString());
    var template = (data['permissionTemplate'] ?? data['key'] ?? 'membro').toString().toLowerCase();
    if (!ChurchFuncoesControleService.permissionTemplates.any((t) => t.key == template)) {
      template = 'membro';
    }
    var enabled = data['enabled'] != false;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            title: Text(isEdit ? 'Editar função' : 'Nova função'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isEdit) ...[
                    TextField(
                      controller: keyCtrl,
                      decoration: InputDecoration(
                        labelText: 'Chave (slug)',
                        hintText: 'ex.: voluntario_midia',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        helperText: 'Usada no cadastro do membro (sem espaços).',
                      ),
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: labelCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nome exibido',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: InputDecoration(
                      labelText: 'Descrição',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: template,
                    decoration: InputDecoration(
                      labelText: 'Permissões equivalentes a',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    ),
                    items: ChurchFuncoesControleService.permissionTemplates
                        .map((t) => DropdownMenuItem(value: t.key, child: Text(t.label)))
                        .toList(),
                    onChanged: (v) => setDlg(() => template = v ?? 'membro'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativa na lista'),
                    subtitle: const Text('Desative para ocultar ao escolher função no membro.'),
                    value: enabled,
                    onChanged: (v) => setDlg(() => enabled = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isEdit ? 'Salvar' : 'Criar')),
            ],
          );
        },
      ),
    );

    if (submitted != true || !mounted) return;

    var key = isEdit ? (data['key'] ?? doc!.id).toString().trim() : ChurchFuncoesControleService.slugifyKey(keyCtrl.text);
    if (key.isEmpty) key = ChurchFuncoesControleService.slugifyKey(labelCtrl.text);
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.feedbackSnackBar('Informe uma chave válida.'));
      return;
    }
    final label = labelCtrl.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.feedbackSnackBar('Informe o nome da função.'));
      return;
    }

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final col = ChurchFuncoesControleService.collection(tid);
      int order = 100;
      if (!isEdit) {
        final all = await col.get();
        for (final d in all.docs) {
          final o = d.data()['order'];
          if (o is int && o >= order) order = o + 1;
          if (o is num && o.toInt() >= order) order = o.toInt() + 1;
        }
      } else {
        order = (data['order'] is int) ? data['order'] as int : ((data['order'] as num?)?.toInt() ?? 50);
      }

      await col.doc(key).set({
        'key': key,
        'label': label,
        'descricao': descCtrl.text.trim(),
        'permissionTemplate': template,
        'order': order,
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!isEdit) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(isEdit ? 'Função atualizada.' : 'Função criada.'),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.feedbackSnackBar('Erro: $e'));
    }
  }

  Future<void> _delete(BuildContext context, String tid, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final key = (doc.data()['key'] ?? doc.id).toString().toLowerCase();
    if (ChurchFuncoesControleService.protectedKeys.contains(key)) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Esta função é protegida e não pode ser excluída.'),
      );
      return;
    }
    final label = (doc.data()['label'] ?? key).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Excluir função'),
          ],
        ),
        content: Text('Remover "$label" da lista? Membros que já usam esta chave continuam com o mesmo valor até você editar o cadastro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await doc.reference.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Função removida.'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.feedbackSnackBar('Erro: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: ThemeCleanPremium.onSurface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Retornar aos Membros',
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        title: Text(
          'Funções e permissões',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3, color: ThemeCleanPremium.onSurface),
        ),
        centerTitle: false,
      ),
      body: FutureBuilder<String>(
        future: _resolvedIdFuture,
        builder: (context, idSnap) {
          if (idSnap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final tid = idSnap.data ?? widget.tenantId;
          return Stack(
            children: [
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.maybePop(context),
                          icon: Icon(Icons.arrow_back_rounded, size: 20, color: ThemeCleanPremium.primary),
                          label: Text(
                            'Retornar aos Membros',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: ThemeCleanPremium.primary,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                          ),
                        ),
                      ),
                    ),
                    if (_canManage)
                      Padding(
                        padding: EdgeInsets.fromLTRB(padding.left, 4, padding.right, 8),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : () => _addOrEdit(context, tid),
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('Nova função'),
                              style: FilledButton.styleFrom(
                                backgroundColor: ThemeCleanPremium.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _restorePadroes(context, tid),
                              icon: const Icon(Icons.restore_rounded, size: 20),
                              label: const Text('Restaurar padrões'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                                foregroundColor: ThemeCleanPremium.primary,
                                side: BorderSide(color: ThemeCleanPremium.primary.withValues(alpha: 0.35)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: ChurchFuncoesControleService.collection(tid).orderBy('order').snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(child: Text('Erro: ${snap.error}', style: TextStyle(color: Colors.red.shade800)));
                          }
                          if (!snap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snap.data!.docs;
                          if (docs.isEmpty) {
                            return ListView(
                              padding: padding,
                              children: [
                                _buildInfoBanner(),
                                const SizedBox(height: 24),
                                _emptyState(tid),
                              ],
                            );
                          }
                          return ListView.builder(
                            padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, padding.bottom + 24),
                            itemCount: docs.length + 1,
                            itemBuilder: (context, i) {
                              if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 16), child: _buildInfoBanner());
                              final doc = docs[i - 1];
                              final d = doc.data();
                              final key = (d['key'] ?? doc.id).toString();
                              final label = (d['label'] ?? key).toString();
                              final desc = (d['descricao'] ?? '').toString();
                              final enabled = d['enabled'] != false;
                              final chips = _chipsForDoc(d);
                              final protected = ChurchFuncoesControleService.protectedKeys.contains(key.toLowerCase());

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.black.withValues(alpha: 0.06),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                                    side: BorderSide(color: const Color(0xFFE8EEF5)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                                    child: Theme(
                                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                      child: ExpansionTile(
                                        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                        leading: Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: enabled
                                                  ? [
                                                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                                                      ThemeCleanPremium.primary.withValues(alpha: 0.06),
                                                    ]
                                                  : [Colors.grey.shade200, Colors.grey.shade100],
                                            ),
                                            borderRadius: BorderRadius.circular(14),
                                            boxShadow: [
                                              BoxShadow(
                                                color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.badge_rounded,
                                            color: enabled ? ThemeCleanPremium.primary : Colors.grey.shade500,
                                            size: 24,
                                          ),
                                        ),
                                        title: Text(
                                          label,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            letterSpacing: -0.2,
                                            color: enabled ? ThemeCleanPremium.onSurface : Colors.grey.shade500,
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (desc.isNotEmpty)
                                                Text(desc, style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade600)),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  _miniChip('chave: $key', muted: true),
                                                  if (!enabled) _miniChip('Inativa', alert: true),
                                                  if (protected) _miniChip('Protegida', muted: true),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        trailing: _canManage
                                            ? PopupMenuButton<String>(
                                                icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                onSelected: (v) {
                                                  if (v == 'edit') _addOrEdit(context, tid, doc: doc);
                                                  if (v == 'del') _delete(context, tid, doc);
                                                },
                                                itemBuilder: (ctx) => [
                                                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded, size: 20), title: Text('Editar'), contentPadding: EdgeInsets.zero)),
                                                  if (!protected)
                                                    const PopupMenuItem(
                                                      value: 'del',
                                                      child: ListTile(
                                                        leading: Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFDC2626)),
                                                        title: Text('Excluir', style: TextStyle(color: Color(0xFFDC2626))),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                ],
                                              )
                                            : Icon(Icons.expand_more_rounded, color: Colors.grey.shade400),
                                        children: [
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Pode acessar:',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: chips
                                                .map(
                                                  (p) => Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF8FAFC),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withValues(alpha: 0.03),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Text(
                                                      p,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: ThemeCleanPremium.primary.withValues(alpha: 0.9),
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy) const ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator())),
            ],
          );
        },
      ),
    );
  }

  Widget _miniChip(String text, {bool muted = false, bool alert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: alert ? const Color(0xFFFFF1F2) : (muted ? const Color(0xFFF1F5F9) : const Color(0xFFEFF6FF)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alert ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: alert ? const Color(0xFFB91C1C) : Colors.grey.shade700),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            const Color(0xFFF8FAFC),
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE8EEF5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.info_outline_rounded, color: ThemeCleanPremium.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _canManage
                  ? 'Cada função define o que o membro pode ver no painel. Você pode criar funções extras (com permissões equivalentes a um perfil existente), editar textos, desativar ou excluir. Use Restaurar padrões se precisar recomeçar.'
                  : 'Cada função define o que o membro pode ver e acessar no sistema. A função é definida ao editar o membro.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String tid) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE8EEF5)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Nenhuma função cadastrada',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 8),
          Text(
            'Toque em Restaurar padrões para carregar a lista oficial ou crie uma nova função.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
          ),
          if (_canManage) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : () => _restorePadroes(context, tid),
              icon: const Icon(Icons.restore_page_rounded),
              label: const Text('Restaurar padrões agora'),
            ),
          ],
        ],
      ),
    );
  }
}
