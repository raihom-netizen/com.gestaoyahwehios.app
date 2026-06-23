import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/lazy_load_more_footer.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Painel Master — visão 360: utilizadores `users/`, filtro por igreja e plataforma,
/// pesquisa moderna e remapeamento de UID de membro (Firebase Auth + ficha).
///
/// Quando [embeddedInMaster] é true (painel admin), não usa AppBar próprio —
/// evita duplicar barra e garante corpo **apenas com scroll** (sem `Expanded`
/// preso a constraints verticais indefinidas do viewport SaaS).
class MasterUsuariosControle360Page extends StatefulWidget {
  const MasterUsuariosControle360Page({super.key, this.embeddedInMaster = true});

  /// Incorporado em [AdminPanelPage]: sem AppBar local; ações no cartão superior.
  final bool embeddedInMaster;

  @override
  State<MasterUsuariosControle360Page> createState() =>
      _MasterUsuariosControle360PageState();
}

class _User360Row {
  final String uid;
  final Map<String, dynamic> data;
  _User360Row(this.uid, this.data);

  String get email =>
      (data['email'] ?? data['EMAIL'] ?? '').toString().trim();
  String get nome =>
      (data['nome'] ?? data['displayName'] ?? data['name'] ?? '').toString().trim();
  String get tenantId =>
      (data['tenantId'] ?? data['igrejaId'] ?? '').toString().trim();
  String get role => (data['role'] ?? data['nivel'] ?? '').toString().trim();
  String get platform =>
      (data['lastClientPlatform'] ?? '').toString().trim().toLowerCase();
  DateTime? get platformAt {
    final v = data['lastClientPlatformAt'];
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

class _MasterUsuariosControle360PageState extends State<MasterUsuariosControle360Page> {
  bool _loading = true;
  String? _loadError;
  List<_User360Row> _rows = [];
  final Map<String, String> _igrejaNomePorId = {};
  int _usersQueryLimit = YahwehPerformanceV4.masterUsersPageSize;
  bool _usersHasMore = false;
  bool _usersLoadingMore = false;
  String _search = '';
  String? _filtroIgrejaId;
  String _filtroPlataforma = 'todos';
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool resetUsersLimit = true}) async {
    if (resetUsersLimit) {
      _usersQueryLimit = YahwehPerformanceV4.masterUsersPageSize;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final churches = await MasterChurchesListService.loadFast();
      final map = <String, String>{};
      for (final c in churches) {
        final n = (c.data['name'] ?? c.data['nome'] ?? c.id).toString().trim();
        map[c.id] = n.isEmpty ? c.id : n;
      }

      QuerySnapshot<Map<String, dynamic>> usersSnap;
      try {
        usersSnap = await MasterAdminFirestore.query(
          firebaseDefaultFirestore
              .collection('users')
              .orderBy('lastClientPlatformAt', descending: true)
              .limit(_usersQueryLimit),
          cacheKey: 'master_users_360',
        );
      } catch (_) {
        usersSnap = await MasterAdminFirestore.query(
          firebaseDefaultFirestore
              .collection('users')
              .limit(_usersQueryLimit),
          cacheKey: 'master_users_360_fallback',
        );
      }
      final list = usersSnap.docs
          .map((d) => _User360Row(d.id, d.data()))
          .toList()
        ..sort((a, b) {
          final ta = a.platformAt;
          final tb = b.platformAt;
          if (ta != null && tb != null) return tb.compareTo(ta);
          if (ta != null) return -1;
          if (tb != null) return 1;
          return a.email.toLowerCase().compareTo(b.email.toLowerCase());
        });

      if (!mounted) return;
      setState(() {
        _igrejaNomePorId
          ..clear()
          ..addAll(map);
        _rows = list;
        _usersHasMore = usersSnap.docs.length >= _usersQueryLimit;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _usersHasMore = false;
        _loading = false;
        _loadError = MasterAdminFirestore.formatLoadError(e);
      });
    }
  }

  Future<void> _loadMoreUsers() async {
    if (_usersLoadingMore || !_usersHasMore) return;
    setState(() {
      _usersLoadingMore = true;
      _usersQueryLimit += YahwehPerformanceV4.masterUsersPageSize;
    });
    try {
      await _load(resetUsersLimit: false);
    } finally {
      if (mounted) setState(() => _usersLoadingMore = false);
    }
  }

