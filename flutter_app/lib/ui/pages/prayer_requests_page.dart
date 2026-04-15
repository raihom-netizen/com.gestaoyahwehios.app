import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

/// E-mail na ficha do membro (várias chaves usadas no app).
String _emailFromMemberData(Map<String, dynamic> data) {
  for (final k in ['EMAIL', 'email', 'Email', 'E_MAIL', 'e_mail']) {
    final v = data[k];
    if (v != null) {
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
  }
  return '';
}

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _paginateSubcollection(
  DocumentReference<Map<String, dynamic>> churchRef,
  String subName,
) async {
  const batch = 500;
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Query<Map<String, dynamic>> q = churchRef
      .collection(subName)
      .orderBy(FieldPath.documentId)
      .limit(batch);
  while (true) {
    final snap = await q.get();
    out.addAll(snap.docs);
    if (snap.docs.length < batch) break;
    final last = snap.docs.last;
    q = churchRef
        .collection(subName)
        .orderBy(FieldPath.documentId)
        .startAfterDocument(last)
        .limit(batch);
  }
  return out;
}

class PrayerRequestsPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Dentro de [IgrejaCleanShell]: remove cabeçalho duplicado e ajusta [SafeArea].
  final bool embeddedInShell;
  const PrayerRequestsPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<PrayerRequestsPage> createState() => _PrayerRequestsPageState();
}

class _PrayerRequestsPageState extends State<PrayerRequestsPage> {
  /// Filtro por status: Todos | Respondidas | Não Respondidas
  String _filtroStatus = 'Todos';
  late Future<QuerySnapshot<Map<String, dynamic>>> _pedidosFuture;

