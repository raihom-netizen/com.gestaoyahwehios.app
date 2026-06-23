import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/prayer_orando_membros_denorm.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_pedidos_oracao_load_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/prayer_analytics_panel.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

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

class _PrayerRequestsPageState extends State<PrayerRequestsPage>
    with SingleTickerProviderStateMixin {
  /// Filtro por status: Todos | Respondidas | Não Respondidas
  String _filtroStatus = 'Todos';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pedidosDocs = const [];
  bool _fetching = false;
  String? _loadError;
  bool _showingStaleCache = false;
  String _effectiveTenantId = '';
  Timer? _webLoadCap;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _bulkDeleting = false;
  final Map<String, Map<String, dynamic>> _pedidoDataOverrides = {};
  late final TabController _tabController;

  String get _churchId => ChurchRepository.churchId(
        _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId,
      );

  bool? _respondidaFilterFromStatus() {
    if (_filtroStatus == 'Respondidas') return true;
    if (_filtroStatus == 'Não Respondidas') return false;
    return null;
  }

  void _startWebLoadingCap() {
    if (!kIsWeb) return;
    _webLoadCap?.cancel();
    _webLoadCap = Timer(const Duration(seconds: 12), () {
      if (!mounted || !_fetching) return;
      setState(() {
        _fetching = false;
        if (_pedidosDocs.isEmpty) {
          _loadError ??=
              'Tempo esgotado ao carregar pedidos de oração. Toque em atualizar.';
        }
      });
    });
  }

  void _seedPedidosLocal() {
    final churchId = _churchId;
    if (churchId.isEmpty) {
      _pedidosDocs = const [];
      _fetching = false;
      return;
    }
    final filter = _respondidaFilterFromStatus();
    var docs = ChurchPedidosOracaoLoadService.peekRam(
          churchId,
          respondidaFilter: filter,
        ) ??
        const [];
    if (docs.isEmpty && filter != null) {
      final all = ChurchPedidosOracaoLoadService.peekRam(churchId) ?? const [];
      docs = all.where((d) {
        final r = d.data()['respondida'];
        return filter ? r == true : r != true;
      }).toList();
    }
    _pedidosDocs = docs;
    _fetching = _pedidosDocs.isEmpty;
    _loadError = null;
    _showingStaleCache = _pedidosDocs.isNotEmpty;
  }

  Future<void> _fetchPedidos({bool forceFresh = false}) async {
    final churchId = _churchId;
    if (churchId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _loadError = 'Igreja não identificada.';
      });
      return;
    }
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final result = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchPedidosOracaoLoadService.load(
          seedTenantId: churchId,
          respondidaFilter: _respondidaFilterFromStatus(),
          forceRefresh: forceFresh,
          forceServer: forceFresh,
        ),
        maxAttempts: 3,
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final hadLocal = _pedidosDocs.isNotEmpty;
      final ui = PanelResilientLoad.afterFetch(
        hadLocalData: hadLocal,
        newItems: result.docs,
        fromCache: result.fromCache,
        softError: result.softError,
        forceFresh: forceFresh,
      );
      setState(() {
        if (result.docs.isNotEmpty) {
          _pedidosDocs = result.docs;
        }
        _showingStaleCache = ui.showingStaleCache;
        _loadError = ui.loadError;
      });
    } catch (e) {
      if (!mounted) return;
      final ui = PanelResilientLoad.afterError(
        hadLocalData: _pedidosDocs.isNotEmpty,
        error: e,
      );
      setState(() {
        _showingStaleCache = ui.showingStaleCache;
        _loadError = ui.loadError;
      });
    } finally {
      _webLoadCap?.cancel();
      if (mounted) {
        setState(() => _fetching = false);
      }
    }
  }

  void _refreshPedidos({bool forceRefresh = false}) {
    setState(() {
      _fetching = _pedidosDocs.isEmpty;
      _loadError = null;
    });
    unawaited(_fetchPedidos(forceFresh: forceRefresh));
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _effectiveTenantId = ChurchRepository.churchId(widget.tenantId).trim();
    _seedPedidosLocal();
    _startWebLoadingCap();
    unawaited(_fetchPedidos());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _webLoadCap?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PrayerRequestsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _effectiveTenantId = ChurchRepository.churchId(widget.tenantId).trim();
      _seedPedidosLocal();
      unawaited(_fetchPedidos());
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

  User? get _currentUser => firebaseDefaultAuth.currentUser;

  bool _readLegacyBool(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (!data.containsKey(key)) continue;
      final raw = data[key];
      if (raw is bool) return raw;
      final parsed = raw?.toString().trim().toLowerCase();
      if (parsed == null || parsed.isEmpty) continue;
      if (parsed == 'true' || parsed == '1' || parsed == 'sim') return true;
      if (parsed == 'false' || parsed == '0' || parsed == 'nao') return false;
    }
    return false;
  }

  bool _isPublicPrayer(Map<String, dynamic> data) {
    if (_readLegacyBool(data, const ['publico', 'public', 'isPublic', 'is_public'])) {
      return true;
    }
    if (_readLegacyBool(data, const ['somenteLideres', 'leadersOnly', 'private'])) {
      return false;
    }
    final emails = data['destinatariosEmails'];
    if (emails is List && emails.isNotEmpty) return false;
    // Compatibilidade legada: sem campo de visibilidade => público.
    return !data.containsKey('publico') &&
        !data.containsKey('public') &&
        !data.containsKey('isPublic') &&
        !data.containsKey('is_public');
  }

  bool get _isLeader {
    final r = widget.role.toLowerCase();
    return r == 'adm' ||
        r == 'admin' ||
        r == 'administrador' ||
        r == 'gestor' ||
        r == 'master' ||
        r == 'pastor' ||
        r == 'pastora' ||
        r == 'lider' ||
        r == 'líder' ||
        r == 'lideranca' ||
        r == 'tesoureiro';
  }

  bool _canSee(Map<String, dynamic> data) {
    if (_isPublicPrayer(data)) return true;
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

  Map<String, dynamic> _mergedPedidoData(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final base = doc.data();
    final patch = _pedidoDataOverrides[doc.id];
    if (patch == null || patch.isEmpty) return base;
    return {...base, ...patch};
  }

  Future<void> _toggleOrando(
    String docId,
    List<dynamic> orandoUids,
    List<Map<String, dynamic>> orandoMembros,
  ) async {
    final uid = _currentUser?.uid;
    if (uid == null) return;
    final removing = orandoUids.contains(uid);
    final user = _currentUser!;
    List<Map<String, dynamic>> nextMembros;
    List<String> nextUids;
    if (removing) {
      nextMembros = PrayerOrandoMembrosDenorm.removeUid(orandoMembros, uid);
      nextUids = List<String>.from(orandoUids.cast<String>())..remove(uid);
    } else {
      nextMembros = PrayerOrandoMembrosDenorm.upsert(
        orandoMembros,
        uid: uid,
        nome: (user.displayName ?? user.email ?? 'Membro').toString(),
        fotoUrl: (user.photoURL ?? '').toString(),
      );
      nextUids = List<String>.from(orandoUids.cast<String>());
      if (!nextUids.contains(uid)) nextUids.add(uid);
    }
    setState(() {
      _pedidoDataOverrides[docId] = {
        'orandoMembros': nextMembros,
        'orandoUids': nextUids,
        'orandoCount': nextMembros.length,
      };
    });
    try {
      await ChurchPedidosOracaoLoadService.toggleOrando(
        churchId: _churchId,
        docId: docId,
        uid: uid,
        removing: removing,
        memberNome: user.displayName ?? user.email,
        memberFotoUrl: user.photoURL,
        currentOrandoMembros: orandoMembros,
      );
      if (mounted) {
        _pedidoDataOverrides.remove(docId);
        unawaited(_fetchPedidos(forceFresh: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pedidoDataOverrides.remove(docId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar: $e')),
        );
      }
    }
  }

  Future<void> _removeOrandoMemberFromPedido({
    required String docId,
    required String targetUid,
    required List<Map<String, dynamic>> orandoMembros,
    required List<String> orandoUids,
  }) async {
    final nextMembros =
        PrayerOrandoMembrosDenorm.removeUid(orandoMembros, targetUid);
    final nextUids = List<String>.from(orandoUids)..remove(targetUid);
    setState(() {
      _pedidoDataOverrides[docId] = {
        'orandoMembros': nextMembros,
        'orandoUids': nextUids,
        'orandoCount': nextMembros.length,
      };
    });
    try {
      await ChurchPedidosOracaoLoadService.removeOrandoMember(
        churchId: _churchId,
        docId: docId,
        targetUid: targetUid,
        currentOrandoMembros: orandoMembros,
      );
      if (mounted) {
        _pedidoDataOverrides.remove(docId);
        unawaited(_fetchPedidos(forceFresh: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pedidoDataOverrides.remove(docId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao remover: $e')),
        );
      }
    }
  }

  Future<void> _showOrandoMembersSheet({
    required String docId,
    required List<Map<String, dynamic>> orandoMembros,
    required List<String> orandoUids,
  }) async {
    if (orandoMembros.isEmpty) return;
    final uid = _currentUser?.uid;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scroll) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Quem está orando',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (_isLeader && orandoMembros.length > 1)
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _confirmClearOrandoSelected([docId]);
                          },
                          child: const Text('Limpar todos'),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: orandoMembros.length,
                    itemBuilder: (_, i) {
                      final m = orandoMembros[i];
                      final mUid = (m['uid'] ?? '').toString();
                      final nome = (m['nome'] ?? 'Membro').toString();
                      final canRemove =
                          _isLeader || (uid != null && mUid == uid);
                      return ListTile(
                        leading: FotoMembroWidget(
                          size: 40,
                          tenantId: _churchId,
                          memberId: mUid,
                          imageUrl: (m['fotoUrl'] ?? '').toString(),
                          memberData: m,
                        ),
                        title: Text(nome),
                        subtitle: mUid == uid
                            ? const Text('Você')
                            : null,
                        trailing: canRemove
                            ? IconButton(
                                tooltip: 'Remover',
                                icon: Icon(
                                  Icons.person_remove_outlined,
                                  color: Colors.grey.shade700,
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await _removeOrandoMemberFromPedido(
                                    docId: docId,
                                    targetUid: mUid,
                                    orandoMembros: orandoMembros,
                                    orandoUids: orandoUids,
                                  );
                                },
                              )
                            : null,
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
  }

  Future<void> _confirmClearOrandoSelected(List<String> docIds) async {
    if (docIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar intercessores'),
        content: Text(
          'Remover todos os intercessores de ${docIds.length} pedido(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulkDeleting = true);
    try {
      await ChurchPedidosOracaoLoadService.clearOrandoFromPedidos(
        seedTenantId: _churchId,
        docIds: docIds,
      );
      if (mounted) {
        _exitSelectionMode();
        unawaited(_fetchPedidos(forceFresh: true));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Intercessores removidos.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
  }

  Future<void> _marcarRespondida(String docId) async {
    try {
      await ChurchPedidosOracaoLoadService.marcarRespondida(
        churchId: _churchId,
        docId: docId,
      );
      if (mounted) unawaited(_fetchPedidos(forceFresh: true));
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
        await ChurchPedidosOracaoLoadService.deletePedidos(
          seedTenantId: _churchId,
          docIds: [docId],
        );
        if (mounted) {
          unawaited(_fetchPedidos(forceFresh: true));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Pedido excluído.',
                  style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao excluir: $e')));
        }
      }
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Widget _buildSelectionBar() {
    return Material(
      elevation: 12,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              TextButton(
                onPressed: _bulkDeleting
                    ? null
                    : () => setState(() => _selectedIds.clear()),
                child: const Text('Limpar'),
              ),
              Expanded(
                child: Text(
                  '${_selectedIds.length} selecionado(s)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: _bulkDeleting ? null : () => _selectAllFromSnap(),
                child: const Text('Todos'),
              ),
              if (_isLeader) ...[
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: _bulkDeleting || _selectedIds.isEmpty
                      ? null
                      : () => _confirmClearOrandoSelected(_selectedIds.toList()),
                  child: const Text('Limpar orando'),
                ),
              ],
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _bulkDeleting || _selectedIds.isEmpty
                    ? null
                    : () => _confirmDeleteSelected(_selectedIds.length),
                icon: _bulkDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text('Excluir'),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectAllFromSnap() async {
    if (!mounted) return;
    final ids = _pedidosDocs
        .where((d) => _canSee(d.data()))
        .map((d) => d.id)
        .toList();
    setState(() => _selectedIds.addAll(ids));
  }

  Future<void> _confirmDeleteSelected(int count) async {
    if (_selectedIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir selecionados?'),
        content: Text(
          'Deseja excluir $count pedido(s)? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) await _runBulkDelete(_selectedIds.toList());
  }

  Future<void> _confirmDeleteAll() async {
    if (!mounted) return;
    final ids = _pedidosDocs.map((d) => d.id).toList();
    if (ids.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum pedido para excluir.')),
        );
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir TODOS os pedidos?'),
        content: Text(
          'Serão apagados ${ids.length} pedido(s) de oração. Esta ação é irreversível.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir todos'),
          ),
        ],
      ),
    );
    if (ok == true) await _runBulkDelete(ids);
  }

  Future<void> _runBulkDelete(List<String> ids) async {
    setState(() => _bulkDeleting = true);
    try {
      final n = await ChurchPedidosOracaoLoadService.deletePedidos(
        seedTenantId: _churchId,
        docIds: ids,
      );
      if (!mounted) return;
      _exitSelectionMode();
      unawaited(_fetchPedidos(forceFresh: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 1 ? 'Pedido excluído' : '$n pedidos excluídos',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
  }

  Future<void> _openPrayerForm({
    QueryDocumentSnapshot<Map<String, dynamic>>? editDoc,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: ThemeCleanPremium.isMobile(context),
        builder: (_) => _PrayerRequestFormPage(
          tenantId: widget.tenantId,
          churchId: _churchId,
          editDoc: editDoc,
          abrirSeletorMembros: _abrirSeletorMembros,
        ),
      ),
    );
    if (mounted && saved == true) {
      _seedPedidosLocal();
      unawaited(_fetchPedidos());
    }
  }

  void _abrirFormularioEdicao(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    _openPrayerForm(editDoc: doc);
  }

  void _abrirFormulario() {
    _openPrayerForm();
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
              title: Text(_selectionMode
                  ? '${_selectedIds.length} selecionado(s)'
                  : 'Pedidos de Oração'),
              actions: [
                if (_isLeader && _selectionMode)
                  TextButton(
                    onPressed: _bulkDeleting ? null : _exitSelectionMode,
                    child: const Text('Cancelar'),
                  )
                else if (_isLeader) ...[
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Mais opções',
                    onSelected: (v) {
                      if (v == 'select') {
                        setState(() => _selectionMode = true);
                      } else if (v == 'delete_all') {
                        _confirmDeleteAll();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'select',
                        child: Row(
                          children: [
                            Icon(Icons.checklist_rounded, size: 20),
                            SizedBox(width: 10),
                            Text('Selecionar vários'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep_rounded,
                                size: 20, color: ThemeCleanPremium.error),
                            SizedBox(width: 10),
                            Text('Excluir todos',
                                style:
                                    TextStyle(color: ThemeCleanPremium.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (!_selectionMode)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => _refreshPedidos(forceRefresh: true),
                    tooltip: 'Atualizar',
                  ),
              ],
            ),
      floatingActionButton: _selectionMode || _tabController.index != 0
          ? null
          : Container(
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
              if (!_selectionMode)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    padding.top,
                    padding.right,
                    0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: _PrayerPremiumTheme.rose,
                      unselectedLabelColor: Colors.grey.shade600,
                      indicatorColor: _PrayerPremiumTheme.rose,
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.list_alt_rounded, size: 20),
                          text: 'Lista',
                        ),
                        Tab(
                          icon: Icon(Icons.insights_rounded, size: 20),
                          text: 'Painel',
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _selectionMode
                    ? _buildPedidosBody(padding, tt)
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPedidosBody(padding, tt),
                          PrayerAnalyticsPanel(
                            tenantId: widget.tenantId,
                            role: widget.role,
                            pedidosDocs: _pedidosDocs,
                            canSee: _canSee,
                            onDataChanged: () =>
                                unawaited(_fetchPedidos(forceFresh: true)),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar:
          _isLeader && _selectionMode ? _buildSelectionBar() : null,
    );
  }

  Widget _buildPedidosBody(EdgeInsets padding, TextTheme tt) {
    final visibleDocs =
        _pedidosDocs.where((d) => _canSee(d.data())).toList();
    final hasLocal = visibleDocs.isNotEmpty;

    final pendentes =
        visibleDocs.where((d) => d.data()['respondida'] != true).length;
    final respondidas = visibleDocs.length - pendentes;
    var orandoTotal = 0;
    for (final d in visibleDocs) {
      final c = d.data()['orandoCount'];
      orandoTotal += c is int ? c : 0;
    }

    return RefreshIndicator(
      onRefresh: () async => _fetchPedidos(forceFresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding.left),
              child: ChurchPanelResilientLoadBanner(
                hasLocalData: hasLocal,
                isSyncing: _fetching && hasLocal,
                showStaleCache: _showingStaleCache && !_fetching,
                errorTitle: 'Não foi possível carregar os pedidos de oração',
                error: _loadError,
                onRetry: () => _refreshPedidos(forceRefresh: true),
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
                            _seedPedidosLocal();
                          });
                          _startWebLoadingCap();
                          unawaited(_fetchPedidos());
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
              child: _fetching
                  ? const Center(child: ChurchPanelLoadingBody(itemCount: 4))
                  : _buildEmptyState(tt),
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
                  (context, i) {
                    if (i >= visibleDocs.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      );
                    }
                    final doc = visibleDocs[i];
                    final id = doc.id;
                    return GestureDetector(
                      onTap: _selectionMode && _isLeader
                          ? () => setState(() {
                                if (_selectedIds.contains(id)) {
                                  _selectedIds.remove(id);
                                } else {
                                  _selectedIds.add(id);
                                }
                              })
                          : null,
                      child: _buildCard(
                        doc,
                        selectionMode: _selectionMode && _isLeader,
                        selected: _selectedIds.contains(id),
                        onSelectionChanged: _selectionMode && _isLeader
                            ? (v) => setState(() {
                                  if (v) {
                                    _selectedIds.add(id);
                                  } else {
                                    _selectedIds.remove(id);
                                  }
                                })
                            : null,
                      ),
                    );
                  },
                  childCount: visibleDocs.length + (_fetching ? 1 : 0),
                ),
              ),
            ),
        ],
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

  Widget _buildCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    bool selectionMode = false,
    bool selected = false,
    ValueChanged<bool>? onSelectionChanged,
  }) {
    final data = _mergedPedidoData(doc);
    final nome = (data['autorNome'] ?? 'Membro').toString();
    final texto = (data['texto'] ?? '').toString();
    final categoria = (data['categoria'] ?? 'Outro').toString();
    final publico = data['publico'] ?? true;
    final respondida = data['respondida'] ?? false;
    final orandoMembros = PrayerOrandoMembrosDenorm.parseList(data['orandoMembros']);
    final orandoUids = orandoMembros.isNotEmpty
        ? PrayerOrandoMembrosDenorm.uidsFromMembros(orandoMembros)
        : List<String>.from(data['orandoUids'] ?? []);
    final orandoCount = orandoMembros.isNotEmpty
        ? orandoMembros.length
        : (data['orandoCount'] ?? orandoUids.length);
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
          color: selectionMode && selected
              ? _PrayerPremiumTheme.rose
              : respondida
                  ? const Color(0xFF86EFAC).withValues(alpha: 0.6)
                  : catFg.withValues(alpha: 0.18),
          width: selectionMode && selected ? 2 : 1,
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
                    if (selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 4),
                        child: Checkbox(
                          value: selected,
                          activeColor: _PrayerPremiumTheme.rose,
                          onChanged: onSelectionChanged == null
                              ? null
                              : (v) => onSelectionChanged(v ?? false),
                        ),
                      ),
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
                    if (_canManage(data) && !selectionMode)
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (orandoMembros.isNotEmpty)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showOrandoMembersSheet(
                            docId: doc.id,
                            orandoMembros: orandoMembros,
                            orandoUids: List<String>.from(orandoUids),
                          ),
                          child: _OrandoMembrosAvatarStack(
                            tenantId: _churchId,
                            membros: orandoMembros,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    _OrandoButton(
                      isOrando: isOrando,
                      count: orandoCount is int
                          ? orandoCount
                          : orandoMembros.length,
                      onTap: () =>
                          _toggleOrando(doc.id, orandoUids, orandoMembros),
                    ),
                  ],
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

class _OrandoMembrosAvatarStack extends StatelessWidget {
  const _OrandoMembrosAvatarStack({
    required this.tenantId,
    required this.membros,
  });

  final String tenantId;
  final List<Map<String, dynamic>> membros;

  @override
  Widget build(BuildContext context) {
    const maxVisible = 5;
    final shown = membros.take(maxVisible).toList();
    final rest = membros.length - shown.length;
    final stackW = 28.0 + (shown.length - 1) * 20.0 + (rest > 0 ? 28.0 : 0.0);

    return Row(
      children: [
        SizedBox(
          height: 32,
          width: stackW,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 20.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: _PrayerPremiumTheme.rose.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: FotoMembroWidget(
                      size: 28,
                      tenantId: tenantId,
                      memberId: (shown[i]['uid'] ?? '').toString(),
                      imageUrl: (shown[i]['fotoUrl'] ?? '').toString(),
                      memberData: shown[i],
                    ),
                  ),
                ),
              if (rest > 0)
                Positioned(
                  left: shown.length * 20.0,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          _PrayerPremiumTheme.rose.withValues(alpha: 0.85),
                          _PrayerPremiumTheme.violet.withValues(alpha: 0.75),
                        ],
                      ),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      '+$rest',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            membros.length == 1
                ? '${membros.first['nome']} está orando'
                : '${membros.length} intercedendo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
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

/// Formulário dedicado — Voltar + gravação rápida via [ChurchPedidosOracaoLoadService].
class _PrayerRequestFormPage extends StatefulWidget {
  final String tenantId;
  final String churchId;
  final QueryDocumentSnapshot<Map<String, dynamic>>? editDoc;
  final Future<List<String>?> Function(
    BuildContext context,
    String tenantId,
    List<String> selecionadosIniciais,
  ) abrirSeletorMembros;

  const _PrayerRequestFormPage({
    required this.tenantId,
    required this.churchId,
    this.editDoc,
    required this.abrirSeletorMembros,
  });

  @override
  State<_PrayerRequestFormPage> createState() => _PrayerRequestFormPageState();
}

class _PrayerRequestFormPageState extends State<_PrayerRequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _textoCtrl;
  late String _categoria;
  late String _visibilidade;
  late List<String> _destinatariosEmails;
  bool _saving = false;

  static const _categorias = _PrayerRequestsPageState._categoriasForm;
  static const _categoriaCores = _PrayerRequestsPageState._categoriaCores;
  static const _categoriaTexto = _PrayerRequestsPageState._categoriaTexto;

  bool get _isEdit => widget.editDoc != null;

  @override
  void initState() {
    super.initState();
    final data = widget.editDoc?.data();
    _textoCtrl = TextEditingController(text: (data?['texto'] ?? '').toString());
    _categoria = (data?['categoria'] ?? 'Outro').toString();
    final publico = data?['publico'] == true;
    final destRaw = data?['destinatariosEmails'];
    _destinatariosEmails = destRaw is List
        ? destRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
        : [];
    if (_isEdit) {
      _visibilidade = publico
          ? 'publico'
          : (_destinatariosEmails.isNotEmpty ? 'membros' : 'lideres');
    } else {
      _visibilidade = 'publico';
    }
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: const Color(0xFFFDF2F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide(
          color: _PrayerPremiumTheme.rose.withValues(alpha: 0.18),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: const BorderSide(
          color: _PrayerPremiumTheme.rose,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
    );
  }

  Widget _categoriaChip(String cat) {
    final sel = _categoria == cat;
    final accent = _categoriaTexto[cat] ?? const Color(0xFF475569);
    final fill = _categoriaCores[cat] ?? const Color(0xFFF1F5F9);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _categoria = cat),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: sel ? fill : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel ? accent : const Color(0xFFCBD5E1),
              width: sel ? 2 : 1,
            ),
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
                    color: sel ? accent : const Color(0xFF334155),
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_visibilidade == 'membros' && _destinatariosEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione pelo menos um membro.')),
      );
      return;
    }

    final user = firebaseDefaultAuth.currentUser;
    if (!_isEdit && user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login para enviar.')),
      );
      return;
    }

    setState(() => _saving = true);

    final publico = _visibilidade == 'publico';
    final dest = _visibilidade == 'membros'
        ? _destinatariosEmails
        : <String>[];

    final payload = <String, dynamic>{
      'texto': _textoCtrl.text.trim(),
      'categoria': _categoria,
      'publico': publico,
      'destinatariosEmails': dest,
    };

    if (!_isEdit && user != null) {
      payload['autorNome'] = user.displayName ?? user.email ?? 'Membro';
      payload['autorUid'] = user.uid;
    }

    try {
      await ChurchPedidosOracaoLoadService.savePedido(
        churchId: widget.churchId,
        payload: payload,
        existingDocId: _isEdit ? widget.editDoc!.id : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit ? 'Pedido atualizado.' : 'Pedido enviado com sucesso!',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isMobile = ThemeCleanPremium.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          style: IconButton.styleFrom(
            minimumSize: const Size(
              ThemeCleanPremium.minTouchTarget,
              ThemeCleanPremium.minTouchTarget,
            ),
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: _PrayerPremiumTheme.heroGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x33EC4899),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
        ),
        title: Text(
          _isEdit ? 'Editar Pedido de Oração' : 'Novo Pedido de Oração',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 560),
            child: SingleChildScrollView(
              padding: ThemeCleanPremium.pagePadding(context),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _textoCtrl,
                            maxLines: 5,
                            maxLength: 500,
                            enabled: !_saving,
                            decoration: _fieldDecoration(
                              label: 'Seu pedido de oração',
                              hint: 'Compartilhe aqui seu pedido...',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Informe o pedido'
                                : null,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Text('Categoria', style: tt.titleSmall),
                          const SizedBox(height: ThemeCleanPremium.spaceXs),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _categorias.map(_categoriaChip).toList(),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          Text('Quem pode ver', style: tt.titleSmall),
                          const SizedBox(height: ThemeCleanPremium.spaceXs),
                          ...['publico', 'lideres', 'membros'].map(
                            (v) => RadioListTile<String>(
                              title: Text(
                                v == 'publico'
                                    ? 'Público (todos os membros)'
                                    : v == 'lideres'
                                        ? 'Apenas líderes'
                                        : 'Membros selecionados',
                              ),
                              value: v,
                              groupValue: _visibilidade,
                              onChanged: _saving
                                  ? null
                                  : (val) => setState(
                                        () => _visibilidade = val ?? _visibilidade,
                                      ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: _PrayerPremiumTheme.rose,
                            ),
                          ),
                          if (_visibilidade == 'membros') ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () async {
                                      final picked =
                                          await widget.abrirSeletorMembros(
                                        context,
                                        widget.tenantId,
                                        _destinatariosEmails,
                                      );
                                      if (mounted && picked != null) {
                                        setState(
                                            () => _destinatariosEmails = picked);
                                      }
                                    },
                              icon: const Icon(Icons.people_rounded, size: 20),
                              label: Text(
                                _destinatariosEmails.isEmpty
                                    ? 'Selecionar membros'
                                    : '${_destinatariosEmails.length} membro(s) selecionado(s)',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceLg),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: ThemeCleanPremium.minTouchTarget,
                            child: OutlinedButton(
                              onPressed:
                                  _saving ? null : () => Navigator.maybePop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _PrayerPremiumTheme.rose,
                                side: BorderSide(
                                  color: _PrayerPremiumTheme.rose
                                      .withValues(alpha: 0.55),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Voltar',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: ThemeCleanPremium.spaceSm),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: ThemeCleanPremium.minTouchTarget,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: _PrayerPremiumTheme.rose,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(_isEdit
                                      ? Icons.save_rounded
                                      : Icons.send_rounded),
                              label: Text(
                                _isEdit ? 'Salvar' : 'Enviar Pedido',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
        ),
      ),
    );
  }
}
