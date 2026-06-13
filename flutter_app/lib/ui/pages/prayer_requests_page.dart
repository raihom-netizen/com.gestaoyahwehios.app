import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/church_pedidos_oracao_load_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

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

/// Cores premium — Pedidos de Oração (rosa / violeta / coral).
abstract final class _PrayerPremiumTheme {
  _PrayerPremiumTheme._();

  static const rose = Color(0xFFEC4899);
  static const violet = Color(0xFF8B5CF6);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFFF472B6)],
  );

  static LinearGradient cardGradient(String categoria) {
    final accent = _PrayerRequestsPageState.categoriaAccent(categoria);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        accent.withValues(alpha: 0.16),
        accent.withValues(alpha: 0.04),
      ],
    );
  }
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
  String _effectiveTenantId = '';

  String get _tid => ChurchPanelTenant.resolve(
        _effectiveTenantId.isNotEmpty
            ? _effectiveTenantId
            : widget.tenantId,
      );

  String get _churchId => ChurchRepository.churchId(_tid);

  bool? _respondidaFilterFromStatus() {
    if (_filtroStatus == 'Respondidas') return true;
    if (_filtroStatus == 'Não Respondidas') return false;
    return null;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadPedidos({
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final tid = _tid.trim();
    if (tid.isEmpty) {
      return const MergedFirestoreQuerySnapshot([]);
    }
    final result = await ChurchPedidosOracaoLoadService.load(
      seedTenantId: tid,
      respondidaFilter: _respondidaFilterFromStatus(),
      forceRefresh: forceRefresh,
      forceServer: forceServer,
    );
    return result.snapshot;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _seedOrLoadPedidos() {
    final tid = _tid.trim();
    if (tid.isEmpty) {
      return Future.value(const MergedFirestoreQuerySnapshot([]));
    }

    final ram = ChurchPedidosOracaoLoadService.peekRam(
      tid,
      respondidaFilter: _respondidaFilterFromStatus(),
    );
    if (ram != null && ram.isNotEmpty) {
      return Future.value(MergedFirestoreQuerySnapshot(ram));
    }

    final memKey = ChurchPedidosOracaoLoadService.cacheKey(
      tid,
      _respondidaFilterFromStatus(),
      ChurchPedidosOracaoLoadService.kDefaultLimit,
    );
    final mem = FirestoreReadResilience.peekLastGoodQuery(memKey);
    if (mem != null && mem.docs.isNotEmpty) {
      return Future.value(mem);
    }

    return _loadPedidos();
  }

  Future<void> _openPedidosFast() async {
    final tid = _tid.trim();
    if (tid.isEmpty) return;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final snap = await _loadPedidos(forceRefresh: true);
      if (!mounted) return;
      setState(() => _pedidosFuture = Future.value(snap));
    } catch (_) {}
  }

  void _refreshPedidos({bool forceRefresh = false}) {
    setState(() {
      _pedidosFuture = _loadPedidos(
        forceRefresh: forceRefresh,
        forceServer: forceRefresh,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _effectiveTenantId = ChurchPanelTenant.resolve(widget.tenantId).trim();
    _pedidosFuture = _seedOrLoadPedidos();
    unawaited(_openPedidosFast());
  }

  @override
  void didUpdateWidget(covariant PrayerRequestsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _effectiveTenantId = ChurchPanelTenant.resolve(widget.tenantId).trim();
      _pedidosFuture = _seedOrLoadPedidos();
      unawaited(_openPedidosFast());
    }
  }

  static const _filtrosStatus = ['Todos', 'Não Respondidas', 'Respondidas'];

  static const _categoriasForm = [
    'Saúde', 'Família', 'Finanças', 'Trabalho', 'Libertação', 'Gratidão', 'Outro',
  ];

  static Color categoriaAccent(String categoria) {
    return _categoriaTexto[categoria] ?? _PrayerPremiumTheme.rose;
  }

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

  CollectionReference<Map<String, dynamic>> get _col =>
      ChurchUiCollections.pedidosOracao(_churchId);

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
      if (emails.any((e) =>
          e.toString().trim().toLowerCase() ==
          _currentUser!.email!.trim().toLowerCase())) {
        return true;
      }
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
    final removing = orandoUids.contains(uid);
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.runWithWebRecovery(
          () async {
            if (removing) {
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
          },
          maxAttempts: 4,
        );
      } else if (removing) {
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
      if (mounted) {
        unawaited(ChurchPedidosOracaoLoadService.invalidate(_tid));
        _refreshPedidos(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar: $e')),
        );
      }
    }
  }

  Future<void> _marcarRespondida(String docId) async {
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.runWithWebRecovery(
          () => _col.doc(docId).update({'respondida': true}),
          maxAttempts: 4,
        );
      } else {
        await _col.doc(docId).update({'respondida': true});
      }
      if (mounted) {
        unawaited(ChurchPedidosOracaoLoadService.invalidate(_tid));
        _refreshPedidos(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
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
        if (kIsWeb) {
          await FirestoreWebGuard.runWithWebRecovery(
            () => _col.doc(docId).delete(),
            maxAttempts: 4,
          );
        } else {
          await _col.doc(docId).delete();
        }
        if (mounted) {
          unawaited(ChurchPedidosOracaoLoadService.invalidate(_tid));
          _refreshPedidos(forceRefresh: true);
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
                                        Future<void> save() => _col.doc(doc.id).update({
                                          'texto': textoCtrl.text.trim(),
                                          'categoria': categoria,
                                          'publico': pub,
                                          'destinatariosEmails': dest,
                                        });
                                        if (kIsWeb) {
                                          await FirestoreWebGuard.runWithWebRecovery(
                                            save,
                                            maxAttempts: 4,
                                          );
                                        } else {
                                          await save();
                                        }
                                        if (ctx.mounted) {
                                          unawaited(ChurchPedidosOracaoLoadService.invalidate(_tid));
                                          _refreshPedidos(forceRefresh: true);
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
                                        Future<void> save() => _col.add({
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
                                        if (kIsWeb) {
                                          await FirestoreWebGuard.runWithWebRecovery(
                                            save,
                                            maxAttempts: 4,
                                          );
                                        } else {
                                          await save();
                                        }
                                        if (ctx.mounted) {
                                          unawaited(ChurchPedidosOracaoLoadService.invalidate(_tid));
                                          _refreshPedidos(forceRefresh: true);
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

  /// Membros para selecionar destinatários (e-mail) — via [ChurchRepository].
  Future<List<Map<String, String>>> _loadMembrosParaSelecao(String tenantId) async {
    final id = ChurchRepository.churchId(tenantId.trim());
    if (id.isEmpty) return [];

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final result = await ChurchRepository.membros.list(
      churchIdHint: id,
      limit: 500,
    );
    final docs = result.items;

    final seenDocIds = <String>{};
    final seenEmails = <String>{};
    final out = <Map<String, String>>[];

    for (final d in docs) {
      if (!seenDocIds.add(d.id)) continue;
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
        if (seenEmails.contains(ek)) continue;
        seenEmails.add(ek);
        out.add({'email': email, 'nome': nome, 'docId': d.id});
      } else {
        out.add({'email': '', 'nome': nome, 'docId': d.id});
      }
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
    final tt = Theme.of(context).textTheme;

    final showAppBar = !isMobile || Navigator.canPop(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: !showAppBar
          ? null
          : AppBar(
              backgroundColor: _PrayerPremiumTheme.rose,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget,
                        ),
                      ),
                    )
                  : null,
              title: const Text('Pedidos de Oração'),
            ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _PrayerPremiumTheme.heroGradient,
          boxShadow: [
            BoxShadow(
              color: _PrayerPremiumTheme.rose.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _abrirFormulario,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Pedir Oração',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDF2F8), Color(0xFFF8FAFC)],
          ),
        ),
        child: SafeArea(
          top: !widget.embeddedInShell,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ResilientPanelQueryFutureBuilder(
                  future: _pedidosFuture,
                  errorTitle: 'Não foi possível carregar os pedidos de oração',
                  onRetry: () => _refreshPedidos(forceRefresh: true),
                  builder: (context, snap, {required bool showingStaleCache}) {
                    final docs = snap.docs;
                    final visibleDocs =
                        docs.where((d) => _canSee(d.data())).toList();
                    final pendentes = visibleDocs
                        .where((d) => d.data()['respondida'] != true)
                        .length;
                    final respondidas = visibleDocs.length - pendentes;
                    var orandoTotal = 0;
                    for (final d in visibleDocs) {
                      final c = d.data()['orandoCount'];
                      orandoTotal += c is int ? c : 0;
                    }

                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              padding.left,
                              padding.top,
                              padding.right,
                              8,
                            ),
                            child: _PrayerHeroHeader(
                              total: visibleDocs.length,
                              pendentes: pendentes,
                              respondidas: respondidas,
                              orandoTotal: orandoTotal,
                            ),
                          ),
                        ),
                        if (showingStaleCache)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: ChurchPanelOfflineStaleBanner(
                                message:
                                    'Modo offline — últimos pedidos guardados.',
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: padding.left,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                for (var i = 0; i < _filtrosStatus.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 8),
                                  Expanded(
                                    child: _PrayerFilterChip(
                                      label: _filtrosStatus[i],
                                      selected: _filtroStatus == _filtrosStatus[i],
                                      onTap: () {
                                        setState(() {
                                          _filtroStatus = _filtrosStatus[i];
                                          _pedidosFuture = _seedOrLoadPedidos();
                                        });
                                        unawaited(_openPedidosFast());
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (visibleDocs.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyState(tt),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.only(
                              left: padding.left,
                              right: padding.right,
                              bottom: 96,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) =>
                                    _buildCard(visibleDocs[i]),
                                childCount: visibleDocs.length,
                              ),
                            ),
                          ),
                      ],
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

  Widget _buildEmptyState(TextTheme tt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _PrayerPremiumTheme.rose.withValues(alpha: 0.18),
                    _PrayerPremiumTheme.violet.withValues(alpha: 0.1),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _PrayerPremiumTheme.rose.withValues(alpha: 0.22),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.volunteer_activism_rounded,
                size: 56,
                color: _PrayerPremiumTheme.rose,
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Text(
              _filtroStatus == 'Todos'
                  ? 'Nenhum pedido ainda'
                  : 'Nenhum pedido neste filtro',
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceXs),
            Text(
              'Compartilhe um pedido — a igreja ora junto com você',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            FilledButton.icon(
              onPressed: _abrirFormulario,
              style: FilledButton.styleFrom(
                backgroundColor: _PrayerPremiumTheme.rose,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Pedir Oração',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final nome = (data['autorNome'] ?? 'Membro').toString();
    final texto = (data['texto'] ?? '').toString();
    final categoria = (data['categoria'] ?? 'Outro').toString();
    final publico = data['publico'] ?? true;
    final respondida = data['respondida'] ?? false;
    final orandoUids = List<String>.from(data['orandoUids'] ?? []);
    final orandoCount = data['orandoCount'] ?? orandoUids.length;
    final ts = data['createdAt'] as Timestamp?;
    final uid = _currentUser?.uid;
    final isOrando = uid != null && orandoUids.contains(uid);

    final catFg = categoriaAccent(categoria);
    final catBg = _categoriaCores[categoria] ?? const Color(0xFFF1F5F9);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: respondida
              ? const Color(0xFF86EFAC).withValues(alpha: 0.6)
              : catFg.withValues(alpha: 0.18),
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _PrayerPremiumTheme.cardGradient(categoria),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [catFg, catFg.withValues(alpha: 0.65)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: catFg.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (ts != null)
                            Text(
                              _timeAgo(ts),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_canManage(data))
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz_rounded,
                            color: Colors.grey.shade600),
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
                                    size: 18, color: _PrayerPremiumTheme.violet),
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
                                      size: 18, color: Color(0xFF16A34A)),
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
                                    style: TextStyle(
                                        color: ThemeCleanPremium.error)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _badge(categoria, catBg, catFg),
                    if (!publico &&
                        data['destinatariosEmails'] is List &&
                        (data['destinatariosEmails'] as List).isNotEmpty)
                      _badge(
                        'Membros selecionados',
                        const Color(0xFFDBEAFE),
                        const Color(0xFF1D4ED8),
                        icon: Icons.people_outline_rounded,
                      ),
                    if (!publico &&
                        (data['destinatariosEmails'] is! List ||
                            (data['destinatariosEmails'] as List).isEmpty))
                      _badge(
                        'Apenas líderes',
                        const Color(0xFFFFEDD5),
                        const Color(0xFFEA580C),
                        icon: Icons.lock_outline_rounded,
                      ),
                    if (respondida)
                      _badge(
                        'Respondida',
                        const Color(0xFFDCFCE7),
                        const Color(0xFF15803D),
                        icon: Icons.check_circle_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 6),
                _OrandoButton(
                  isOrando: isOrando,
                  count: orandoCount is int ? orandoCount : 0,
                  onTap: () => _toggleOrando(doc.id, orandoUids),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrayerHeroHeader extends StatelessWidget {
  const _PrayerHeroHeader({
    required this.total,
    required this.pendentes,
    required this.respondidas,
    required this.orandoTotal,
  });

  final int total;
  final int pendentes;
  final int respondidas;
  final int orandoTotal;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        gradient: _PrayerPremiumTheme.heroGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _PrayerPremiumTheme.rose.withValues(alpha: 0.38),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedidos de Oração',
                      style: tt.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Oremos juntos — compartilhe e interceda',
                      style: tt.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$total',
                style: tt.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PrayerStatPill(label: 'Pendentes', value: pendentes),
              const SizedBox(width: 8),
              _PrayerStatPill(label: 'Respondidas', value: respondidas),
              const SizedBox(width: 8),
              _PrayerStatPill(label: 'Orando', value: orandoTotal),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrayerStatPill extends StatelessWidget {
  const _PrayerStatPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrayerFilterChip extends StatelessWidget {
  const _PrayerFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected ? _PrayerPremiumTheme.heroGradient : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _PrayerPremiumTheme.rose.withValues(alpha: 0.5)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _PrayerPremiumTheme.rose.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Center(
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF475569),
                height: 1.15,
              ),
            ),
          ),
        ),
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
                      ? _PrayerPremiumTheme.rose
                      : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.isOrando ? 'Orando' : 'Estou orando',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isOrando ? FontWeight.w800 : FontWeight.w600,
                  color: widget.isOrando
                      ? _PrayerPremiumTheme.rose
                      : Colors.grey.shade600,
                ),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _PrayerPremiumTheme.rose.withValues(alpha: 0.2),
                        _PrayerPremiumTheme.violet.withValues(alpha: 0.14),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _PrayerPremiumTheme.rose,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
