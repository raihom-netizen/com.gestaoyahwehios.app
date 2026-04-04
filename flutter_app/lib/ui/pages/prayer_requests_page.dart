import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

class PrayerRequestsPage extends StatefulWidget {
  final String tenantId;
  final String role;
  const PrayerRequestsPage(
      {super.key, required this.tenantId, required this.role});

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
    'Saúde': Color(0xFF2E7D32),
    'Família': Color(0xFFE65100),
    'Finanças': Color(0xFF1565C0),
    'Trabalho': Color(0xFF6A1B9A),
    'Libertação': Color(0xFFC62828),
    'Gratidão': Color(0xFFF9A825),
    'Outro': Color(0xFF616161),
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(ThemeCleanPremium.radiusLg)),
          ),
          padding: EdgeInsets.only(
            left: ThemeCleanPremium.spaceLg,
            right: ThemeCleanPremium.spaceLg,
            top: ThemeCleanPremium.spaceLg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                ThemeCleanPremium.spaceLg,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
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
                  Text('Editar Pedido de Oração',
                      style: Theme.of(ctx).textTheme.titleLarge),
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
                    spacing: ThemeCleanPremium.spaceXs,
                    runSpacing: ThemeCleanPremium.spaceXs,
                    children: _categoriasForm
                        .map((c) => ChoiceChip(
                              label: Text(c),
                              selected: categoria == c,
                              selectedColor:
                                  _categoriaCores[c] ?? Colors.grey.shade200,
                              onSelected: (_) =>
                                  setLocal(() => categoria = c),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Text('Quem pode ver',
                      style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: ThemeCleanPremium.spaceXs),
                  ...['publico', 'lideres', 'membros'].map((v) => RadioListTile<String>(
                    title: Text(v == 'publico' ? 'Público (todos os membros)' : v == 'lideres' ? 'Apenas líderes' : 'Membros selecionados'),
                    value: v,
                    groupValue: visibilidade,
                    onChanged: (val) => setLocal(() => visibilidade = val ?? visibilidade),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                  if (visibilidade == 'membros') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _abrirSeletorMembros(ctx, widget.tenantId, destinatariosEmails);
                        if (ctx.mounted && picked != null) setLocal(() => destinatariosEmails = picked);
                      },
                      icon: const Icon(Icons.people_rounded, size: 20),
                      label: Text(destinatariosEmails.isEmpty ? 'Selecionar membros' : '${destinatariosEmails.length} membro(s) selecionado(s)'),
                    ),
                  ],
                  const SizedBox(height: ThemeCleanPremium.spaceLg),
                  SizedBox(
                    width: double.infinity,
                    height: ThemeCleanPremium.minTouchTarget,
                    child: FilledButton.icon(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final pub = visibilidade == 'publico';
                        final dest = visibilidade == 'membros' ? destinatariosEmails : <String>[];
                        if (visibilidade == 'membros' && dest.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Selecione pelo menos um membro.')));
                          return;
                        }
                        try {
                          await FirebaseAuth.instance.currentUser?.getIdToken(true);
                          await _col.doc(doc.id).update({
                            'texto': textoCtrl.text.trim(),
                            'categoria': categoria,
                            'publico': pub,
                            'destinatariosEmails': dest,
                          });
                          if (ctx.mounted) {
                            _refreshPedidos();
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Pedido atualizado!')));
                          }
                        } catch (e) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
                        }
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Salvar alterações'),
                    ),
                  ),
                ],
              ),
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(ThemeCleanPremium.radiusLg)),
          ),
          padding: EdgeInsets.only(
            left: ThemeCleanPremium.spaceLg,
            right: ThemeCleanPremium.spaceLg,
            top: ThemeCleanPremium.spaceLg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                ThemeCleanPremium.spaceLg,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
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
                  Text('Novo Pedido de Oração',
                      style: Theme.of(ctx).textTheme.titleLarge),
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
                    spacing: ThemeCleanPremium.spaceXs,
                    runSpacing: ThemeCleanPremium.spaceXs,
                    children: _categoriasForm
                        .map((c) => ChoiceChip(
                              label: Text(c),
                              selected: categoria == c,
                              selectedColor:
                                  _categoriaCores[c] ?? Colors.grey.shade200,
                              onSelected: (_) =>
                                  setLocal(() => categoria = c),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Text('Quem pode ver',
                      style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: ThemeCleanPremium.spaceXs),
                  ...['publico', 'lideres', 'membros'].map((v) => RadioListTile<String>(
                    title: Text(v == 'publico' ? 'Público (todos os membros)' : v == 'lideres' ? 'Apenas líderes' : 'Membros selecionados'),
                    value: v,
                    groupValue: visibilidade,
                    onChanged: (val) => setLocal(() => visibilidade = val ?? visibilidade),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                  if (visibilidade == 'membros') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _abrirSeletorMembros(ctx, widget.tenantId, destinatariosEmails);
                        if (ctx.mounted && picked != null) setLocal(() => destinatariosEmails = picked);
                      },
                      icon: const Icon(Icons.people_rounded, size: 20),
                      label: Text(destinatariosEmails.isEmpty ? 'Selecionar membros' : '${destinatariosEmails.length} membro(s) selecionado(s)'),
                    ),
                  ],
                  const SizedBox(height: ThemeCleanPremium.spaceLg),
                  SizedBox(
                    width: double.infinity,
                    height: ThemeCleanPremium.minTouchTarget,
                    child: FilledButton.icon(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final user = _currentUser;
                        if (user == null) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Faça login para enviar.')));
                          return;
                        }
                        if (visibilidade == 'membros' && destinatariosEmails.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Selecione pelo menos um membro.')));
                          return;
                        }
                        final publico = visibilidade == 'publico';
                        final dest = visibilidade == 'membros' ? destinatariosEmails : <String>[];
                        try {
                          await FirebaseAuth.instance.currentUser?.getIdToken(true);
                          await _col.add({
                            'texto': textoCtrl.text.trim(),
                            'categoria': categoria,
                            'publico': publico,
                            'destinatariosEmails': dest,
                            'autorNome':
                                user.displayName ?? user.email ?? 'Membro',
                            'autorUid': user.uid,
                            'createdAt': FieldValue.serverTimestamp(),
                            'orandoCount': 0,
                            'orandoUids': <String>[],
                            'respondida': false,
                          });
                          if (ctx.mounted) {
                            _refreshPedidos();
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Pedido enviado com sucesso!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
                        }
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Enviar Pedido'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Abre bottom sheet para selecionar membros; retorna lista de emails ou null se cancelar.
  Future<List<String>?> _abrirSeletorMembros(BuildContext context, String tenantId, List<String> selecionadosIniciais) async {
    final members = await _loadMembrosParaSelecao(tenantId);
    List<String> selected = List.from(selecionadosIniciais);
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusLg)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                child: Row(
                  children: [
                    Text('Selecionar membros', style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final m = members[i];
                    final email = m['email'] ?? '';
                    final nome = m['nome'] ?? email;
                    final isSelected = selected.any((e) => e.trim().toLowerCase() == email.trim().toLowerCase());
                    return CheckboxListTile(
                      title: Text(nome, overflow: TextOverflow.ellipsis),
                      subtitle: email.isNotEmpty ? Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis) : null,
                      value: isSelected,
                      onChanged: (v) {
                        setLocal(() {
                          if (v == true) {
                            if (!selected.any((e) => e.trim().toLowerCase() == email.trim().toLowerCase())) selected.add(email);
                          } else {
                            selected.removeWhere((e) => e.trim().toLowerCase() == email.trim().toLowerCase());
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
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

  /// Carrega lista de membros (nome + email) do tenant para o seletor.
  Future<List<Map<String, String>>> _loadMembrosParaSelecao(String tenantId) async {
    final seen = <String>{};
    final out = <Map<String, String>>[];
    final col = FirebaseFirestore.instance.collection('igrejas').doc(tenantId);
    final igreja = FirebaseFirestore.instance.collection('igrejas').doc(tenantId);
    final sources = [
      col.collection('membros').limit(500).get(),
      col.collection('membros').limit(500).get(),
      igreja.collection('membros').limit(500).get(),
      igreja.collection('membros').limit(500).get(),
    ];
    final snaps = await Future.wait(sources);
    for (final snap in snaps) {
      for (final d in snap.docs) {
        final data = d.data();
        final email = (data['EMAIL'] ?? data['email'] ?? '').toString().trim();
        if (email.isEmpty) continue;
        final key = email.toLowerCase();
        if (seen.contains(key)) continue;
        seen.add(key);
        final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? email).toString().trim();
        out.add({'email': email, 'nome': nome});
      }
    }
    out.sort((a, b) => (a['nome'] ?? '').compareTo(b['nome'] ?? ''));
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
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
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
