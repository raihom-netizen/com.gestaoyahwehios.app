import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/services/city_autocomplete_service.dart';
import 'package:gestao_yahweh/services/church_canonical_media_publish.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/services/member_profile_photo_pick_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_save_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/services/church_functions_service.dart';
import 'package:gestao_yahweh/services/dashboard_stats_counter_service.dart';
import 'package:gestao_yahweh/services/member_codigo_service.dart';
import 'package:gestao_yahweh/services/members_limit_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/public_church_site_bootstrap.dart';
import 'package:gestao_yahweh/services/public_church_slug_resolver.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableChurchLogo;
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';
import 'package:gestao_yahweh/ui/site_publico_igreja/church_public_site_shell.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/default_church_logo_asset.dart';
import 'package:gestao_yahweh/ui/widgets/member_signup_premium_ui.dart';
import 'package:gestao_yahweh/ui/widgets/member_display_name_utils.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_public_site_ui.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        churchTenantLogoHttpsUrl,
        isValidImageUrl,
        memCacheExtentForLogicalSize,
        ResilientNetworkImage,
        sanitizeImageUrl;
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:gestao_yahweh/debug/agent_debug_log.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

class PublicMemberSignupPage extends StatefulWidget {
  /// Slug da igreja (para link público). Se null, use [tenantId].
  final String? slug;

  /// ID do tenant (para abrir a partir do painel quando a igreja não tem slug).
  final String? tenantId;
  const PublicMemberSignupPage({super.key, this.slug, this.tenantId})
      : assert(slug != null || tenantId != null, 'Informe slug ou tenantId');

  @override
  State<PublicMemberSignupPage> createState() => _PublicMemberSignupPageState();
}

