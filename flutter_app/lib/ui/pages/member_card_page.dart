import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/carteirinha_consulta_url.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_signatory_load_service.dart';
import 'package:gestao_yahweh/services/member_card_directory_service.dart'
    show
        MemberCardDirectoryService,
        MemberCardListEntry,
        MemberCardSignatory;
import 'package:gestao_yahweh/services/member_card_load_service.dart';
import 'package:gestao_yahweh/services/member_card_sign_service.dart';
import 'package:gestao_yahweh/services/yahweh_share_service.dart';
import 'package:gestao_yahweh/ui/pages/member_card_cnh_nav.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_signatory_picker_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_card_cnh_data.dart';
import 'package:gestao_yahweh/ui/widgets/member_card_cnh_digital.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show churchTenantLogoUrl, sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:screenshot/screenshot.dart';

/// Cartão membro digital — reescrito (busca, preview, assinatura, exportação PNG).
class MemberCardPage extends StatefulWidget {
  const MemberCardPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.memberId,
    this.cpf,
    this.memberSeedData,
    this.onNavigateToMembers,
    this.embeddedInShell = false,
    this.cnhFullscreenOnly = false,
    this.onShellBack,
  });

  final String tenantId;
  final String role;
  final String? memberId;
  final String? cpf;
  final Map<String, dynamic>? memberSeedData;
  final VoidCallback? onNavigateToMembers;
  final bool embeddedInShell;
  final bool cnhFullscreenOnly;
  final VoidCallback? onShellBack;

  @override
  State<MemberCardPage> createState() => _MemberCardPageState();
}

class _MemberRow {
  const _MemberRow({
    required this.id,
    required this.name,
    required this.data,
    this.photoUrl,
  });

  final String id;
  final String name;
  final Map<String, dynamic> data;
  final String? photoUrl;

