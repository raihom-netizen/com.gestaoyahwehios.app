import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import '../../services/app_permissions.dart';

class AprovarMembrosPendentesPage extends StatefulWidget {
  final String tenantId;
  final String gestorRole;
  const AprovarMembrosPendentesPage({super.key, required this.tenantId, required this.gestorRole});

  @override
  State<AprovarMembrosPendentesPage> createState() => _AprovarMembrosPendentesPageState();
}

class _AprovarMembrosPendentesPageState extends State<AprovarMembrosPendentesPage> {
  late final CollectionReference<Map<String, dynamic>> _membersCol;
  final Set<String> _selecionados = {};
  Map<String, String>? _tenantLinkageCache;
  int _pendentesStreamKey = 0;

  @override
  void initState() {
    super.initState();
    _membersCol = FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');
  }

  Future<Map<String, String>> _getTenantLinkage() async {
    if (_tenantLinkageCache != null) return _tenantLinkageCache!;
    final snap = await FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).get();
    final d = snap.data();
    final id = snap.id;
    final alias = (d?['alias'] ?? d?['slug'] ?? id).toString().trim();
    final slug = (d?['slug'] ?? d?['alias'] ?? id).toString().trim();
    _tenantLinkageCache = {'alias': alias.isEmpty ? id : alias, 'slug': slug.isEmpty ? id : slug};
    return _tenantLinkageCache!;
  }

  Future<void> _editarStatus(String id, String newStatus) async {
    final linkage = await _getTenantLinkage();
    await _membersCol.doc(id).update({
      'alias': linkage['alias'],
      'slug': linkage['slug'],
      'tenantId': widget.tenantId,
      'status': newStatus,
      'STATUS': newStatus,
      if (newStatus == 'ativo') 'aprovadoEm': FieldValue.serverTimestamp(),
      if (newStatus == 'reprovado') 'reprovadoEm': FieldValue.serverTimestamp(),
    });
    if (newStatus == 'ativo') {
      try {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('setMemberApproved').call({'tenantId': widget.tenantId, 'memberId': id});
      } catch (_) {}
    }
    setState(() => _selecionados.remove(id));
  }

  Future<void> _batchAction(String newStatus) async {
    if (_selecionados.isEmpty) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final linkage = await _getTenantLinkage();
    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selecionados) {
      batch.update(_membersCol.doc(id), {
        'alias': linkage['alias'],
        'slug': linkage['slug'],
        'tenantId': widget.tenantId,
        'status': newStatus,
        'STATUS': newStatus,
        if (newStatus == 'ativo') 'aprovadoEm': FieldValue.serverTimestamp(),
        if (newStatus == 'reprovado') 'reprovadoEm': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (newStatus == 'ativo') {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      for (final id in _selecionados) {
        try {
          await functions.httpsCallable('setMemberApproved').call({'tenantId': widget.tenantId, 'memberId': id});
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('${_selecionados.length} membro(s) ${newStatus == 'ativo' ? 'aprovado(s)' : 'reprovado(s)'}.'));
      setState(() => _selecionados.clear());
    }
  }

  Future<void> _aprovarTodos(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (docs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Aprovar todos'),
        content: Text('Deseja aprovar os ${docs.length} membro(s) pendente(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprovar todos')),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final linkage = await _getTenantLinkage();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs) {
      batch.update(_membersCol.doc(d.id), {
        'alias': linkage['alias'],
        'slug': linkage['slug'],
        'tenantId': widget.tenantId,
        'status': 'ativo',
        'STATUS': 'ativo',
        'aprovadoEm': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    for (final d in docs) {
      try {
        await functions.httpsCallable('setMemberApproved').call({'tenantId': widget.tenantId, 'memberId': d.id});
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('${docs.length} membro(s) aprovado(s)!'));
      setState(() => _selecionados.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    if (!AppPermissions.canEditDepartments(widget.gestorRole)) {
      return const Scaffold(body: Center(child: Text('Acesso restrito.')));
    }
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Voltar',
        ),
        title: const Text('Aprovar Novos Membros'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        actions: _buildActions(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile && _selecionados.isNotEmpty)
              Container(
                color: ThemeCleanPremium.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Text('${_selecionados.length} selecionado(s)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                    onPressed: () => _batchAction('ativo'),
                    tooltip: 'Aprovar',
                    style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent),
                    onPressed: () => _batchAction('reprovado'),
                    tooltip: 'Reprovar',
                    style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                  ),
                ]),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey('pendentes_$_pendentesStreamKey'),
                stream: _membersCol.where('status', isEqualTo: 'pendente').snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: ThemeCleanPremium.pagePadding(context),
                      child: ChurchPanelErrorBody(
                        title: 'Não foi possível carregar os membros pendentes',
                        error: snap.error,
                        onRetry: () =>
                            setState(() => _pendentesStreamKey++),
                      ),
                    );
                  }
                  final docs = snap.data?.docs ?? [];
                  final isLoading = snap.connectionState == ConnectionState.waiting && !snap.hasData;
                  if (isLoading) {
                    return const ChurchPanelLoadingBody();
                  }
                  if (docs.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.green.shade300),
                            const SizedBox(height: 16),
                            Text('Nenhum membro pendente!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            Text('Todos os cadastros foram aprovados ou não há solicitações.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                          ]),
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: ThemeCleanPremium.pagePadding(context),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          height: 44,
                          child: FilledButton.icon(
                            onPressed: () => _aprovarTodos(docs),
                            icon: const Icon(Icons.check_circle_rounded, size: 20),
                            label: Text('Aprovar todos (${docs.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.success,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(docs.length, (i) {
                    final d = docs[i];
                      final data = d.data();
                      final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? 'Membro').toString();
                      final email = (data['EMAIL'] ?? data['email'] ?? '').toString();
                      final foto = _photoUrlFromData(data);
                      final hasFoto = foto.isNotEmpty;
                      final sel = _selecionados.contains(d.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: sel ? ThemeCleanPremium.primary.withOpacity(0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: sel ? Border.all(color: ThemeCleanPremium.primary.withOpacity(0.3)) : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                            onTap: () => setState(() {
                              if (sel) { _selecionados.remove(d.id); } else { _selecionados.add(d.id); }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: sel,
                                    onChanged: (v) => setState(() {
                                      if (v == true) _selecionados.add(d.id); else _selecionados.remove(d.id);
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  ClipOval(
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: hasFoto
                                          ? SafeNetworkImage(
                                              imageUrl: foto,
                                              fit: BoxFit.cover,
                                              placeholder: Container(color: Colors.grey.shade400, child: Center(child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
                                              errorWidget: Container(color: Colors.grey.shade400, child: Center(child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
                                            )
                                          : Container(color: Colors.grey.shade400, child: Center(child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                    if (email.isNotEmpty) Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ])),
                                  IconButton(
                                    icon: const Icon(Icons.check_rounded, color: ThemeCleanPremium.success),
                                    onPressed: () => _editarStatus(d.id, 'ativo'),
                                    tooltip: 'Aprovar',
                                    style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close_rounded, color: Colors.red.shade400),
                                    onPressed: () => _editarStatus(d.id, 'reprovado'),
                                    tooltip: 'Reprovar',
                                    style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions() => _selecionados.isNotEmpty
      ? [
          IconButton(icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent), onPressed: () => _batchAction('ativo'), tooltip: 'Aprovar selecionados', style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget))),
          IconButton(icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent), onPressed: () => _batchAction('reprovado'), tooltip: 'Reprovar selecionados', style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget))),
        ]
      : [];

  static String _photoUrlFromData(Map<String, dynamic> data) => imageUrlFromMap(data);
}