class _PublicMemberSignupPageState extends State<PublicMemberSignupPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
  final _quadraLoteNumeroCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController();
  final _estadoCivilCtrl = TextEditingController();
  final _escolaridadeCtrl = TextEditingController();
  final _profissaoCtrl = TextEditingController();
  final _conjugeCtrl = TextEditingController();
  final _filiacaoPaiCtrl = TextEditingController();
  final _filiacaoMaeCtrl = TextEditingController();

  String? _tenantId;
  String _tenantName = 'Igreja';
  String? _tenantLogoUrl;
  /// Snapshot do doc `igrejas/{id}` para resolver logo via path/Storage (igual ao site público).
  Map<String, dynamic>? _tenantChurchData;
  /// URL já resolvida em [_loadTenant] — evita segundo [resolveChurchTenantLogoUrl] no [StableChurchLogo].
  String? _resolvedChurchLogoUrl;
  String _tenantEndereco = '';

  /// Alias e slug da igreja para amarrar o membro ao tenant (segurança: outra igreja não vê esses membros).
  String _tenantAlias = '';
  String _tenantSlug = '';

  DateTime? _birthDate;
  final _birthDateCtrl = TextEditingController();
  String _sexo = 'Masculino';

  XFile? _photoFile;
  Uint8List? _photoBytes;
  bool _loading = true;
  bool _saving = false;
  bool _loadingCep = false;
  bool _submittedSuccess = false;
  bool _tenantBlocked = false;
  String _submittedMemberName = '';
  String? _lastSubmittedDocId;
  bool _editModeAfterSubmit = false;
  bool _loadingCitySuggestions = false;
  List<CitySuggestion> _citySuggestions = const [];
  int _citySearchToken = 0;

  /// Wizard: 0 dados pessoais, 1 endereço, 2 família/foto/envio.
  int _signupStep = 0;

  Color get _signupStepAccent {
    const colors = [
      Color(0xFF6366F1),
      Color(0xFF10B981),
      Color(0xFFF97316),
    ];
    return colors[_signupStep.clamp(0, 2)];
  }

  InputDecoration _signInput({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffixIcon,
    String? counterText,
    bool required = false,
  }) =>
      memberSignupInputDecoration(
        label: label,
        hint: hint,
        icon: icon,
        suffixIcon: suffixIcon,
        counterText: counterText,
        accentColor: _signupStepAccent,
        required: required,
      );

  String? _reqEmail(String? v) {
    final base = _req(v);
    if (base != null) return base;
    final t = v!.trim();
    if (!t.contains('@') || t.length < 5) return 'E-mail inválido';
    return null;
  }

  /// UFs do Brasil para seleção manual (quando não sabe o CEP).
  static const List<String> _ufs = [
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO',
  ];
  @override
  void initState() {
    super.initState();
    unawaited(YahwehModuleMediaGate.ensureReadyForPublicMedia(
      module: YahwehMediaModule.membros,
    ));
    final slugPeek = (widget.slug ?? '').trim();
    if (slugPeek.isNotEmpty) {
      final instant = PublicChurchSlugResolver.peek(slugPeek);
      if (instant != null) {
        _applyTenantFromChurchDataSync(instant.churchId, instant.profile);
      }
    }
    if (_tryApplySessionChurchInstant()) {
      unawaited(_bootstrap(backgroundOnly: true));
    } else {
      unawaited(_bootstrap());
    }
  }

  /// Painel Android/iOS — dados da igreja já na sessão (sem skeleton prolongado).
  bool _tryApplySessionChurchInstant() {
    final ctxData = ChurchContextService.currentChurchData;
    final ctxId = ChurchContextService.currentChurchId;
    if (ctxData == null ||
        ctxData.isEmpty ||
        ctxId == null ||
        ctxId.isEmpty) {
      return false;
    }
    final hint = (widget.tenantId ?? widget.slug ?? '').trim();
    if (hint.isNotEmpty) {
      final panel = ChurchContextService.panelChurchId(hint);
      final canonical = ChurchRepository.churchId(hint);
      if (hint != ctxId && panel != ctxId && canonical != ctxId) {
        return false;
      }
    }
    _applyTenantFromChurchDataSync(ctxId, ctxData);
    return true;
  }

  /// Auth de visitante + carga da igreja — Web, Android e iOS (bootstrap único).
  Future<void> _bootstrap({bool backgroundOnly = false}) async {
    if (backgroundOnly) {
      await _loadTenant(refreshInBackground: true);
      return;
    }
    await _loadTenant();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cpfCtrl.dispose();
    _cepCtrl.dispose();
    _cityCtrl.dispose();
    _bairroCtrl.dispose();
    _enderecoCtrl.dispose();
    _quadraLoteNumeroCtrl.dispose();
    _estadoCtrl.dispose();
    _estadoCivilCtrl.dispose();
    _escolaridadeCtrl.dispose();
    _profissaoCtrl.dispose();
    _birthDateCtrl.dispose();
    _conjugeCtrl.dispose();
    _filiacaoPaiCtrl.dispose();
    _filiacaoMaeCtrl.dispose();
    super.dispose();
  }

  String _onlyDigits(String v) => memberSignupOnlyDigits(v);

  static String _buildFiliacaoLegado(String pai, String mae) {
    if (pai.isEmpty && mae.isEmpty) return '';
    if (pai.isEmpty) return mae;
    if (mae.isEmpty) return pai;
    return '$pai e $mae';
  }

  static String _buildEndereco({
    required String rua,
    required String bairro,
    required String cidade,
    required String estado,
    required String cep,
  }) {
    final parts = <String>[];
    if (rua.isNotEmpty) parts.add(rua);
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty && estado.isNotEmpty) {
      parts.add('$cidade - $estado');
    } else if (cidade.isNotEmpty) {
      parts.add(cidade);
    } else if (estado.isNotEmpty) {
      parts.add(estado);
    }
    if (cep.isNotEmpty) parts.add('CEP $cep');
    return parts.join(', ');
  }

  /// Marca padrão quando não há logo ou falha 403/rede (padding adapta em telas baixas).
  Widget _fallbackGestaoYahwehLogo(double maxWidth, double maxHeight) {
    return DefaultChurchLogoAsset(
      width: maxWidth,
      height: maxHeight,
      fractionOfBox: 0.9,
      borderRadius: BorderRadius.circular(16),
    );
  }

  /// Mesmo pipeline do site público ([StableChurchLogo]): token Storage na web + path legado.
  Widget _publicSignupChurchLogo({
    required double maxWidth,
    required double maxHeight,
  }) {
    final tid = _tenantId?.trim();
    final tenantMap = _tenantChurchData;
    final fallback = _fallbackGestaoYahwehLogo(maxWidth, maxHeight);
    if (tid == null || tid.isEmpty) return fallback;

    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheW =
        memCacheExtentForLogicalSize(maxWidth, dpr, maxPx: 512);
    final cacheH =
        memCacheExtentForLogicalSize(maxHeight, dpr, maxPx: 512);

    final pre = _resolvedChurchLogoUrl?.trim();
    if (pre != null && pre.isNotEmpty) {
      final clean = sanitizeImageUrl(pre);
      if (isValidImageUrl(clean)) {
        final ph = SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        );
        return SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ResilientNetworkImage(
              key: ValueKey<String>('pubmemlogo_direct_$tid'),
              imageUrl: clean,
              width: maxWidth,
              height: maxHeight,
              fit: BoxFit.contain,
              memCacheWidth: cacheW,
              memCacheHeight: cacheH,
              placeholder: ph,
              errorWidget: fallback,
            ),
          ),
        );
      }
    }

    final preferRaw = _tenantLogoUrl?.trim();
    final prefer =
        (preferRaw != null && preferRaw.isNotEmpty) ? preferRaw : null;
    final sp = ChurchImageFields.logoStoragePath(tenantMap, churchIdHint: tid);

    return SizedBox(
      width: maxWidth,
      height: maxHeight,
      child: StableChurchLogo(
        key: ValueKey<String>('pubmemlogo_${tid}_${prefer ?? ''}_${sp ?? ''}'),
        tenantId: tid,
        tenantData: tenantMap,
        imageUrl: prefer,
        storagePath: sp ??
            (tid.isNotEmpty ? ChurchStorageLayout.churchIdentityLogoPath(tid) : null),
        width: maxWidth,
        height: maxHeight,
        fit: BoxFit.contain,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
      ),
    );
  }

  /// URL https ou null — path Storage resolve via [_prefetchChurchLogoUrl].
  static String? _logoUrlFromChurchDoc(Map<String, dynamic> data) {
    final https = churchTenantLogoHttpsUrl(data);
    if (https.isNotEmpty) return https;
    return null;
  }

  Future<String?> _prefetchChurchLogoUrl({
    required String tenantDocId,
    required Map<String, dynamic> churchWithId,
  }) async {
    try {
      final tid = tenantDocId.trim();
      return await AppStorageImageService.instance.resolveChurchTenantLogoUrl(
        tenantId: tid,
        tenantData: churchWithId,
        preferImageUrl: ChurchImageFields.logoHttpsUrlFromDoc(churchWithId),
        preferStoragePath: ChurchImageFields.logoStoragePath(
              churchWithId,
              churchIdHint: tid,
            ) ??
            ChurchBrandService.canonicalLogoPath(tid),
      );
    } catch (_) {
      return null;
    }
  }

  /// Busca CEP via ViaCEP e preenche endereço, bairro, cidade e estado automaticamente.
  Future<void> _buscarCep() async {
    final cep = _onlyDigits(_cepCtrl.text);
    if (cep.length != 8) return;
    setState(() => _loadingCep = true);
    try {
      final result = await fetchCep(_cepCtrl.text.trim());
      if (!mounted) return;
      if (!result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'CEP não encontrado. Preencha os campos manualmente ou tente outro CEP.')),
        );
        setState(() => _loadingCep = false);
        return;
      }
      if (result.logradouro != null && result.logradouro!.isNotEmpty)
        _enderecoCtrl.text = result.logradouro!;
      if (result.bairro != null && result.bairro!.isNotEmpty)
        _bairroCtrl.text = result.bairro!;
      if (result.localidade != null && result.localidade!.isNotEmpty)
        _cityCtrl.text = result.localidade!;
      if (result.uf != null && result.uf!.isNotEmpty)
        _estadoCtrl.text = result.uf!;
      if (result.cep != null && result.cep!.isNotEmpty)
        _cepCtrl.text = result.cep!;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Endereço preenchido automaticamente pelo CEP.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar CEP: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingCep = false);
    }
  }

  Future<void> _searchCitySuggestions(String raw) async {
    final query = raw.trim();
    final token = ++_citySearchToken;
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _loadingCitySuggestions = false;
        _citySuggestions = const [];
      });
      return;
    }
    setState(() => _loadingCitySuggestions = true);
    final list = await searchBrazilCities(query, limit: 8);
    if (!mounted || token != _citySearchToken) return;
    setState(() {
      _loadingCitySuggestions = false;
      _citySuggestions = list;
    });
  }

  void _applyCitySuggestion(CitySuggestion s) {
    _cityCtrl.text = s.city;
    _estadoCtrl.text = s.state;
    setState(() {
      _citySuggestions = const [];
      _loadingCitySuggestions = false;
    });
  }

  Future<void> _applyTenantFromChurchDoc(
    DocumentSnapshot<Map<String, dynamic>> d,
  ) async {
    await _applyTenantFromChurchData(d.id, d.data() ?? {});
  }

  void _applyTenantFromChurchDataSync(String docId, Map<String, dynamic> data) {
    final operational = ChurchContextService.panelChurchId(docId);
    final op = operational.isNotEmpty ? operational : docId;
    final churchWithId = Map<String, dynamic>.from(data)..['id'] = op;
    final endereco = (data['endereco'] ?? '').toString().trim();
    final rua = (data['rua'] ?? '').toString().trim();
    final bairro = (data['bairro'] ?? '').toString().trim();
    final cidade = (data['cidade'] ?? '').toString().trim();
    final estado = (data['estado'] ?? '').toString().trim();
    final cep = (data['cep'] ?? '').toString().trim();
    final enderecoCompleto = endereco.isNotEmpty
        ? endereco
        : _buildEndereco(
            rua: rua,
            bairro: bairro,
            cidade: cidade,
            estado: estado,
            cep: cep,
          );
    final logoFromDoc = _logoUrlFromChurchDoc(data);
    _tenantId = op;
    _tenantChurchData = churchWithId;
    _tenantName = (data['name'] ?? data['nome'] ?? 'Igreja').toString();
    _tenantBlocked = SubscriptionGuard.evaluate(church: data).blocked;
    _tenantLogoUrl = logoFromDoc;
    _resolvedChurchLogoUrl = logoFromDoc;
    _tenantEndereco = enderecoCompleto;
    _tenantAlias =
        (data['alias'] ?? data['slug'] ?? op).toString().trim();
    _tenantSlug = (data['slug'] ?? data['alias'] ?? op).toString().trim();
    if (_tenantAlias.isEmpty) _tenantAlias = op;
    if (_tenantSlug.isEmpty) _tenantSlug = op;
    _loading = false;
  }

  void _refreshTenantLogoInBackground(String operational, Map<String, dynamic> data) {
    final churchWithId = Map<String, dynamic>.from(data)..['id'] = operational;
    unawaited(() async {
      final resolved = await _prefetchChurchLogoUrl(
        tenantDocId: operational,
        churchWithId: churchWithId,
      );
      if (!mounted || resolved == null || resolved.isEmpty) return;
      if (_resolvedChurchLogoUrl == resolved) return;
      setState(() => _resolvedChurchLogoUrl = resolved);
    }());
  }

  Future<void> _applyTenantFromChurchData(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!mounted) return;
    setState(() {
      _applyTenantFromChurchDataSync(docId, data);
    });
    final op = (_tenantId ?? docId).trim();
    _refreshTenantLogoInBackground(op, data);
  }

  Future<void> _enrichTenantProfile(
    String slug,
    PublicChurchResolved seed,
  ) async {
    try {
      final full = await PublicChurchSlugResolver.resolveEnrich(
        slug,
        seed: seed,
      );
      if (full != null && mounted) {
        await _applyTenantFromChurchData(full.churchId, full.profile);
      }
    } catch (_) {}
  }

  Future<void> _loadTenant({bool refreshInBackground = false}) async {
    if (refreshInBackground && !_loading) {
      final tid = (_tenantId ?? widget.tenantId ?? '').trim();
      if (tid.isEmpty) return;
      try {
        final hit = await IgrejaDirectFirestoreReads.readIgrejaPublicProfile(tid);
        if (hit != null && hit.data.isNotEmpty && mounted) {
          await _applyTenantFromChurchData(hit.docId, hit.data);
        }
      } catch (_) {}
      return;
    }
    try {
      final resolved = await PublicChurchSiteBootstrap.resolveForSignup(
        slug: widget.slug,
        tenantIdHint: widget.tenantId,
      );
      if (resolved != null) {
        await _applyTenantFromChurchData(
          resolved.churchId,
          resolved.profile,
        );
        final slugTrim = widget.slug?.trim() ?? '';
        if (slugTrim.isNotEmpty) {
          unawaited(_enrichTenantProfile(slugTrim, resolved));
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _resolvedChurchLogoUrl = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _resolvedChurchLogoUrl = null;
      });
    }
  }

  int? _calcAge(DateTime? birth) {
    if (birth == null) return null;
    final now = DateTime.now();
    int age = now.year - birth.year;
    final hasHadBirthday = (now.month > birth.month) ||
        (now.month == birth.month && now.day >= birth.day);
    if (!hasHadBirthday) age -= 1;
    return age;
  }

  String _ageRange(int? age) {
    if (age == null) return '';
    if (age <= 12) return '0-12';
    if (age <= 17) return '13-17';
    if (age <= 25) return '18-25';
    if (age <= 35) return '26-35';
    if (age <= 50) return '36-50';
    return '51+';
  }

  String? _reqName(String? v) => memberNameValidationMessage(v);

  String? _req(String? v) {
    if (v == null || v.trim().isEmpty) return 'Campo obrigatorio';
    return null;
  }

  String _statusTrackPath(String protocol) {
    final slug = _tenantSlug.trim().isNotEmpty
        ? _tenantSlug.trim()
        : (_tenantId ?? 'igreja');
    return '/igreja/$slug/acompanhar-cadastro?protocolo=$protocol';
  }

  /// URL completa para copiar/partilhar (respeita domínio público da igreja quando configurado).
  String _fullTrackingUrl(String protocol) {
    final path = _statusTrackPath(protocol);
    final base =
        AppConstants.publicWebBaseUrlForChurch(_tenantChurchData).trim();
    if (path.startsWith('http')) return path;
    return '$base$path';
  }

  static const double _kSuccessLogoHeight = 152;

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ChurchPublicSiteScaffoldBackground(
        child: SafeArea(
          bottom: true,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, c) {
                              final w = c.maxWidth;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(22),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  boxShadow: [
                                    ...ThemeCleanPremium.softUiCardShadow,
                                    BoxShadow(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.06),
                                      blurRadius: 28,
                                      offset: const Offset(0, 12),
                                      spreadRadius: -4,
                                    ),
                                  ],
                                ),
                                child: _publicSignupChurchLogo(
                                  maxWidth: w,
                                  maxHeight: _kSuccessLogoHeight,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 96,
                            child: Lottie.network(
                              'https://assets3.lottiefiles.com/packages/lf20_at6mub9m.json',
                              repeat: true,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bem-vindo à família!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: Colors.green.shade800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Bem-vindo à $_tenantName!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '${_submittedMemberName.trim().isEmpty ? 'Seu cadastro' : '${_submittedMemberName.trim()}, seu cadastro'} foi enviado para aprovação da liderança.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Quando o gestor aprovar, sua conta de acesso será criada automaticamente com senha inicial 123456 (você poderá trocar depois ou usar “Esqueci a senha”).',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                          if (_emailCtrl.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFF86EFAC).withValues(alpha: 0.7),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.mark_email_read_outlined,
                                      size: 22, color: Colors.green.shade700),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Enviamos um e-mail para ${_emailCtrl.text.trim()} com o link para acompanhar a aprovação (verifique também o spam). Se não receber em alguns minutos, use o protocolo abaixo.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if ((_lastSubmittedDocId ?? '').isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusLg),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.08),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.track_changes_rounded,
                                          color: Colors.blue.shade700, size: 22),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Acompanhamento do cadastro',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SelectableText(
                                    'Protocolo: ${_lastSubmittedDocId!}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E40AF),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                        ),
                                        onPressed: () {
                                          final protocol =
                                              _lastSubmittedDocId!;
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PublicSignupStatusPage(
                                                slug: _tenantSlug.isNotEmpty
                                                    ? _tenantSlug
                                                    : (_tenantId ?? ''),
                                                protocolo: protocol,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                            Icons.visibility_rounded,
                                            size: 20),
                                        label: const Text('Acompanhar agora'),
                                      ),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                        ),
                                        onPressed: () async {
                                          final protocol =
                                              _lastSubmittedDocId!;
                                          final full =
                                              _fullTrackingUrl(protocol);
                                          await Clipboard.setData(
                                            ClipboardData(text: full),
                                          );
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Link completo copiado.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.copy_rounded,
                                            size: 20),
                                        label: const Text('Copiar link'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _submittedSuccess = false;
                                    _lastSubmittedDocId = null;
                                    _editModeAfterSubmit = false;
                                    _nameCtrl.clear();
                                    _emailCtrl.clear();
                                    _phoneCtrl.clear();
                                    _cpfCtrl.clear();
                                    _cepCtrl.clear();
                                    _cityCtrl.clear();
                                    _bairroCtrl.clear();
                                    _enderecoCtrl.clear();
                                    _quadraLoteNumeroCtrl.clear();
                                    _estadoCtrl.clear();
                                    _estadoCivilCtrl.clear();
                                    _escolaridadeCtrl.clear();
                                    _profissaoCtrl.clear();
                                    _conjugeCtrl.clear();
                                    _filiacaoPaiCtrl.clear();
                                    _filiacaoMaeCtrl.clear();
                                    _birthDate = null;
                                    _birthDateCtrl.clear();
                                    _photoFile = null;
                                    _photoBytes = null;
                                  });
                                },
                                icon: const Icon(Icons.person_add_rounded,
                                    size: 20),
                                label: const Text('Voltar ao início'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  if (kIsWeb) {
                                    VersionService.reloadWeb();
                                  } else {
                                    Navigator.maybePop(context);
                                  }
                                },
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 20),
                                label: const Text('Recarregar'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/igreja/login',
                                  (_) => false,
                                ),
                                icon: const Icon(Icons.login_rounded, size: 20),
                                label: const Text('Ir para login da igreja'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final initial = _birthDate ??
        memberSignupParseBirthDateBr(_birthDateCtrl.text.trim()) ??
        DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 100),
      lastDate: DateTime(DateTime.now().year),
      initialDate: initial,
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _birthDateCtrl.text = memberSignupFormatBirthDateBr(picked);
      });
    }
  }

  Future<void> _pickPhoto({bool fromCamera = false}) async {
    final authUser = FirebaseAuth.instance.currentUser;
    final isPublicVisitor = authUser == null || authUser.isAnonymous;
    final hit = fromCamera
        ? await MemberProfilePhotoPickService.pickFromCamera(
            context,
            requireAuth: !isPublicVisitor,
          )
        : await MemberProfilePhotoPickService.pickForMemberEdit(
            context,
            requireAuth: !isPublicVisitor,
          );
    if (hit == null || !mounted) return;
    setState(() {
      _photoFile = XFile.fromData(hit.bytes, name: hit.displayName);
      _photoBytes = hit.bytes;
    });
  }

  /// `igrejas/{tenant}/membros/{memberDocId}/foto_perfil.jpg` — path fixo (1 foto).
  Future<({String url, String storagePath})> _uploadPhoto({
    required String tenantId,
    required String memberDocId,
    XFile? file,
    Uint8List? rawBytes,
  }) async {
    final raw = rawBytes ??
        (file != null ? await file.readAsBytes() : Uint8List.fromList(const []));
    if (raw.isEmpty) {
      throw Exception('Foto vazia — selecione outra imagem.');
    }
    final mid = memberDocId.trim().isEmpty
        ? 'membro_${DateTime.now().millisecondsSinceEpoch}'
        : memberDocId.trim();
    final isPublicVisitor = FirebaseAuth.instance.currentUser == null ||
        FirebaseAuth.instance.currentUser!.isAnonymous;
    return MemberProfilePhotoSaveService.uploadStorageOnlyControleTotal(
      tenantId: tenantId.trim(),
      memberDocId: mid,
      rawBytes: raw,
      requireAuth: !isPublicVisitor,
    );
  }

  /// Avatar automático quando o membro não envia foto.
  String _buildAutoAvatarUrl(String memberDocId) {
    final name =
        _nameCtrl.text.trim().isEmpty ? 'Membro' : _nameCtrl.text.trim();
    final seed = _onlyDigits(_cpfCtrl.text).isNotEmpty
        ? _onlyDigits(_cpfCtrl.text)
        : memberDocId;
    return 'https://api.dicebear.com/7.x/initials/png?seed=${Uri.encodeComponent('$name-$seed')}&backgroundColor=e2e8f0,bae6fd,c7d2fe,d9f99d&fontWeight=700';
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_validatePhotoRequired()) return;
    if (!_formKey.currentState!.validate()) return;
    final birthParsed = memberSignupParseBirthDateBr(_birthDateCtrl.text.trim());
    if (birthParsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe a data de nascimento (DD/MM/AAAA).')),
      );
      return;
    }
    final today = DateTime.now();
    if (birthParsed
        .isAfter(DateTime(today.year, today.month, today.day))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data de nascimento inválida.')),
      );
      return;
    }
    if (_tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Igreja nao encontrada.')),
      );
      return;
    }
    if (_tenantBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O cadastro público desta igreja está temporariamente indisponível por assinatura suspensa.',
          ),
        ),
      );
      return;
    }

    if (_tenantId == null) return;
    // Web: sessão anónima para Storage — não tem leitura em `membros` nem em `subscriptions`.
    // Visitante real = sem conta ou só anónimo; aí não se pode correr checkLimit nem queries de duplicado.
    final authUser = FirebaseAuth.instance.currentUser;
    final isPublicVisitor = authUser == null || authUser.isAnonymous;
    // Limite do plano: só para utilizador com login real (gestor a testar o link, etc.).
    if (!isPublicVisitor) {
      final limitService = MembersLimitService();
      final limitResult = await limitService.checkLimit(_tenantId!);
      if (limitResult.isBlocked) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Limite do plano'),
            content: Text(limitResult.blockedDialogMessage),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendi')),
              if (!IosPaymentsGate.shouldHidePayments)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RenewPlanPage()));
                  },
                  child: const Text('Ver planos'),
                ),
            ],
          ),
        );
        return;
      }
    }

    if (_tenantId == null || _tenantId!.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Igreja não identificada. Recarregue a página ou use o link correto da igreja.')),
        );
      return;
    }
    if (_tenantBlocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cadastro temporariamente indisponível para esta igreja.'),
          ),
        );
      }
      return;
    }
    final cpfDigits = _onlyDigits(_cpfCtrl.text);
    final emailNorm = _emailCtrl.text.trim().toLowerCase();
    final op = ChurchRepository.churchId(_tenantId!);
    final col =         ChurchUiCollections.membros(op);
    final editingDocId = _editModeAfterSubmit ? _lastSubmittedDocId : null;

    // Duplicado: precisa de leitura em `membros` (regras só para tenant). Visitantes não têm — evitar permission-denied.
    if (!isPublicVisitor) {
      if (cpfDigits.length == 11) {
        final byCpf = await col.where('CPF', isEqualTo: cpfDigits).limit(2).get();
        final byCpfLower =
            await col.where('cpf', isEqualTo: cpfDigits).limit(2).get();
        final conflictCpf =
            byCpf.docs.where((d) => d.id != editingDocId).isNotEmpty ||
                byCpfLower.docs.where((d) => d.id != editingDocId).isNotEmpty;
        if (conflictCpf) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Já existe um cadastro com este CPF nesta igreja.')),
          );
          return;
        }
      }
      if (emailNorm.isNotEmpty) {
        final byEmail =
            await col.where('EMAIL', isEqualTo: emailNorm).limit(2).get();
        final byEmailLower =
            await col.where('email', isEqualTo: emailNorm).limit(2).get();
        final conflictEmail =
            byEmail.docs.where((d) => d.id != editingDocId).isNotEmpty ||
                byEmailLower.docs.where((d) => d.id != editingDocId).isNotEmpty;
        if (conflictEmail) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Já existe um cadastro com este e-mail nesta igreja.')),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);

    try {
      if (isPublicVisitor) {
        await PublicSiteMediaAuth.ensurePublicVisitorMediaAccess();
      }
      if (_photoBytes != null && _photoBytes!.isNotEmpty) {
        await DirectStorageUrlPublish.ensureReady(requireAuth: !isPublicVisitor);
      }
      final ref = editingDocId != null
          ? col.doc(editingDocId)
          : (cpfDigits.length == 11 ? col.doc(cpfDigits) : col.doc());
      String? photoStoragePathField;
      String? photoUrlField;
      if (_photoBytes != null && _photoBytes!.isNotEmpty) {
        final uploaded = await _uploadPhoto(
          tenantId: _tenantId!,
          memberDocId: ref.id,
          file: _photoFile,
          rawBytes: _photoBytes,
        );
        photoStoragePathField = uploaded.storagePath;
        photoUrlField = sanitizeImageUrl(uploaded.url);
      }
      final age = _calcAge(birthParsed) ?? 0;
      final ageRange = _ageRange(age);

      // Path canónico: igrejas/{churchId}/membros — sem alias/tenantId legados.
      final data = {
        'MEMBER_ID': ref.id,
        'CREATED_BY_CPF': cpfDigits.isNotEmpty ? cpfDigits : ref.id,
        'churchId': _tenantId,
        'NOME_COMPLETO': _nameCtrl.text.trim(),
        'EMAIL': _emailCtrl.text.trim(),
        'DATA_NASCIMENTO': Timestamp.fromDate(birthParsed),
        'TELEFONES': _phoneCtrl.text.trim(),
        'SEXO': _sexo,
        'FAIXA_ETARIA': ageRange,
        'IDADE': age,
        'ENDERECO': _enderecoCtrl.text.trim(),
        'QUADRA_LOTE_NUMERO': _quadraLoteNumeroCtrl.text.trim(),
        'CEP': _cepCtrl.text.trim(),
        'CIDADE': _cityCtrl.text.trim(),
        'BAIRRO': _bairroCtrl.text.trim(),
        'ESTADO': _estadoCtrl.text.trim(),
        'CPF': cpfDigits,
        'ESTADO_CIVIL': _estadoCivilCtrl.text.trim(),
        'ESCOLARIDADE': _escolaridadeCtrl.text.trim(),
        'PROFISSAO': _profissaoCtrl.text.trim(),
        'NOME_CONJUGE': _conjugeCtrl.text.trim(),
        'DEPARTAMENTOS': <String>[],
        if (photoStoragePathField != null &&
            photoUrlField != null &&
            photoStoragePathField.isNotEmpty &&
            photoUrlField.isNotEmpty)
          ...ChurchCanonicalMediaPublish.memberProfileFields(
            downloadUrl: photoUrlField,
            storagePath: photoStoragePathField,
            thumbStoragePath: photoStoragePathField,
          ),
        'PUBLIC_SIGNUP': true,
        'STATUS': 'pendente',
        'status': 'pendente',
        'role': 'membro',
        'CARGO': 'Membro',
        'FUNCAO': 'Membro',
        'FUNCOES': <String>['membro'],
        'CRIADO_EM': FieldValue.serverTimestamp(),
        'FILIACAO_PAI': _filiacaoPaiCtrl.text.trim(),
        'FILIACAO_MAE': _filiacaoMaeCtrl.text.trim(),
        'FILIACAO': _buildFiliacaoLegado(
            _filiacaoPaiCtrl.text.trim(), _filiacaoMaeCtrl.text.trim()),
      };
      if (_editModeAfterSubmit) {
        final updateData = Map<String, dynamic>.from(data);
        updateData.remove('CRIADO_EM');
        await ref.update(updateData);
      } else {
        if (!isPublicVisitor) {
          final codigoMembro =
              await MemberCodigoService.allocateNext(_tenantId!);
          data.addAll(MemberCodigoService.fieldsForFirestore(codigoMembro));
        }
        if (kIsWeb && isPublicVisitor) {
          await ChurchFunctionsService.publicMemberSignup(
            churchId: _tenantId!.trim(),
            docId: ref.id,
            data: AdminFeedFirestoreBridge.encodeMap(data),
          );
        } else if (kIsWeb) {
          await AdminFeedFirestoreBridge.upsertTenantDoc(
            churchId: _tenantId!.trim(),
            collection: 'membros',
            docId: ref.id,
            data: data,
            isNewDoc: true,
            directWrite: () => ref.set(data),
          );
        } else {
          await ref.set(data);
        }
        if (_tenantId != null && _tenantId!.trim().isNotEmpty) {
          unawaited(
            DashboardStatsCounterService.onMemberCreated(_tenantId!.trim())
                .catchError((_) {}),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _submittedSuccess = true;
        _submittedMemberName = _nameCtrl.text.trim();
        _lastSubmittedDocId = ref.id;
      });
    } catch (e) {
      await YahwehModuleMediaGate.recoverNoAppAfterPublishError(
        e,
        requireAuth: !(FirebaseAuth.instance.currentUser == null ||
            FirebaseAuth.instance.currentUser!.isAnonymous),
      );
      if (!mounted) return;
      final u = FirebaseAuth.instance.currentUser;
      final msg = e.toString().contains('permission-denied') &&
              (u == null || u.isAnonymous)
          ? 'Não foi possível gravar. Verifique os dados e tente novamente, ou entre em contato com a igreja.'
          : 'Erro ao cadastrar: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snackWizard(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  bool _validateWizardStep0() {
    if (_nameCtrl.text.trim().isEmpty) {
      _snackWizard('Preencha o nome completo.');
      return false;
    }
    if (_onlyDigits(_cpfCtrl.text).length != 11) {
      _snackWizard('CPF deve ter 11 dígitos.');
      return false;
    }
    final birthParsed = memberSignupParseBirthDateBr(_birthDateCtrl.text.trim());
    if (birthParsed == null) {
      _snackWizard('Informe a data de nascimento (DD/MM/AAAA).');
      return false;
    }
    final today = DateTime.now();
    if (birthParsed
        .isAfter(DateTime(today.year, today.month, today.day))) {
      _snackWizard('Data de nascimento inválida.');
      return false;
    }
    _birthDate = birthParsed;
    final e = _reqEmail(_emailCtrl.text);
    if (e != null) {
      _snackWizard(e);
      return false;
    }
    return true;
  }

  bool _validateWizardStep1() => true;

  bool _validatePhotoRequired() {
    if (_photoBytes == null || _photoBytes!.isEmpty) {
      _snackWizard('Envie a foto de perfil (campo obrigatório).');
      return false;
    }
    return true;
  }

  void _onWizardNext() {
    if (_signupStep == 0) {
      if (!_validateWizardStep0()) return;
    } else if (_signupStep == 1) {
      if (!_validateWizardStep1()) return;
    }
    setState(() => _signupStep = (_signupStep + 1).clamp(0, 2));
  }

  /// Faixa superior compacta: logo à esquerda, nome e formulário discretos.
  Widget _buildPublicChurchHeader({
    required bool loading,
    bool churchNotFound = false,
  }) {
    final Widget logoSlot = loading
        ? Skeletonizer(
            enabled: true,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          )
        : churchNotFound
            ? Icon(Icons.church_rounded,
                size: 30, color: Colors.grey.shade400)
            : _publicSignupChurchLogo(maxWidth: 40, maxHeight: 40);
    return PublicMemberSignupCompactHeader(
      loading: loading,
      churchNotFound: churchNotFound,
      tenantName: _tenantName,
      formSubtitle: 'Formulário de cadastro',
      endereco: _tenantEndereco,
      logoSlot: logoSlot,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tenantId == null && !_loading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: ChurchPublicSiteScaffoldBackground(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPublicChurchHeader(
              loading: false,
              churchNotFound: true,
            ),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Verifique o link ou fale com a igreja.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      );
    }

    if (_submittedSuccess) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ChurchPublicSiteScaffoldBackground(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPublicChurchHeader(loading: _loading),
          Expanded(
            child: Padding(
              padding: ThemeCleanPremium.pagePadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: AbsorbPointer(
                    absorbing: _loading || _saving,
                    child: Opacity(
                      opacity: _loading ? 0.72 : 1,
                      child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                    if (_loading) ...[
                    const LinearProgressIndicator(
                      minHeight: 3,
                      color: Color(0xFF0D9488),
                      backgroundColor: Color(0x220D9488),
                    ),
                    const SizedBox(height: 12),
                    ],
                    MemberSignupWizardProgress(step: _signupStep),
                    const SizedBox(height: 14),
                    const MemberSignupRequiredFieldsAlert(),
                    const SizedBox(height: 16),
                    YahwehWisdomSectionCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    if (_signupStep == 0) ...[
                    Text(
                      'Preencha os campos obrigatórios (*) para entrar no cadastro da igreja.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    MemberSignupSectionTitle(
                      title: 'Dados pessoais',
                      accentColor: _signupStepAccent,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _signInput(
                          label: 'Nome completo',
                          icon: Icons.person_rounded,
                          required: true),
                      validator: _reqName,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoMaeCtrl,
                      decoration: _signInput(
                          label: 'Filiação (mãe)',
                          icon: Icons.family_restroom_rounded),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoPaiCtrl,
                      decoration: _signInput(
                          label: 'Filiação (pai)',
                          icon: Icons.family_restroom_rounded),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cpfCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                              TextInputFormatter.withFunction(
                                  (oldValue, newValue) {
                                final masked = memberSignupFormatCpfMask(newValue.text);
                                return TextEditingValue(
                                  text: masked,
                                  selection: TextSelection.collapsed(
                                      offset: masked.length),
                                );
                              }),
                            ],
                            decoration: _signInput(
                                label: 'CPF',
                                icon: Icons.badge_rounded,
                                required: true),
                            validator: (v) {
                              final msg = _req(v);
                              if (msg != null) return msg;
                              final digits = _onlyDigits(v!);
                              if (digits.length != 11) return 'CPF invalido';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _birthDateCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              MemberSignupBirthDateInputFormatter(),
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: _signInput(
                              label: 'Data de nascimento',
                              icon: Icons.cake_rounded,
                              hint: 'DD/MM/AAAA',
                              required: true,
                              suffixIcon: IconButton(
                                icon: Icon(Icons.calendar_month_rounded,
                                    color: ThemeCleanPremium.primary),
                                tooltip: 'Calendário',
                                onPressed: _pickBirthDate,
                              ),
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'Campo obrigatório';
                              final p = memberSignupParseBirthDateBr(t);
                              if (p == null) return 'Use DD/MM/AAAA';
                              final now = DateTime.now();
                              if (p.isAfter(
                                  DateTime(now.year, now.month, now.day))) {
                                return 'Data inválida';
                              }
                              return null;
                            },
                            onChanged: (v) {
                              final p = memberSignupParseBirthDateBr(v);
                              if (p != null) {
                                setState(() => _birthDate = p);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sexo,
                            decoration: _signInput(
                                label: 'Sexo', icon: Icons.wc_rounded),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Masculino', child: Text('Masculino')),
                              DropdownMenuItem(
                                  value: 'Feminino', child: Text('Feminino')),
                              DropdownMenuItem(
                                  value: 'Outro', child: Text('Outro')),
                            ],
                            onChanged: (v) =>
                                setState(() => _sexo = v ?? 'Masculino'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                              TextInputFormatter.withFunction(
                                  (oldValue, newValue) {
                                final masked = memberSignupFormatPhoneMask(newValue.text);
                                return TextEditingValue(
                                  text: masked,
                                  selection: TextSelection.collapsed(
                                      offset: masked.length),
                                );
                              }),
                            ],
                            decoration: _signInput(
                                label: 'Telefone',
                                icon: Icons.phone_rounded,
                                hint: 'Opcional'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _signInput(
                          label: 'E-mail',
                          icon: Icons.alternate_email_rounded,
                          required: true),
                      validator: _reqEmail,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: MemberSignupPremiumUi.escolaridadeOptions
                              .contains(_escolaridadeCtrl.text.trim())
                          ? _escolaridadeCtrl.text.trim()
                          : null,
                      decoration: _signInput(
                          label: 'Escolaridade',
                          icon: Icons.school_rounded),
                      hint: const Text('Opcional'),
                      isExpanded: true,
                      items: MemberSignupPremiumUi.escolaridadeOptions
                          .map((e) => DropdownMenuItem<String>(
                              value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _escolaridadeCtrl.text = (v ?? '').trim()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _profissaoCtrl,
                      decoration: _signInput(
                          label: 'Profissão',
                          icon: Icons.work_outline_rounded),
                    ),
                    ],
                    if (_signupStep == 1) ...[
                    MemberSignupSectionTitle(
                      title: 'Endereço (opcional)',
                      accentColor: _signupStepAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Digite o CEP e saia do campo para preencher os dados automaticamente.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cepCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      decoration: _signInput(
                        label: 'CEP',
                        icon: Icons.pin_drop_rounded,
                        hint: '00000-000',
                        counterText: '',
                        suffixIcon: _loadingCep
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      onChanged: (v) {
                        if (_onlyDigits(v).length == 8) _buscarCep();
                      },
                      onEditingComplete: _buscarCep,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _enderecoCtrl,
                      decoration: _signInput(
                        label: 'Logradouro (rua, avenida)',
                        icon: Icons.home_rounded,
                        hint: 'Opcional',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quadraLoteNumeroCtrl,
                      decoration: _signInput(
                        label: 'Quadra, Lote e Número',
                        icon: Icons.tag_rounded,
                        hint: 'Qd 1, Lt 5, Nº 123',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bairroCtrl,
                      decoration: _signInput(
                          label: 'Bairro',
                          icon: Icons.location_city_rounded,
                          hint: 'Opcional'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cityCtrl,
                      decoration: _signInput(
                          label: 'Cidade', icon: Icons.apartment_rounded),
                      onChanged: _searchCitySuggestions,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _ufs.contains(_estadoCtrl.text.trim())
                          ? _estadoCtrl.text.trim()
                          : null,
                      decoration: _signInput(
                          label: 'Estado (UF)', icon: Icons.map_rounded),
                      isExpanded: true,
                      items: _ufs
                          .map((uf) => DropdownMenuItem(
                              value: uf, child: Text(uf)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _estadoCtrl.text = v;
                        setState(() {});
                      },
                      onSaved: (v) {
                        if (v != null) _estadoCtrl.text = v;
                      },
                    ),
                    if (_loadingCitySuggestions ||
                        _citySuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: _loadingCitySuggestions
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                    SizedBox(width: 10),
                                    Text('Buscando cidades...'),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _citySuggestions.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final s = _citySuggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                        Icons.location_city_rounded,
                                        size: 20),
                                    title: Text(s.city),
                                    subtitle: Text(s.state),
                                    onTap: () => _applyCitySuggestion(s),
                                  );
                                },
                              ),
                      ),
                    ],
                    ],
                    if (_signupStep == 2) ...[
                    MemberSignupSectionTitle(
                      title: 'Família (opcional)',
                      accentColor: _signupStepAccent,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: MemberSignupPremiumUi.estadoCivilOptions
                              .contains(_estadoCivilCtrl.text.trim())
                          ? _estadoCivilCtrl.text.trim()
                          : null,
                      decoration: _signInput(
                          label: 'Estado civil',
                          icon: Icons.favorite_outline_rounded),
                      hint: const Text('Opcional'),
                      isExpanded: true,
                      items: MemberSignupPremiumUi.estadoCivilOptions
                          .map((e) => DropdownMenuItem<String>(
                              value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _estadoCivilCtrl.text = (v ?? '').trim()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _conjugeCtrl,
                      decoration: _signInput(
                          label: 'Nome conjuge',
                          icon: Icons.people_alt_rounded),
                    ),
                    const SizedBox(height: 16),
                    MemberSignupPhotoRequiredCard(
                      hasPhoto:
                          _photoBytes != null && _photoBytes!.isNotEmpty,
                      onGallery: () => _pickPhoto(fromCamera: false),
                      onCamera: () => _pickPhoto(fromCamera: true),
                      photoPreview: CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFF1F5F9),
                        backgroundImage: _photoBytes == null
                            ? null
                            : MemoryImage(_photoBytes!),
                        child: _photoBytes == null
                            ? Icon(Icons.person_rounded,
                                size: 36, color: Colors.grey.shade400)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _signupStep = 1),
                          child: const Text('Voltar'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ThemeCleanPremium.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle),
                              label: Text(
                                _saving
                                    ? 'Enviando...'
                                    : 'Finalizar cadastro',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ],
                    if (_signupStep < 2) ...[
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_signupStep > 0)
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => _signupStep--),
                              child: const Text('Voltar'),
                            ),
                          if (_signupStep > 0) const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _onWizardNext,
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                _signupStep == 0
                                    ? 'Continuar (endereço opcional)'
                                    : 'Continuar para foto *',
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                        ],
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
        ],
        ),
      ),
    );
  }
}

class PublicSignupStatusPage extends StatelessWidget {
  final String slug;
  final String protocolo;
  const PublicSignupStatusPage({
    super.key,
    required this.slug,
    required this.protocolo,
  });

  Future<({
    String churchName,
    String? nome,
    String? statusRaw,
    String? error,
  })> _loadStatus() async {
    final slugTrim = slug.trim();
    final protocol = protocolo.trim();
    if (slugTrim.isEmpty || protocol.isEmpty) {
      return (
        churchName: 'Igreja',
        nome: null,
        statusRaw: null,
        error: 'Link inválido.',
      );
    }

    PublicChurchResolved? resolved = PublicChurchSlugResolver.peek(slugTrim);
    resolved ??= await PublicChurchSlugResolver.resolveFast(slugTrim)
        .timeout(const Duration(seconds: 6), onTimeout: () => null);

    try {
      final cf = await ChurchFunctionsService.publicSignupStatus(
        slug: slugTrim,
        churchId: resolved?.churchId,
        protocolo: protocol,
      );
      if (!cf.found || !cf.ok) {
        return (
          churchName: cf.churchName,
          nome: null,
          statusRaw: null,
          error: cf.error ?? 'Cadastro não localizado para o protocolo informado.',
        );
      }
      return (
        churchName: cf.churchName,
        nome: cf.nome,
        statusRaw: cf.status,
        error: null,
      );
    } catch (e) {
      return (
        churchName: resolved != null
            ? (resolved.profile['name'] ?? resolved.profile['nome'] ?? 'Igreja')
                .toString()
            : 'Igreja',
        nome: null,
        statusRaw: null,
        error: 'Não foi possível consultar o status. Tente novamente.',
      );
    }
  }

  static ({String label, Color color}) _statusUi(String raw) {
    final s = raw.toLowerCase().trim();
    if (s == 'ativo' || s == 'aprovado') {
      return (label: 'Aprovado', color: const Color(0xFF16A34A));
    }
    if (s == 'reprovado' || s == 'negado') {
      return (label: 'Não aprovado', color: const Color(0xFFDC2626));
    }
    return (label: 'Em análise', color: const Color(0xFFD97706));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Acompanhar cadastro',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFE2E8F0),
          ),
        ),
      ),
      body: ChurchPublicSiteScaffoldBackground(
        child: FutureBuilder<
            ({
              String churchName,
              String? nome,
              String? statusRaw,
              String? error,
            })>(
          future: _loadStatus(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const ChurchWisdomPublicLoading(
                message: 'Consultando protocolo…',
              );
            }
            final data = snap.data!;
            if (data.error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ChurchWisdomPublicSurfaceCard(
                    child: Text(
                      data.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              );
            }
            final nome = data.nome ?? 'Membro';
            final status = _statusUi(data.statusRaw ?? 'pendente');
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ChurchWisdomPublicSurfaceCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          data.churchName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          nome,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ChurchWisdomPublicStatusBadge(
                          label: 'Status: ${status.label}',
                          color: status.color,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Protocolo: $protocolo',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