  List<_User360Row> get _filtrados {
    final q = _search.trim().toLowerCase();
    return _rows.where((r) {
      if (_filtroIgrejaId != null && _filtroIgrejaId!.isNotEmpty) {
        if (r.tenantId != _filtroIgrejaId) return false;
      }
      if (_filtroPlataforma != 'todos') {
        final p = r.platform.isEmpty ? 'desconhecido' : r.platform;
        if (_filtroPlataforma == 'desconhecido') {
          if (r.platform.isNotEmpty) return false;
        } else if (p != _filtroPlataforma) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      return r.uid.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.nome.toLowerCase().contains(q) ||
          r.tenantId.toLowerCase().contains(q) ||
          (_igrejaNomePorId[r.tenantId] ?? '')
              .toLowerCase()
              .contains(q);
    }).toList();
  }

  Future<void> _abrirRemapearUid() async {
    final tenantCtrl = TextEditingController();
    final memberCtrl = TextEditingController();
    final newUidCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Remapear UID do membro (master)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Associa a ficha em igrejas/{tenant}/membros ao UID já existente no Firebase Auth. '
                'O login antigo deixa de existir para esse membro.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: tenantCtrl,
                decoration: const InputDecoration(
                  labelText: 'tenantId da igreja',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: memberCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID do documento membros (ou authUid antigo)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newUidCtrl,
                decoration: const InputDecoration(
                  labelText: 'Novo UID (Firebase Auth)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Executar'),
          ),
        ],
      ),
    );
    final tid = tenantCtrl.text.trim();
    final mid = memberCtrl.text.trim();
    final nu = newUidCtrl.text.trim();
    tenantCtrl.dispose();
    memberCtrl.dispose();
    newUidCtrl.dispose();
    if (ok != true || !mounted) return;
    if (tid.isEmpty || mid.isEmpty || nu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Preencha todos os campos.'),
      );
      return;
    }
    try {
      await FirebaseFunctions.instanceFor(
        app: firebaseDefaultApp,
        region: 'us-central1',
      )
          .httpsCallable('masterRelinkMembroAuthUid')
          .call({
        'tenantId': tid,
        'memberId': mid,
        'newAuthUid': nu,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('UID remapeado. Peça novo login ao utilizador.'),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha: $e')),
        );
      }
    }
  }

  IconData _platformIcon(String p) {
    switch (p) {
      case 'web':
        return Icons.language_rounded;
      case 'android':
        return Icons.android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final filtrados = _filtrados;
    final primary = ThemeCleanPremium.primary;

    final heroCard = MasterPremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primary.withValues(alpha: 0.22),
                      primary.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: primary.withValues(alpha: 0.2)),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Icon(Icons.threesixty_rounded, color: primary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Utilizadores — visão 360',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: -0.35,
                        color: ThemeCleanPremium.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Documentos em users/. Plataforma = última sessão no painel da igreja (web / Android / iOS).',
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.embeddedInMaster) ...[
                IconButton(
                  tooltip: 'Atualizar lista',
                  onPressed: _load,
                  icon: Icon(Icons.refresh_rounded, color: primary),
                ),
              ],
            ],
          ),
          if (widget.embeddedInMaster) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _abrirRemapearUid,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: const Text('Remapear UID membro'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, color: primary.withValues(alpha: 0.85)),
              hintText: 'Pesquisar por e-mail, nome, UID, igreja…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onChanged: (v) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                if (!mounted) return;
                if (v == _search) return;
                setState(() => _search = v);
              });
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: kIsWeb ? 320 : double.infinity,
                child: DropdownButtonFormField<String?>(
                  value: _filtroIgrejaId, // ignore: deprecated_member_use
                  decoration: InputDecoration(
                    labelText: 'Igreja',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas as igrejas'),
                    ),
                    ..._igrejaNomePorId.entries.map(
                      (e) => DropdownMenuItem<String?>(
                        value: e.key,
                        child: Text(
                          e.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filtroIgrejaId = v),
                ),
              ),
              FilterChip(
                label: const Text('Todos'),
                selected: _filtroPlataforma == 'todos',
                selectedColor: primary.withValues(alpha: 0.18),
                checkmarkColor: primary,
                onSelected: (_) =>
                    setState(() => _filtroPlataforma = 'todos'),
              ),
              FilterChip(
                avatar: Icon(_platformIcon('web'), size: 18),
                label: const Text('Web'),
                selected: _filtroPlataforma == 'web',
                selectedColor: primary.withValues(alpha: 0.18),
                checkmarkColor: primary,
                onSelected: (_) =>
                    setState(() => _filtroPlataforma = 'web'),
              ),
              FilterChip(
                avatar: Icon(_platformIcon('android'), size: 18),
                label: const Text('Android'),
                selected: _filtroPlataforma == 'android',
                selectedColor: primary.withValues(alpha: 0.18),
                checkmarkColor: primary,
                onSelected: (_) =>
                    setState(() => _filtroPlataforma = 'android'),
              ),
              FilterChip(
                avatar: Icon(_platformIcon('ios'), size: 18),
                label: const Text('iOS'),
                selected: _filtroPlataforma == 'ios',
                selectedColor: primary.withValues(alpha: 0.18),
                checkmarkColor: primary,
                onSelected: (_) =>
                    setState(() => _filtroPlataforma = 'ios'),
              ),
              FilterChip(
                label: const Text('Sem dados'),
                selected: _filtroPlataforma == 'desconhecido',
                selectedColor: primary.withValues(alpha: 0.18),
                checkmarkColor: primary,
                onSelected: (_) =>
                    setState(() => _filtroPlataforma = 'desconhecido'),
              ),
            ],
          ),
        ],
      ),
    );

    Widget userTile(_User360Row r) {
      final igNome = _igrejaNomePorId[r.tenantId] ?? r.tenantId;
      final plat = r.platform.isEmpty ? '—' : r.platform;
      final when =
          r.platformAt != null ? df.format(r.platformAt!) : '—';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: MasterPremiumCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _platformIcon(
                    r.platform.isEmpty ? 'out' : r.platform,
                  ),
                  color: primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.nome.isEmpty ? '(sem nome)' : r.nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.email.isEmpty ? 'sem e-mail' : r.email,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      'UID: ${r.uid}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Igreja: $igNome',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (r.role.isNotEmpty)
                      Text(
                        'Papel: ${r.role}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      plat.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Color(0xFF4338CA),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    when,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar UID',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: r.uid));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          ThemeCleanPremium.successSnackBar('UID copiado'),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      primary: !widget.embeddedInMaster,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: widget.embeddedInMaster
          ? null
          : AppBar(
              title: const Text('Controle 360 — Utilizadores'),
              actions: [
                IconButton(
                  tooltip: 'Atualizar lista',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _load,
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: _abrirRemapearUid,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Remapear UID membro'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
      body: SafeArea(
        child: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'A carregar utilizadores e igrejas…',
                      style: TextStyle(
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                color: primary,
                onRefresh: _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (_loadError != null)
                      SliverPadding(
                        padding: pad,
                        sliver: SliverToBoxAdapter(
                          child: MasterPremiumCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: ThemeCleanPremium.error,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Falha ao carregar dados',
                                        style: GoogleFonts.manrope(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: ThemeCleanPremium.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _loadError!,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.4,
                                          color: ThemeCleanPremium
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: _load,
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          size: 20,
                                        ),
                                        label: const Text('Tentar novamente'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: pad,
                      sliver: SliverToBoxAdapter(child: heroCard),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Mostrando ${filtrados.length} de ${_rows.length} carregados',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    if (filtrados.isEmpty && _loadError == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: ThemeCleanPremium.premiumEmptyState(
                          icon: Icons.people_outline_rounded,
                          title: 'Nenhum resultado',
                          subtitle: 'Ajuste filtros ou pesquisa.',
                        ),
                      )
                    else if (filtrados.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          pad.left,
                          0,
                          pad.right,
                          24,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => userTile(filtrados[i]),
                            childCount: filtrados.length,
                          ),
                        ),
                      ),
                    if (_usersHasMore && _loadError == null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          pad.left,
                          0,
                          pad.right,
                          24,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: LazyLoadMoreFooter(
                            loading: _usersLoadingMore,
                            onLoadMore: _loadMoreUsers,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