  bool get isSigned {
    final em = data['carteirinhaAssinadaEm'];
    if (em != null) return true;
    return (data['carteirinhaAssinadaPorNome'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
  }
}

class _MemberCardPageState extends State<MemberCardPage>
    with SingleTickerProviderStateMixin {
  static const _gradA = Color(0xFF6366F1);
  static const _gradB = Color(0xFF0EA5E9);
  static const _gradC = Color(0xFFEC4899);

  late final TextEditingController _searchCtrl;
  Timer? _searchDebounce;
  TabController? _tabs;

  String _churchId = '';
  String _search = '';
  String _genderFilter = 'todos';
  final Set<String> _selectedIds = {};

  List<_MemberRow> _members = [];
  bool _loadingMembers = true;
  Object? _membersError;

  _MemberRow? _previewMember;
  MemberCardLoadPayload? _cardPayload;
  bool _loadingCard = false;
  Object? _cardError;

  final ScreenshotController _shotCtrl = ScreenshotController();

  String get _churchIdResolved => _churchId.isNotEmpty
      ? _churchId
      : ChurchRepository.churchId(ChurchPanelTenant.resolve(widget.tenantId));

  bool get _canManage {
    if (AppPermissions.isRestrictedMember(widget.role)) return false;
    final n = ChurchRolePermissions.normalize(widget.role);
    if (n == ChurchRoleKeys.master ||
        n == ChurchRoleKeys.adm ||
        n == ChurchRoleKeys.gestor) {
      return true;
    }
    return ChurchRolePermissions.snapshotFor(widget.role).editAnyMember;
  }

  bool get _isRestricted =>
      widget.role.toLowerCase() == 'membro' ||
      widget.role.toLowerCase() == 'visitante';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(PublicSiteMediaAuth.ensureWebAnonymousForStorage());
    }
    _churchId = _churchIdResolved;
    _searchCtrl = TextEditingController();
    if (_canManage && !widget.cnhFullscreenOnly) {
      _tabs = TabController(length: 3, vsync: this);
    }
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.cnhFullscreenOnly || _isRestricted) {
      await _loadSingleCard(
        memberId: widget.memberId,
        seed: widget.memberSeedData,
        restricted: _isRestricted,
      );
      return;
    }
    await _reloadMembers();
  }

  Future<void> _reloadMembers() async {
    if (!mounted) return;
    setState(() {
      _loadingMembers = true;
      _membersError = null;
    });
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final instant = MemberCardDirectoryService.peekMembersSync(
        _churchIdResolved,
        limit: 200,
      );
      if (instant != null && instant.isNotEmpty && mounted) {
        setState(() {
          _members = _mapEntries(instant);
          _loadingMembers = false;
        });
      }
      final entries = await MemberCardDirectoryService.loadMembers(
        tenantId: _churchIdResolved,
        limit: 200,
        forceRefresh: instant == null || instant.isEmpty,
      );
      if (!mounted) return;
      setState(() {
        _members = _mapEntries(entries);
        _loadingMembers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _membersError = e;
        _loadingMembers = false;
      });
    }
  }

  List<_MemberRow> _mapEntries(List<MemberCardListEntry> entries) {
    return entries
        .map(
          (e) => _MemberRow(
            id: e.id,
            name: e.name,
            data: e.data,
            photoUrl: e.photoUrl,
          ),
        )
        .toList();
  }

  List<_MemberRow> get _filtered {
    final q = _search.trim().toLowerCase();
    return _members.where((m) {
      if (q.isNotEmpty) {
        final cpf = (m.data['CPF'] ?? m.data['cpf'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\D'), '');
        final qDigits = q.replaceAll(RegExp(r'\D'), '');
        final textHit = m.name.toLowerCase().contains(q) ||
            m.id.toLowerCase().contains(q);
        final cpfHit = qDigits.length >= 3 && cpf.contains(qDigits);
        if (!textHit && !cpfHit) return false;
      }
      if (_genderFilter == 'masculino') {
        if (genderCategoryFromMemberData(m.data) != 'M') return false;
      } else if (_genderFilter == 'feminino') {
        if (genderCategoryFromMemberData(m.data) != 'F') return false;
      }
      return true;
    }).toList();
  }

  Future<void> _loadSingleCard({
    String? memberId,
    Map<String, dynamic>? seed,
    bool restricted = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _loadingCard = true;
      _cardError = null;
    });
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final payload = await MemberCardLoadService.load(
        MemberCardLoadRequest(
          churchIdHint: _churchIdResolved,
          memberId: memberId,
          cpf: widget.cpf,
          memberSeedData: seed,
          restrictedMember: restricted,
        ),
      );
      if (!mounted) return;
      setState(() {
        _cardPayload = payload;
        _loadingCard = false;
        if (payload != null) {
          _previewMember = _MemberRow(
            id: payload.memberId,
            name: (payload.member['NOME_COMPLETO'] ??
                    payload.member['nome'] ??
                    '')
                .toString(),
            data: payload.member,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cardError = e;
        _loadingCard = false;
      });
    }
  }

  Future<void> _openPreview(_MemberRow row) async {
    setState(() {
      _previewMember = row;
      _selectedIds.add(row.id);
    });
    if (_tabs != null) {
      _tabs!.animateTo(1);
      await _loadSingleCard(memberId: row.id, seed: row.data);
    } else {
      openMemberCardCnhFullscreen(
        context,
        tenantId: widget.tenantId,
        role: widget.role,
        memberId: row.id,
        cpf: widget.cpf,
        memberSeedData: row.data,
      );
    }
  }

  Future<void> _signSelected(BuildContext context) async {
    final ids = _selectedIds.isEmpty
        ? (_previewMember != null ? [_previewMember!.id] : <String>[])
        : _selectedIds.toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Selecione um ou mais membros para assinar.',
        ),
      );
      return;
    }
    final signers = await ChurchSignatoryLoadService.loadEligible(
      seedTenantId: _churchIdResolved,
    );
    if (!context.mounted) return;
    final picked = await showChurchSignatoryPickerSheet(
      context,
      title: 'Quem assina a carteirinha?',
      tenantId: _churchIdResolved,
      signers: signers,
    );
    if (picked == null || !context.mounted) return;
    final signatory = MemberCardSignatory(
      memberId: picked.memberId,
      nome: picked.nome,
      cargo: picked.cargo,
      cpf: picked.cpfDigits,
      assinaturaUrl: picked.assinaturaUrl,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Assinar ${ids.length} carteirinha(s)?'),
        content: Text('Signatário: ${signatory.nome} (${signatory.cargo}).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Assinar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final r = await MemberCardSignService.signBatch(
      tenantId: _churchIdResolved,
      memberIds: ids,
      signatory: signatory,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        r.fail == 0
            ? '${r.ok} carteirinha(s) assinada(s).'
            : 'Assinadas: ${r.ok}. Falhas: ${r.fail}.',
      ),
    );
    await _reloadMembers();
    if (_previewMember != null) {
      await _loadSingleCard(
        memberId: _previewMember!.id,
        seed: _previewMember!.data,
      );
    }
  }

  Future<void> _exportPng() async {
    final pr = MediaQuery.devicePixelRatioOf(context) * 1.5;
    final bytes = await _shotCtrl.capture(pixelRatio: pr);
    if (bytes == null || !mounted) return;
    final name = (_previewMember?.name ?? 'carteirinha')
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim();
    await YahwehShareService.shareBytes(
      bytes: bytes,
      fileName: '${name.isEmpty ? 'carteirinha' : name}.png',
      mimeType: 'image/png',
    );
  }

  MemberCardCnhViewData? _viewDataFromPayload(MemberCardLoadPayload p) {
    final tenant = p.tenant;
    final title = (tenant['nome'] ?? tenant['name'] ?? tenant['titulo'] ?? '')
        .toString()
        .trim();
    final subtitle = (tenant['cidade'] ?? tenant['city'] ?? '').toString();
    return MemberCardCnhViewData.fromMaps(
      tenantId: p.igrejaDocId,
      memberId: p.memberId,
      member: p.member,
      tenant: tenant,
      churchTitle: title.isEmpty ? 'Igreja' : title,
      churchSubtitle: subtitle,
      qrPayload: CarteirinhaConsultaUrl.validationUrl(p.igrejaDocId, p.memberId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cnhFullscreenOnly || _isRestricted) {
      return _buildSingleCardScaffold(context);
    }
    return _buildManagerScaffold(context);
  }

  Widget _buildSingleCardScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: widget.cnhFullscreenOnly
          ? AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              title: const Text('Cartão membro'),
            )
          : null,
      body: SafeArea(child: _buildCardBody(context)),
    );
  }

  Widget _buildManagerScaffold(BuildContext context) {
    final hideAppBar =
        widget.embeddedInShell && ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: hideAppBar
          ? null
          : AppBar(
              title: const Text(
                'Cartão membro',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_gradA, _gradB, _gradC],
                  ),
                ),
              ),
              foregroundColor: Colors.white,
            ),
      body: Column(
        children: [
          if (widget.onShellBack != null && _canManage)
            ChurchEmbeddedModuleBar(
              title: 'Emissão de carteirinhas',
              icon: kChurchShellNavEntries[13].icon,
              accent: kChurchShellNavEntries[13].accent,
              onBack: widget.onShellBack!,
              subtitle: 'Buscar · emitir · assinar',
            ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: ThemeCleanPremium.churchPanelBodyGradient,
              ),
              child: SafeArea(
                top: !hideAppBar,
                child: Column(
                  children: [
                    _buildHero(),
                    if (_tabs != null) ...[
                      Material(
                        color: Colors.white,
                        child: TabBar(
                          controller: _tabs,
                          labelColor: _gradA,
                          unselectedLabelColor: Colors.grey.shade600,
                          indicatorColor: _gradC,
                          indicatorWeight: 3,
                          tabs: const [
                            Tab(
                              icon: Icon(Icons.people_alt_rounded, size: 20),
                              text: 'Membros',
                            ),
                            Tab(
                              icon: Icon(Icons.badge_rounded, size: 20),
                              text: 'Cartão',
                            ),
                            Tab(
                              icon: Icon(Icons.draw_rounded, size: 20),
                              text: 'Assinar',
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: [
                            _buildMembersTab(),
                            _buildCardTab(),
                            _buildSignTab(),
                          ],
                        ),
                      ),
                    ] else
                      Expanded(child: _buildMembersTab()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      margin: ThemeCleanPremium.pagePadding(context).copyWith(top: 8, bottom: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gradA, _gradB, _gradC],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: _gradA.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.badge_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emissão de Carteirinha',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Busque membros, visualize o cartão virtual e assine em lote.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    return Padding(
      padding: ThemeCleanPremium.pagePadding(context).copyWith(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou CPF…',
              prefixIcon: Icon(Icons.search_rounded, color: _gradA),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                if (mounted) setState(() => _search = _searchCtrl.text);
              });
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('Todos', 'todos', const Color(0xFF6366F1)),
              _filterChip('Homens', 'masculino', const Color(0xFF0EA5E9)),
              _filterChip('Mulheres', 'feminino', const Color(0xFFEC4899)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${_filtered.length} de ${_members.length} membros',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Recarregar',
                onPressed:
                    _loadingMembers ? null : () => unawaited(_reloadMembers()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Expanded(child: _buildMembersList()),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, Color color) {
    final sel = _genderFilter == value;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _genderFilter = value),
      selectedColor: color.withValues(alpha: 0.18),
      checkmarkColor: color,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: sel ? color : Colors.grey.shade700,
      ),
      side: BorderSide(color: color.withValues(alpha: sel ? 0.6 : 0.25)),
    );
  }

  Widget _buildMembersList() {
    if (_loadingMembers && _members.isEmpty) {
      return YahwehSkeletonLoading.membrosList(itemCount: 8);
    }
    if (_membersError != null && _members.isEmpty) {
      return ChurchPanelErrorBody(
        title: 'Não foi possível carregar membros',
        error: _membersError,
        onRetry: () => unawaited(_reloadMembers()),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _members.isEmpty
              ? 'Nenhum membro cadastrado.'
              : 'Nenhum membro corresponde à busca.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = list[i];
        final selected = _selectedIds.contains(m.id);
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => unawaited(_openPreview(m)),
            onLongPress: _canManage
                ? () => setState(() {
                      if (selected) {
                        _selectedIds.remove(m.id);
                      } else {
                        _selectedIds.add(m.id);
                      }
                    })
                : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _gradA.withValues(alpha: 0.55)
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (_canManage)
                    Checkbox(
                      value: selected,
                      activeColor: _gradA,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedIds.add(m.id);
                        } else {
                          _selectedIds.remove(m.id);
                        }
                      }),
                    ),
                  FotoMembroWidget(
                    tenantId: _churchIdResolved,
                    memberId: m.id,
                    imageUrl: m.photoUrl,
                    size: 52,
                    preferListThumbnail: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m.isSigned ? 'Assinada' : 'Pendente assinatura',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: m.isSigned
                                ? const Color(0xFF059669)
                                : const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardTab() {
    if (_previewMember == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Toque em um membro na aba «Membros» para ver o cartão virtual.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return _buildCardBody(context);
  }

  Widget _buildSignTab() {
    final n = _selectedIds.length;
    return Padding(
      padding: ThemeCleanPremium.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _gradC.withValues(alpha: 0.12),
                  _gradA.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _gradC.withValues(alpha: 0.25)),
            ),
            child: Text(
              n == 0
                  ? 'Marque membros na lista (checkbox) ou abra um cartão e assine só ele.'
                  : '$n membro(s) selecionado(s) para assinatura.',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _gradA,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => unawaited(_signSelected(context)),
            icon: const Icon(Icons.draw_rounded),
            label: Text(
              n == 0 ? 'Assinar membro em preview' : 'Assinar $n selecionado(s)',
            ),
          ),
          if (n > 0) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(_selectedIds.clear),
              child: const Text('Limpar seleção'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardBody(BuildContext context) {
    if (_loadingCard) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cardError != null) {
      return ChurchPanelErrorBody(
        title: 'Não foi possível carregar o cartão',
        error: _cardError,
        onRetry: () => unawaited(
          _loadSingleCard(
            memberId: _previewMember?.id ?? widget.memberId,
            seed: _previewMember?.data ?? widget.memberSeedData,
            restricted: _isRestricted,
          ),
        ),
      );
    }
    final payload = _cardPayload;
    if (payload == null) {
      return const Center(child: Text('Membro não encontrado.'));
    }
    final view = _viewDataFromPayload(payload);
    if (view == null) {
      return const Center(child: Text('Dados incompletos para o cartão.'));
    }
    final logoUrl = sanitizeImageUrl(churchTenantLogoUrl(payload.tenant));
    return SingleChildScrollView(
      padding: ThemeCleanPremium.pagePadding(context),
      child: Column(
        children: [
          Screenshot(
            controller: _shotCtrl,
            child: MemberCardCnhDigital(
              data: view,
              maxWidth: 380,
              logoSlot: StableChurchLogo(
                tenantId: payload.igrejaDocId,
                imageUrl: logoUrl,
                width: 56,
                height: 56,
              ),
              photoSlot: SafeMemberProfilePhoto(
                tenantId: payload.igrejaDocId,
                memberId: payload.memberId,
                memberFirestoreHint: payload.member,
                width: 88,
                height: 88,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _gradB,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => unawaited(_exportPng()),
                icon: const Icon(Icons.image_rounded),
                label: const Text('Exportar PNG'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _gradA,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => openMemberCardCnhFullscreen(
                  context,
                  tenantId: widget.tenantId,
                  role: widget.role,
                  memberId: payload.memberId,
                  cpf: widget.cpf,
                  memberSeedData: payload.member,
                ),
                icon: const Icon(Icons.fullscreen_rounded),
                label: const Text('Tela cheia'),
              ),
              if (_canManage)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gradC,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => unawaited(_signSelected(context)),
                  icon: const Icon(Icons.draw_rounded),
                  label: const Text('Assinar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