  Query<Map<String, dynamic>> _getQuery() {
    Query<Map<String, dynamic>> q = _col.orderBy('createdAt', descending: true);
    if (_filtroStatus == 'Respondidas') {
      q = q.where('respondida', isEqualTo: true);
    } else if (_filtroStatus == 'Não Respondidas') {
      q = q.where('respondida', isEqualTo: false);
    }
    return q;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadPedidos() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 150));
    return _getQuery().get();
  }

  void _refreshPedidos() {
    setState(() {
      _pedidosFuture = _loadPedidos();
    });
  }

  @override
  void initState() {
    super.initState();
    _pedidosFuture = _loadPedidos();
  }

  static const _filtrosStatus = ['Todos', 'Não Respondidas', 'Respondidas'];

  /// Categorias usadas no formulário (novo/editar) — o assunto é o texto do pedido.
  static const _categoriasForm = [
    'Saúde', 'Família', 'Finanças', 'Trabalho', 'Libertação', 'Gratidão', 'Outro',
  ];

  static const _categoriaCores = <String, Color>{
    'Saúde': Color(0xFFE8F5E9),
    'Família': Color(0xFFFFF3E0),
    'Finanças': Color(0xFFE3F2FD),
    'Trabalho': Color(0xFFF3E5F5),
    'Libertação': Color(0xFFFCE4EC),
    'Gratidão': Color(0xFFFFF8E1),
    'Outro': Color(0xFFF5F5F5),
  };

  static const _categoriaTexto = <String, Color>{
    'Saúde': Color(0xFF1B5E20),
    'Família': Color(0xFFBF360C),
    'Finanças': Color(0xFF0D47A1),
    'Trabalho': Color(0xFF4A148C),
    'Libertação': Color(0xFFB71C1C),
    'Gratidão': Color(0xFFB45309),
    'Outro': Color(0xFF424242),
  };

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('pedidosOracao');

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  bool get _isLeader {
    final r = widget.role.toLowerCase();
    return r == 'adm' ||
        r == 'admin' ||
        r == 'gestor' ||
        r == 'master' ||
        r == 'pastor' ||
        r == 'lider';
  }

  bool _canSee(Map<String, dynamic> data) {
    if (data['publico'] == true) return true;
    if (_isLeader) return true;
    if (data['autorUid'] == _currentUser?.uid) return true;
    final emails = data['destinatariosEmails'];
    if (emails is List && emails.isNotEmpty && _currentUser?.email != null) {
      if (emails.any((e) => e.toString().trim().toLowerCase() == _currentUser!.email!.trim().toLowerCase())) return true;
    }
    return false;
  }

  bool _canManage(Map<String, dynamic> data) {
    if (_isLeader) return true;
    if (data['autorUid'] == _currentUser?.uid) return true;
    return false;
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${(diff.inDays / 30).floor()}m';
  }

  Future<void> _toggleOrando(String docId, List<dynamic> orandoUids) async {
    final uid = _currentUser?.uid;
    if (uid == null) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (orandoUids.contains(uid)) {
      await _col.doc(docId).update({
        'orandoUids': FieldValue.arrayRemove([uid]),
        'orandoCount': FieldValue.increment(-1),
      });
    } else {
      await _col.doc(docId).update({
        'orandoUids': FieldValue.arrayUnion([uid]),
        'orandoCount': FieldValue.increment(1),
      });
    }
    if (mounted) _refreshPedidos();
  }

  Future<void> _marcarRespondida(String docId) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await _col.doc(docId).update({'respondida': true});
    if (mounted) _refreshPedidos();
  }

  Future<void> _deletar(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir pedido'),
        content: const Text('Deseja realmente excluir este pedido de oração?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        await _col.doc(docId).delete();
        if (mounted) {
          _refreshPedidos();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido excluído.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
      }
    }
  }

  /// Decoração “super premium” para o sheet de novo/editar pedido.
  static BoxDecoration get _prayerSheetDecoration => BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ThemeCleanPremium.radiusLg)),
        border: Border.all(color: const Color(0xFFE8EDF3)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      );

  static const Color _chipBorderUnselected = Color(0xFFCBD5E1);
  static const Color _chipLabelUnselected = Color(0xFF334155);

  /// Categoria: contraste explícito (ChoiceChip + tema M3 gerava texto claro em fundo claro).
  Widget _buildPrayerCategoriaChip({
    required String cat,
    required String selectedCat,
    required ValueChanged<String> onSelect,
  }) {
    final sel = selectedCat == cat;
    final accent = _categoriaTexto[cat] ?? const Color(0xFF475569);
    final fill = _categoriaCores[cat] ?? const Color(0xFFF1F5F9);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(cat),
        borderRadius: BorderRadius.circular(14),
        splashColor: accent.withValues(alpha: 0.14),
        highlightColor: accent.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            color: sel ? fill : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel ? accent : _chipBorderUnselected,
              width: sel ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: sel
                    ? accent.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: sel ? 12 : 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sel) ...[
                  Icon(Icons.check_circle_rounded, size: 18, color: accent),
                  const SizedBox(width: 6),
                ],
                Text(
                  cat,
                  style: TextStyle(
                    color: sel ? accent : _chipLabelUnselected,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.2,
                    letterSpacing: 0.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _abrirFormularioEdicao(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final textoCtrl = TextEditingController(text: (data['texto'] ?? '').toString());
    String categoria = (data['categoria'] ?? 'Outro').toString();
    bool publico = data['publico'] == true;
    final destRaw = data['destinatariosEmails'];
    List<String> destinatariosEmails = destRaw is List ? destRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet().toList() : [];
    String visibilidade = publico ? 'publico' : (destinatariosEmails.isNotEmpty ? 'membros' : 'lideres');
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: _prayerSheetDecoration,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.92,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ThemeCleanPremium.radiusLg)),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary.withValues(alpha: 0.45),
                        ThemeCleanPremium.primaryLight.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: ThemeCleanPremium.spaceLg,
                      right: ThemeCleanPremium.spaceLg,
                      top: ThemeCleanPremium.spaceMd,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom +
                          ThemeCleanPremium.spaceLg,
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Editar Pedido de Oração',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: TextButton.styleFrom(
                                  foregroundColor: ThemeCleanPremium.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: ThemeCleanPremium.spaceSm,
                                    vertical: ThemeCleanPremium.spaceXs,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          TextFormField(
                            controller: textoCtrl,
                            maxLines: 4,
                            maxLength: 500,
                            decoration: const InputDecoration(
                              labelText: 'Seu pedido de oração',
                              hintText: 'Compartilhe aqui seu pedido...',
                              alignLabelWithHint: true,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Informe o pedido'
                                : null,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Text('Categoria',
                              style: Theme.of(ctx).textTheme.titleSmall),
                          const SizedBox(height: ThemeCleanPremium.spaceXs),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _categoriasForm
                                .map(
                                  (c) => _buildPrayerCategoriaChip(
                                    cat: c,
                                    selectedCat: categoria,
                                    onSelect: (v) =>
                                        setLocal(() => categoria = v),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Text('Quem pode ver',
                              style: Theme.of(ctx).textTheme.titleSmall),
                          const SizedBox(height: ThemeCleanPremium.spaceXs),
                          ...['publico', 'lideres', 'membros'].map(
                              (v) => RadioListTile<String>(
                                    title: Text(v == 'publico'
                                        ? 'Público (todos os membros)'
                                        : v == 'lideres'
                                            ? 'Apenas líderes'
                                            : 'Membros selecionados'),
                                    value: v,
                                    groupValue: visibilidade,
                                    onChanged: (val) => setLocal(() =>
                                        visibilidade = val ?? visibilidade),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                  )),
                          if (visibilidade == 'membros') ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await _abrirSeletorMembros(
                                    ctx, widget.tenantId, destinatariosEmails);
                                if (ctx.mounted && picked != null) {
                                  setLocal(() => destinatariosEmails = picked);
                                }
                              },
                              icon: const Icon(Icons.people_rounded, size: 20),
                              label: Text(destinatariosEmails.isEmpty
                                  ? 'Selecionar membros'
                                  : '${destinatariosEmails.length} membro(s) selecionado(s)'),
                            ),
                          ],
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: ThemeCleanPremium.minTouchTarget,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: ThemeCleanPremium.primary,
                                      side: BorderSide(
                                        color: ThemeCleanPremium.primary
                                            .withValues(alpha: 0.55),
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancelar'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: ThemeCleanPremium.spaceSm),
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: ThemeCleanPremium.minTouchTarget,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: ThemeCleanPremium.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    onPressed: () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }
                                      final pub = visibilidade == 'publico';
                                      final dest = visibilidade == 'membros'
                                          ? destinatariosEmails
                                          : <String>[];
                                      if (visibilidade == 'membros' &&
                                          dest.isEmpty) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'Selecione pelo menos um membro.')));
                                        return;
                                      }
                                      try {
                                        await FirebaseAuth.instance.currentUser
                                            ?.getIdToken(true);
                                        await _col.doc(doc.id).update({
                                          'texto': textoCtrl.text.trim(),
                                          'categoria': categoria,
                                          'publico': pub,
                                          'destinatariosEmails': dest,
                                        });
                                        if (ctx.mounted) {
                                          _refreshPedidos();
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(ctx)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Pedido atualizado!')));
                                        }
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Erro ao salvar: $e')));
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.save_rounded),
                                    label: const Text('Salvar alterações'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _abrirFormulario() {
    final textoCtrl = TextEditingController();
    String categoria = 'Outro';
    String visibilidade = 'publico';
    List<String> destinatariosEmails = [];
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: _prayerSheetDecoration,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.92,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ThemeCleanPremium.radiusLg)),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary.withValues(alpha: 0.45),
                        ThemeCleanPremium.primaryLight.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: ThemeCleanPremium.spaceLg,
                      right: ThemeCleanPremium.spaceLg,
                      top: ThemeCleanPremium.spaceMd,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom +
                          ThemeCleanPremium.spaceLg,
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Novo Pedido de Oração',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: TextButton.styleFrom(
                                  foregroundColor: ThemeCleanPremium.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: ThemeCleanPremium.spaceSm,
                                    vertical: ThemeCleanPremium.spaceXs,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          TextFormField(
                            controller: textoCtrl,
                            maxLines: 4,
                            maxLength: 500,
                            decoration: const InputDecoration(
                              labelText: 'Seu pedido de oração',
                              hintText: 'Compartilhe aqui seu pedido...',
                              alignLabelWithHint: true,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Informe o pedido'
                                : null,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Text('Categoria',
                              style: Theme.of(ctx).textTheme.titleSmall),
                          const SizedBox(height: ThemeCleanPremium.spaceXs),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _categoriasForm
                                .map(
                                  (c) => _buildPrayerCategoriaChip(
                                    cat: c,
                                    selectedCat: categoria,
                                    onSelect: (v) =>
                                        setLocal(() => categoria = v),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Text('Quem pode ver',
                              style: Theme.of(ctx).textTheme.titleSmall),
                          const SizedBox(height: ThemeCleanPremium.spaceXs),
                          ...['publico', 'lideres', 'membros'].map(
                              (v) => RadioListTile<String>(
                                    title: Text(v == 'publico'
                                        ? 'Público (todos os membros)'
                                        : v == 'lideres'
                                            ? 'Apenas líderes'
                                            : 'Membros selecionados'),
                                    value: v,
                                    groupValue: visibilidade,
                                    onChanged: (val) => setLocal(() =>
                                        visibilidade = val ?? visibilidade),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                  )),
                          if (visibilidade == 'membros') ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await _abrirSeletorMembros(
                                    ctx, widget.tenantId, destinatariosEmails);
                                if (ctx.mounted && picked != null) {
                                  setLocal(() => destinatariosEmails = picked);
                                }
                              },
                              icon: const Icon(Icons.people_rounded, size: 20),
                              label: Text(destinatariosEmails.isEmpty
                                  ? 'Selecionar membros'
                                  : '${destinatariosEmails.length} membro(s) selecionado(s)'),
                            ),
                          ],
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: ThemeCleanPremium.minTouchTarget,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: ThemeCleanPremium.primary,
                                      side: BorderSide(
                                        color: ThemeCleanPremium.primary
                                            .withValues(alpha: 0.55),
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancelar'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: ThemeCleanPremium.spaceSm),
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: ThemeCleanPremium.minTouchTarget,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: ThemeCleanPremium.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    onPressed: () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }
                                      final user = _currentUser;
                                      if (user == null) {
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Faça login para enviar.')));
                                        }
                                        return;
                                      }
                                      if (visibilidade == 'membros' &&
                                          destinatariosEmails.isEmpty) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'Selecione pelo menos um membro.')));
                                        return;
                                      }
                                      final publico =
                                          visibilidade == 'publico';
                                      final dest = visibilidade == 'membros'
                                          ? destinatariosEmails
                                          : <String>[];
                                      try {
                                        await FirebaseAuth.instance.currentUser
                                            ?.getIdToken(true);
                                        await _col.add({
                                          'texto': textoCtrl.text.trim(),
                                          'categoria': categoria,
                                          'publico': publico,
                                          'destinatariosEmails': dest,
                                          'autorNome': user.displayName ??
                                              user.email ??
                                              'Membro',
                                          'autorUid': user.uid,
                                          'createdAt':
                                              FieldValue.serverTimestamp(),
                                          'orandoCount': 0,
                                          'orandoUids': <String>[],
                                          'respondida': false,
                                        });
                                        if (ctx.mounted) {
                                          _refreshPedidos();
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                    'Pedido enviado com sucesso!',
                                                    style: TextStyle(
                                                        color: Colors.white),
                                                  ),
                                                  backgroundColor:
                                                      Colors.green));
                                        }
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Erro ao enviar: $e')));
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.send_rounded),
                                    label: const Text('Enviar Pedido'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Abre bottom sheet para selecionar membros; retorna lista de emails ou null se cancelar.
  Future<List<String>?> _abrirSeletorMembros(BuildContext context, String tenantId, List<String> selecionadosIniciais) async {
    if (!mounted) return null;
    final selected = List<String>.from(selecionadosIniciais);
    var searchQuery = '';
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return FutureBuilder<List<Map<String, String>>>(
            future: _loadMembrosParaSelecao(tenantId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                    minHeight: 220,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(ThemeCleanPremium.radiusLg)),
                  ),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Carregando membros da igreja…'),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (snap.hasError) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(ThemeCleanPremium.radiusLg)),
                  ),
                  child: Text(
                    'Não foi possível carregar membros: ${snap.error}',
                    style: TextStyle(color: ThemeCleanPremium.error),
                  ),
                );
              }
              final members = snap.data ?? [];
              final q = searchQuery.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? members
                  : members.where((m) {
                      final nome = (m['nome'] ?? '').toString().toLowerCase();
                      final email = (m['email'] ?? '').toString().toLowerCase();
                      return nome.contains(q) || email.contains(q);
                    }).toList();

              return Container(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(ThemeCleanPremium.radiusLg)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ThemeCleanPremium.spaceSm,
                        ThemeCleanPremium.spaceMd,
                        ThemeCleanPremium.spaceMd,
                        ThemeCleanPremium.spaceSm,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            tooltip: 'Voltar',
                            onPressed: () => Navigator.pop(ctx, null),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(
                                  ThemeCleanPremium.minTouchTarget,
                                  ThemeCleanPremium.minTouchTarget),
                            ),
                          ),
                          Expanded(
                            child: Text('Selecionar membros',
                                style: Theme.of(ctx).textTheme.titleMedium),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, selected),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ThemeCleanPremium.spaceMd,
                        0,
                        ThemeCleanPremium.spaceMd,
                        ThemeCleanPremium.spaceSm,
                      ),
                      child: TextField(
                        onChanged: (v) => setLocal(() => searchQuery = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Buscar por nome ou e-mail',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                      ),
                    ),
                    if (members.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          ThemeCleanPremium.spaceMd,
                          0,
                          ThemeCleanPremium.spaceMd,
                          4,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${members.length} membro(s) na lista',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  q.isEmpty
                                      ? 'Nenhum membro encontrado.'
                                      : 'Nenhum resultado para a busca.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final m = filtered[i];
                                final email = (m['email'] ?? '').trim();
                                final docId = (m['docId'] ?? '').trim();
                                final nomeRaw = (m['nome'] ?? '').toString().trim();
                                final nome = nomeRaw.isNotEmpty
                                    ? nomeRaw
                                    : (email.isNotEmpty ? email : docId);
                                final canSelect = email.isNotEmpty;
                                final isSelected = canSelect &&
                                    selected.any((e) =>
                                        e.trim().toLowerCase() ==
                                        email.toLowerCase());
                                return CheckboxListTile(
                                  title: Text(nome,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (email.isNotEmpty)
                                        Text(
                                          email,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600),
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      else
                                        Text(
                                          'Sem e-mail na ficha — cadastre na área Membros para poder selecionar.',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange.shade800,
                                          ),
                                        ),
                                    ],
                                  ),
                                  value: isSelected,
                                  onChanged: !canSelect
                                      ? null
                                      : (v) {
                                          setLocal(() {
                                            if (v == true) {
                                              if (!selected.any((e) =>
                                                  e.trim().toLowerCase() ==
                                                  email.toLowerCase())) {
                                                selected.add(email);
                                              }
                                            } else {
                                              selected.removeWhere((e) =>
                                                  e.trim().toLowerCase() ==
                                                  email.toLowerCase());
                                            }
                                          });
                                        },
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Carrega todos os membros do tenant (`membros` paginado + legado `members`).
  Future<List<Map<String, String>>> _loadMembrosParaSelecao(String tenantId) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final effective =
        await TenantResolverService.resolveEffectiveTenantId(tenantId.trim());
    final id = effective.trim().isNotEmpty ? effective : tenantId.trim();
    if (id.isEmpty) return [];

    final db = FirebaseFirestore.instance;
    final churchRef = db.collection('igrejas').doc(id);

    final membrosDocs = await _paginateSubcollection(churchRef, 'membros');
    final legacyDocs = await _paginateSubcollection(churchRef, 'members');

    final seenDocIds = <String>{};
    final seenEmails = <String>{};
    final out = <Map<String, String>>[];

    void addDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      if (!seenDocIds.add(d.id)) return;
      final data = d.data();
      final email = _emailFromMemberData(data);
      final nome = (data['NOME_COMPLETO'] ??
              data['nome'] ??
              data['name'] ??
              (email.isNotEmpty ? email : d.id))
          .toString()
          .trim();
      if (email.isNotEmpty) {
        final ek = email.toLowerCase();
        if (seenEmails.contains(ek)) return;
        seenEmails.add(ek);
        out.add({'email': email, 'nome': nome, 'docId': d.id});
      } else {
        out.add({'email': '', 'nome': nome, 'docId': d.id});
      }
    }

    for (final d in membrosDocs) {
      addDoc(d);
    }
    for (final d in legacyDocs) {
      addDoc(d);
    }

    out.sort((a, b) {
      final an = (a['nome'] ?? '').toLowerCase();
      final bn = (b['nome'] ?? '').toLowerCase();
      final c = an.compareTo(bn);
      if (c != 0) return c;
      return (a['email'] ?? '').compareTo(b['email'] ?? '');
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);

    final showAppBar = !isMobile || Navigator.canPop(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: !showAppBar
          ? null
          : AppBar(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                    )
                  : null,
              title: const Text('Pedidos de Oração'),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Pedir Oração'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: SafeArea(
          top: !widget.embeddedInShell,
          child: Column(
            children: [
            if (isMobile && !widget.embeddedInShell)
              Padding(
                padding: EdgeInsets.only(
                  left: padding.left,
                  right: padding.right,
                  top: padding.top,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.volunteer_activism_rounded,
                        color: ThemeCleanPremium.primary, size: 28),
                    const SizedBox(width: ThemeCleanPremium.spaceSm),
                    Text('Pedidos de Oração',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                                color: ThemeCleanPremium.onSurface,
                                fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: padding.left,
                  vertical: ThemeCleanPremium.spaceSm),
              child: SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filtrosStatus.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: ThemeCleanPremium.spaceXs),
                  itemBuilder: (_, i) {
                    final s = _filtrosStatus[i];
                    final sel = _filtroStatus == s;
                    return FilterChip(
                      label: Text(s,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w500,
                            color: sel
                                ? Colors.white
                                : ThemeCleanPremium.onSurfaceVariant,
                          )),
                      selected: sel,
                      selectedColor: ThemeCleanPremium.primary,
                      backgroundColor: ThemeCleanPremium.cardBackground,
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                        side: BorderSide(
                          color: sel
                              ? ThemeCleanPremium.primary
                              : Colors.grey.shade300,
                        ),
                      ),
                      onSelected: (_) {
                        setState(() => _filtroStatus = s);
                        _refreshPedidos();
                      },
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _pedidosFuture,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: ThemeCleanPremium.pagePadding(context),
                      child: ChurchPanelErrorBody(
                        title: 'Não foi possível carregar os pedidos de oração',
                        error: snap.error,
                        onRetry: _refreshPedidos,
                      ),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const ChurchPanelLoadingBody();
                  }

                  final docs = snap.data?.docs ?? [];
                  final visibleDocs =
                      docs.where((d) => _canSee(d.data())).toList();

                  if (visibleDocs.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    padding: EdgeInsets.only(
                      left: padding.left,
                      right: padding.right,
                      bottom: 80,
                      top: ThemeCleanPremium.spaceXs,
                    ),
                    itemCount: visibleDocs.length,
                    itemBuilder: (_, i) =>
                        _buildCard(visibleDocs[i]),
                  );
                },
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.volunteer_activism_rounded,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Text('Nenhum pedido ainda',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500)),
          const SizedBox(height: ThemeCleanPremium.spaceXs),
          Text('Seja o primeiro a compartilhar um pedido de oração',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final nome = data['autorNome'] ?? 'Membro';
    final texto = data['texto'] ?? '';
    final categoria = data['categoria'] ?? 'Outro';
    final publico = data['publico'] ?? true;
    final respondida = data['respondida'] ?? false;
    final orandoUids = List<String>.from(data['orandoUids'] ?? []);
    final orandoCount = data['orandoCount'] ?? orandoUids.length;
    final ts = data['createdAt'] as Timestamp?;
    final uid = _currentUser?.uid;
    final isOrando = uid != null && orandoUids.contains(uid);

    final catBg = _categoriaCores[categoria] ?? Colors.grey.shade100;
    final catFg = _categoriaTexto[categoria] ?? Colors.grey.shade700;

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: ThemeCleanPremium.primaryLight.withAlpha(40),
                  child: Text(
                    nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ThemeCleanPremium.primary,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      if (ts != null)
                        Text(_timeAgo(ts),
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                if (_canManage(data))
                  PopupMenuButton<String>(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: ThemeCleanPremium.minTouchTarget,
                        minHeight: ThemeCleanPremium.minTouchTarget),
                    onSelected: (v) {
                      if (v == 'editar') _abrirFormularioEdicao(doc);
                      if (v == 'respondida') _marcarRespondida(doc.id);
                      if (v == 'excluir') _deletar(doc.id);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined,
                                size: 18, color: ThemeCleanPremium.primary),
                            SizedBox(width: 8),
                            Text('Editar'),
                          ],
                        ),
                      ),
                      if (!respondida)
                        const PopupMenuItem(
                          value: 'respondida',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  size: 18, color: ThemeCleanPremium.success),
                              SizedBox(width: 8),
                              Text('Marcar respondida'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: ThemeCleanPremium.error),
                            SizedBox(width: 8),
                            Text('Excluir',
                                style:
                                    TextStyle(color: ThemeCleanPremium.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            Text(texto,
                style: const TextStyle(fontSize: 15, height: 1.5)),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            Wrap(
              spacing: ThemeCleanPremium.spaceXs,
              runSpacing: ThemeCleanPremium.spaceXs,
              children: [
                _badge(categoria, catBg, catFg),
                if (!publico && data['destinatariosEmails'] is List && (data['destinatariosEmails'] as List).isNotEmpty)
                  _badge('Membros selecionados', const Color(0xFFE3F2FD),
                      const Color(0xFF1565C0),
                      icon: Icons.people_outline_rounded),
                if (!publico && (data['destinatariosEmails'] is! List || (data['destinatariosEmails'] as List).isEmpty))
                  _badge('Apenas líderes', const Color(0xFFFFF3E0),
                      const Color(0xFFE65100),
                      icon: Icons.lock_outline_rounded),
                if (respondida)
                  _badge('Respondida!', const Color(0xFFE8F5E9),
                      ThemeCleanPremium.success,
                      icon: Icons.check_circle_rounded),
              ],
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            const Divider(height: 1),
            const SizedBox(height: ThemeCleanPremium.spaceXs),
            _OrandoButton(
              isOrando: isOrando,
              count: orandoCount is int ? orandoCount : 0,
              onTap: () => _toggleOrando(doc.id, orandoUids),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class _OrandoButton extends StatefulWidget {
  final bool isOrando;
  final int count;
  final VoidCallback onTap;
  const _OrandoButton(
      {required this.isOrando, required this.count, required this.onTap});

  @override
  State<_OrandoButton> createState() => _OrandoButtonState();
}

class _OrandoButtonState extends State<_OrandoButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween(begin: 1.0, end: 1.25).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
      onTap: _onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: ThemeCleanPremium.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ThemeCleanPremium.spaceSm,
              vertical: ThemeCleanPremium.spaceXs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Icon(
                  Icons.volunteer_activism_rounded,
                  size: 20,
                  color: widget.isOrando
                      ? ThemeCleanPremium.primary
                      : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.isOrando ? 'Orando' : 'Estou orando',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isOrando ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isOrando
                      ? ThemeCleanPremium.primary
                      : Colors.grey.shade600,
                ),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.isOrando
                        ? ThemeCleanPremium.primaryLight.withAlpha(30)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${widget.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: widget.isOrando
                            ? ThemeCleanPremium.primary
                            : Colors.grey.shade600,
                      )),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
