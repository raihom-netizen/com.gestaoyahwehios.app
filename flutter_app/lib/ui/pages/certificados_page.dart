import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show imageCache;
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/pdf/cert_pdf_worker.dart'
    show
        CertPdfGalaBatchMemberSlice,
        CertPdfPipelineParams,
        CertPdfPipelineSignatory,
        resolveCertificatePdfShared,
        runCertificateGalaLuxoBatchPdfPipeline,
        runCertificatePdfPipeline,
        warmCertificatePdfFontAssets;
import 'package:gestao_yahweh/certificates/certificate_visual_template.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/certificado_consulta_url.dart';
import 'package:gestao_yahweh/services/certificate_emitido_service.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gestao_yahweh/utils/carteirinha_zip_export.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableChurchLogo;
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        SafeCircleAvatarImage,
        SafeNetworkImage,
        FreshFirebaseStorageImage,
        churchTenantLogoUrl,
        churchTenantLogoUrlCandidates,
        firebaseStorageMediaUrlLooksLike,
        imageUrlFromMap,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart'
    show avatarColorForMember;
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/cert_zip_opener.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Templates de Certificados ──────────────────────────────────────────────
class _CertTemplate {
  final String id;
  final String nome;
  final IconData icon;
  final Color cor;
  final String textoModelo;
  /// Versículo ou frase curta (layout tradicional, premium gold, moderno).
  final String subtituloPadrao;

  const _CertTemplate({
    required this.id,
    required this.nome,
    required this.icon,
    required this.cor,
    required this.textoModelo,
    this.subtituloPadrao = '',
  });
}

const _templates = [
  _CertTemplate(
    id: 'batismo',
    nome: 'Certificado de Batismo',
    icon: Icons.water_drop_rounded,
    cor: Color(0xFF2563EB),
    textoModelo:
        'Certificamos que {NOME}, portador(a) do CPF {CPF}, foi batizado(a) nas águas '
        'conforme a ordenança bíblica de Mateus 28:19, nesta igreja, na data de {DATA_CERTIFICADO}.\n\n'
        'Que o Senhor abençoe e guarde os passos deste(a) irmão(ã) em sua caminhada cristã.',
    subtituloPadrao:
        'Quem crer e for batizado será salvo (Marcos 16:16)',
  ),
  _CertTemplate(
    id: 'membro',
    nome: 'Certificado de Membro',
    icon: Icons.people_rounded,
    cor: Color(0xFF16A34A),
    textoModelo:
        'Por meio deste instrumento, certificamos que {NOME}, identificado(a) pelo CPF {CPF}, '
        'integra o rol de membros desta igreja em plena comunhão e participação ativa.\n\n'
        'O presente documento é emitido em {DATA_CERTIFICADO}, para comprovação junto a terceiros, '
        'mediante a fé e o testemunho desta comunidade.',
  ),
  _CertTemplate(
    id: 'apresentacao',
    nome: 'Certificado de Apresentação',
    icon: Icons.child_care_rounded,
    cor: Color(0xFFD97706),
    textoModelo:
        'Certificamos que a criança {NOME} foi apresentada ao Senhor nesta igreja, '
        'em cerimônia realizada na data de {DATA_CERTIFICADO}, '
        'conforme o exemplo bíblico de Lucas 2:22.\n\n'
        'Que Deus abençoe e proteja esta criança e sua família.',
  ),
  _CertTemplate(
    id: 'casamento',
    nome: 'Certificado de Casamento',
    icon: Icons.favorite_rounded,
    cor: Color(0xFFDB2777),
    textoModelo:
        'Certificamos que {NOME} contraiu matrimônio nesta igreja na data de {DATA_CERTIFICADO}, '
        'tendo a cerimônia sido celebrada conforme os preceitos cristãos.\n\n'
        'Que o Senhor abençoe este lar com amor, paz e fidelidade.',
  ),
  _CertTemplate(
    id: 'participacao',
    nome: 'Certificado de Participação',
    icon: Icons.emoji_events_rounded,
    cor: Color(0xFF7C3AED),
    textoModelo:
        'Certificamos que {NOME} participou do evento/curso realizado por esta igreja '
        'na data de {DATA_CERTIFICADO}.\n\n'
        'Agradecemos sua presença e dedicação.',
  ),
  _CertTemplate(
    id: 'lideranca',
    nome: 'Certificado de Liderança',
    icon: Icons.stars_rounded,
    cor: Color(0xFF0891B2),
    textoModelo:
        'Certificamos que {NOME}, portador(a) do CPF {CPF}, exerce a função de líder '
        'nesta igreja, contribuindo para o crescimento espiritual da comunidade.\n\n'
        'Este certificado é emitido em {DATA_CERTIFICADO} como reconhecimento por sua dedicação.',
  ),
  _CertTemplate(
    id: 'conclusao_curso',
    nome: 'Certificado de Conclusão de Curso',
    icon: Icons.school_rounded,
    cor: Color(0xFFEA580C),
    textoModelo:
        'Certificamos que {NOME} concluiu com aproveitamento o curso ministrado por esta igreja '
        'na data de {DATA_CERTIFICADO}.\n\n'
        'Parabéns pela dedicação e empenho!',
  ),
  _CertTemplate(
    id: 'ordenacao',
    nome: 'Certificado de Ordenação',
    icon: Icons.church_rounded,
    cor: Color(0xFF4338CA),
    textoModelo:
        'Certificamos que {NOME}, portador(a) do CPF {CPF}, foi ordenado(a) ao ministério '
        'nesta igreja na data de {DATA_CERTIFICADO}, após cumprir todos os requisitos '
        'estabelecidos pela liderança eclesiástica.\n\n'
        'Que o Senhor o(a) capacite e fortaleça no exercício do ministério.',
  ),
  _CertTemplate(
    id: 'reconhecimento',
    nome: 'Certificado de Reconhecimento',
    icon: Icons.thumb_up_rounded,
    cor: Color(0xFF059669),
    textoModelo:
        'Certificamos que {NOME} recebe o presente reconhecimento por relevantes serviços '
        'prestados a esta igreja, em {DATA_CERTIFICADO}.\n\n'
        'Agradecemos sua dedicação e parceria.',
  ),
  _CertTemplate(
    id: 'honra_merito',
    nome: 'Honra ao Mérito',
    icon: Icons.military_tech_rounded,
    cor: Color(0xFFB45309),
    textoModelo:
        'A igreja outorga a {NOME} a Honra ao Mérito em {DATA_CERTIFICADO}, '
        'em reconhecimento ao seu destacado empenho e contribuição.\n\n'
        'Que o Senhor continue abençoando seus passos.',
  ),
];

class _CertLayoutOption {
  final String id;
  final String nome;
  final String descricao;
  const _CertLayoutOption({
    required this.id,
    required this.nome,
    required this.descricao,
  });
}

/// Único layout de PDF disponível para todos os tipos de certificado.
const String _certPdfLayoutId = 'gala_luxo';

const _certLayoutOptions = [
  _CertLayoutOption(
    id: _certPdfLayoutId,
    nome: 'Gala Luxo (paisagem)',
    descricao:
        'A4 horizontal: logo e nome da igreja centralizados, moldura premium, QR de autenticidade e data no canto inferior esquerdo.',
  ),
];

class _CertFontStyleOption {
  final String id;
  final String nome;
  final String descricao;
  const _CertFontStyleOption({
    required this.id,
    required this.nome,
    required this.descricao,
  });
}

const _certFontStyleOptions = [
  _CertFontStyleOption(
    id: 'moderna',
    nome: 'Moderna (Clean)',
    descricao: 'Leitura limpa e equilibrada.',
  ),
  _CertFontStyleOption(
    id: 'classica',
    nome: 'Clássica (Manuscrita)',
    descricao: 'Destaque elegante no nome do membro.',
  ),
  _CertFontStyleOption(
    id: 'gotica',
    nome: 'Gótica (Antiga)',
    descricao:
        'Visual refinado no PDF: título legível e nome em script elegante (sem blackletter ilegível).',
  ),
];

/// Cores predefinidas para a igreja escolher nos certificados.
const _certificadoCores = [
  Color(0xFF2563EB), // azul
  Color(0xFF16A34A), // verde
  Color(0xFFD97706), // âmbar
  Color(0xFFDB2777), // rosa
  Color(0xFF7C3AED), // violeta
  Color(0xFF0891B2), // ciano
  Color(0xFF4338CA), // índigo
  Color(0xFFB45309), // dourado
  Color(0xFF059669), // esmeralda
  Color(0xFFDC2626), // vermelho
];

// ─── Página Principal ────────────────────────────────────────────────────────
class CertificadosPage extends StatefulWidget {
  final String tenantId;
  final String role;

  const CertificadosPage(
      {super.key, required this.tenantId, required this.role});

  @override
  State<CertificadosPage> createState() => _CertificadosPageState();
}

class _CertificadosPageState extends State<CertificadosPage> {
  String _searchQuery = '';
  bool _batchMode = false;
  /// Preferência ao gerar lote local: um PDF vs ZIP (lembrada entre sessões no mesmo ecrã).
  bool _batchPreferSinglePdf = true;
  final Set<String> _batchMemberIds = {};
  Map<String, dynamic>? _tenantData;
  Map<String, dynamic>? _certConfig;
  bool _tenantLoaded = false;
  late Future<QuerySnapshot<Map<String, dynamic>>> _membersFuture;

  DocumentReference<Map<String, dynamic>> get _certConfigDoc =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('certificados');

  Future<QuerySnapshot<Map<String, dynamic>>> _loadMembers() async {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros')
        .get();
  }

  void _refreshMembers() {
    setState(() {
      _membersFuture = _loadMembers();
    });
  }

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _membersFuture = _loadMembers();
    _loadTenant();
    _loadCertConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      warmCertificatePdfFontAssets();
    });
  }

  Future<void> _loadCertConfig() async {
    try {
      final snap = await _certConfigDoc.get();
      if (mounted) setState(() => _certConfig = snap.data());
    } catch (_) {}
  }

  Future<void> _loadTenant() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .get();
      if (mounted)
        setState(() {
          _tenantData = snap.data();
          _tenantLoaded = true;
        });
    } catch (_) {
      if (mounted) setState(() => _tenantLoaded = true);
    }
  }

  String get _nomeIgreja =>
      (_tenantData?['name'] ?? _tenantData?['nome'] ?? 'Igreja').toString();

  /// Logo do cadastro da igreja (prioriza `logoProcessedUrl`, igual ao site público).
  String get _logoUrl {
    final data = _tenantData;
    if (data == null) return '';
    final url = churchTenantLogoUrl(data).trim();
    if (!isValidImageUrl(url)) return '';
    return url;
  }

  /// URLs para pré-visualização/PDF: logo específica dos certificados (se houver)
  /// e, em seguida, todas as candidatas do tenant (retry se uma URL falhar).
  List<String> get _logoCertCandidateUrls {
    final out = <String>[];
    void push(String? s) {
      final raw = (s ?? '').trim();
      if (raw.isEmpty) return;
      final sanitized = sanitizeImageUrl(raw);
      final candidate = sanitized.isNotEmpty ? sanitized : raw;
      if (!out.contains(candidate)) out.add(candidate);
    }
    final custom = Map<String, dynamic>.from(_certConfig ?? const {});
    // Caminho no Storage primeiro (getData no SDK costuma ser mais fiável na web que URL com token).
    push((custom['logoPath'] ?? custom['storagePath'] ?? '').toString());
    final dedicada = (custom['logoCertificado'] ?? '').toString().trim();
    if (dedicada.isNotEmpty) push(dedicada);
    final customUrl = (custom['logoUrl'] ?? '').toString().trim();
    if (customUrl.isNotEmpty) push(customUrl);
    final customVariants = custom['logoVariants'];
    if (customVariants is Map) {
      for (final v in customVariants.values) {
        if (v is Map) {
          final p = (v['path'] ?? v['storagePath'] ?? '').toString().trim();
          if (p.isNotEmpty) push(p);
          push((v['url'] ?? v['downloadUrl'] ?? '').toString());
        } else {
          push(v?.toString());
        }
      }
    }
    if (_tenantData != null) {
      push(ChurchStorageLayout.churchIdentityLogoPath(widget.tenantId));
      push(ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(widget.tenantId));
      for (final u in churchTenantLogoUrlCandidates(_tenantData)) {
        push(u);
      }
      for (final key in [
        'logoPath',
        'logo_path',
        'storagePath',
        'storage_path',
        'brandLogoPath',
        'churchLogoPath',
      ]) {
        push(_tenantData?[key]?.toString());
      }
      // Fallback extra para dados de gestor/cadastro legado.
      final gestorLogo = (_tenantData?['gestorLogoUrl'] ??
              _tenantData?['gestor_logo'] ??
              _tenantData?['logo'] ??
              '')
          .toString()
          .trim();
      push(gestorLogo);
    }
    return out;
  }

  /// Primeira URL exibida no editor (config ou melhor candidata do cadastro).
  String get _logoCert =>
      _logoCertCandidateUrls.isNotEmpty ? _logoCertCandidateUrls.first : '';

  String _layoutForTemplate(_CertTemplate t) => _certPdfLayoutId;

  String _fontStyleForTemplate(_CertTemplate t) {
    final data = _templateConfig(t);
    final id = (data?['fontStyleId'] ?? '').toString().trim();
    if (_certFontStyleOptions.any((e) => e.id == id)) return id;
    return 'moderna';
  }

  /// Dados do template na config (compatível: apresentacao lê 'dedicacao' se existir).
  Map<String, dynamic>? _templateConfig(_CertTemplate t) {
    final templates = _certConfig?['templates'];
    if (templates is! Map) return null;
    var data = templates[t.id];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (t.id == 'apresentacao') {
      data = templates['dedicacao'];
      if (data is Map) return Map<String, dynamic>.from(data);
    }
    return null;
  }

  Color _corForTemplate(_CertTemplate t) {
    final data = _templateConfig(t);
    if (data == null) return t.cor;
    final hex = (data['corPrimaria'] ?? '').toString().trim();
    if (hex.isEmpty) return t.cor;
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6) return t.cor;
    return Color(int.parse('FF$h', radix: 16));
  }

  Color _corTextoForTemplate(_CertTemplate t) {
    final data = _templateConfig(t);
    final hex = (data?['corTexto'] ?? '').toString().trim();
    if (hex.isEmpty) return const Color(0xFF1E1E1E);
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6) return const Color(0xFF1E1E1E);
    return Color(int.parse('FF$h', radix: 16));
  }

  String _tituloForTemplate(_CertTemplate t) {
    final data = _templateConfig(t);
    if (data == null) return t.nome;
    final titulo = (data['titulo'] ?? '').toString().trim();
    return titulo.isNotEmpty ? titulo : t.nome;
  }

  String _textoModeloForTemplate(_CertTemplate t) {
    final data = _templateConfig(t);
    if (data == null) return t.textoModelo;
    final texto = (data['textoModelo'] ?? '').toString().trim();
    return texto.isNotEmpty ? texto : t.textoModelo;
  }

  String _subtituloForTemplate(_CertTemplate t) {
    final data = _templateConfig(t);
    if (data == null || !data.containsKey('subtitulo')) {
      return t.subtituloPadrao;
    }
    return (data['subtitulo'] ?? '').toString().trim();
  }

  List<_SignatoryOption> _buildSignatoryOptions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allMembers) {
    final list = <_SignatoryOption>[];
    for (final doc in allMembers) {
      final d = doc.data();
      if (!memberHasLeadershipForAssinatura(d)) continue;
      final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final cargoOptions = signatoryCargoDisplayOptions(d);
      list.add(_SignatoryOption(
        memberId: doc.id,
        nome: nome,
        cargo: cargoOptions.first,
        cargoOptions: cargoOptions,
        assinaturaUrl:
            (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim(),
      ));
    }
    list.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return list;
  }

  /// Pré-seleciona pastor(a) ou primeiro elegível.
  List<String> _initialSelectedSignatoryIds(List<_SignatoryOption> options) {
    if (options.isEmpty) return [];
    final cfg = _certConfig ?? const <String, dynamic>{};
    final configuredListRaw = cfg['defaultSignatoryMemberIds'];
    if (configuredListRaw is List) {
      final configuredList = configuredListRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (configuredList.isNotEmpty) {
        final valid = options
            .where((o) => configuredList.contains(o.memberId))
            .map((o) => o.memberId)
            .toList();
        if (valid.isNotEmpty) return valid;
      }
    }
    final configuredSingle = (cfg['defaultSignatoryMemberId'] ?? '').toString().trim();
    if (configuredSingle.isNotEmpty) {
      final exists = options.any((o) => o.memberId == configuredSingle);
      if (exists) return [configuredSingle];
    }
    final pastors = options.where((o) => o.cargo.contains('Pastor')).toList();
    if (pastors.length == 1) return [pastors.first.memberId];
    if (pastors.isNotEmpty) return [pastors.first.memberId];
    return [options.first.memberId];
  }

  @override
  Widget build(BuildContext context) {
    if (!_tenantLoaded) return const ChurchPanelLoadingBody();

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _membersFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: ChurchPanelErrorBody(
              title: 'Não foi possível carregar os membros',
              error: snap.error,
              onRetry: _refreshMembers,
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final allDocs = snap.data?.docs ?? [];
        if (allDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Nenhum membro cadastrado.',
                    style:
                        TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text('Cadastre membros para emitir certificados.',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ],
            ),
          );
        }

        final docs = allDocs.where((d) {
          if (_searchQuery.isEmpty) return true;
          final data = d.data();
          final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? '')
              .toString()
              .toLowerCase();
          final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString();
          return nome.contains(_searchQuery) || cpf.contains(_searchQuery);
        }).toList()
          ..sort((a, b) {
            final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
                .toString()
                .toLowerCase();
            final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
                .toString()
                .toLowerCase();
            return na.compareTo(nb);
          });
        final signatoryOptionsAll = _buildSignatoryOptions(allDocs);
        final totalTemplates = _templates.length;
        final customTemplates = _templates.where((t) {
          final cfg = _templateConfig(t);
          return cfg != null && cfg.isNotEmpty;
        }).length;
        final modelDistribution = <String, int>{
          for (final o in _certLayoutOptions) o.id: 0,
        };
        for (final t in _templates) {
          final layout = _layoutForTemplate(t);
          modelDistribution[layout] = (modelDistribution[layout] ?? 0) + 1;
        }

        /// Um único eixo de scroll: evita `Column` + `Expanded` + `ListView`, que zera a
        /// altura da lista quando o cabeçalho (insights + busca) passa do viewport — típico em
        /// celular e em janelas baixas no desktop.
        final pageEdge = ThemeCleanPremium.pagePadding(context);
        return DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.white,
                child: TabBar(
                  indicatorColor: ThemeCleanPremium.primary,
                  labelColor: ThemeCleanPremium.primary,
                  unselectedLabelColor: Colors.grey.shade600,
                  tabs: const [
                    Tab(text: 'Membros'),
                    Tab(text: 'Histórico de emissões'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        RefreshIndicator(
          onRefresh: () async {
            _refreshMembers();
            await _membersFuture;
          },
          child: CustomScrollView(
            physics: AlwaysScrollableScrollPhysics(
              parent: !kIsWeb &&
                      Theme.of(context).platform == TargetPlatform.android
                  ? const ClampingScrollPhysics()
                  : const BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pageEdge.left,
                  ThemeCleanPremium.spaceMd,
                  pageEdge.right,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ThemeCleanPremium.spaceLg,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _CertificadosConfigPage(
                              tenantId: widget.tenantId,
                              tenantData: _tenantData,
                              certConfig: _certConfig,
                              logoIgreja: _logoUrl,
                              nomeIgreja: _nomeIgreja,
                            ),
                          ),
                        );
                        if (mounted) await _loadTenant();
                        if (mounted) await _loadCertConfig();
                        if (mounted) setState(() {});
                      },
                      icon: Icon(Icons.edit_note_rounded,
                          size: 20, color: ThemeCleanPremium.primary),
                      label: const Text(
                          'Personalizar redação, título, versículo e aparência'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ThemeCleanPremium.primary,
                        side: BorderSide(
                            color:
                                ThemeCleanPremium.primary.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: ThemeCleanPremium.isMobile(context)
                            ? const Size(0, ThemeCleanPremium.minTouchTarget)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm),
                        ),
                      ),
                    ),
                        const SizedBox(height: 10),
                        Text(
                          'No editor: texto principal com {NOME}, {CPF} e {DATA_CERTIFICADO}; '
                          'versículo opcional sob o título; título e cores por tipo de certificado.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pageEdge.left,
                  ThemeCleanPremium.spaceSm,
                  pageEdge.right,
                  ThemeCleanPremium.spaceSm,
                ),
                sliver: SliverToBoxAdapter(
                  child: _CertificadosInsightsPanel(
                    totalMembros: allDocs.length,
                    membrosFiltrados: docs.length,
                    signatariosElegiveis: signatoryOptionsAll.length,
                    totalTemplates: totalTemplates,
                    templatesCustomizados: customTemplates,
                    modelDistribution: modelDistribution,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pageEdge.left,
                  ThemeCleanPremium.spaceSm,
                  pageEdge.right,
                  4,
                ),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar membro...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pageEdge.left,
                  ThemeCleanPremium.spaceSm,
                  pageEdge.right,
                  ThemeCleanPremium.spaceSm,
                ),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${docs.length} membro(s)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FilterChip(
                        label: Text(_batchMode ? 'Lote: ${_batchMemberIds.length}' : 'Modo lote'),
                        selected: _batchMode,
                        onSelected: (v) {
                          setState(() {
                            _batchMode = v;
                            if (!v) _batchMemberIds.clear();
                          });
                        },
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Text(
                          _batchMode
                              ? 'Toque para marcar; use o botão Lote'
                              : 'Toque no nome para emitir certificado',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (docs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nenhum membro encontrado.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    pageEdge.left,
                    0,
                    pageEdge.right,
                    80,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final data = docs[i].data();
                        final nome = (data['NOME_COMPLETO'] ??
                                data['nome'] ??
                                'Sem nome')
                            .toString();
                        final cpf =
                            (data['CPF'] ?? data['cpf'] ?? '').toString();
                        final foto = imageUrlFromMap(data);
                        final hasFoto = foto.isNotEmpty;
                        final avatarColor =
                            avatarColorForMember(data, hasPhoto: hasFoto);
                        final docId = docs[i].id;
                        final batchSel = _batchMemberIds.contains(docId);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                            boxShadow: ThemeCleanPremium.softUiCardShadow,
                            border: Border.all(
                              color: batchSel
                                  ? ThemeCleanPremium.primary.withOpacity(0.35)
                                  : const Color(0xFFF1F5F9),
                              width: batchSel ? 1.5 : 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd),
                              onTap: () {
                                if (_batchMode) {
                                  setState(() {
                                    if (batchSel) {
                                      _batchMemberIds.remove(docId);
                                    } else {
                                      _batchMemberIds.add(docId);
                                    }
                                  });
                                } else {
                                  _showTemplateSelector(
                                      context, docs[i], allDocs);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 14),
                                child: Row(
                                  children: [
                                    hasFoto
                                        ? ClipOval(
                                            child: SizedBox(
                                              width: 52,
                                              height: 52,
                                              child: SafeCircleAvatarImage(
                                                imageUrl: foto,
                                                radius: 26,
                                                fallbackIcon:
                                                    Icons.person_rounded,
                                                fallbackColor: Colors.white,
                                                backgroundColor: avatarColor ??
                                                    Colors.grey.shade400,
                                              ),
                                            ),
                                          )
                                        : CircleAvatar(
                                            radius: 26,
                                            backgroundColor: avatarColor ??
                                                Colors.grey.shade400,
                                            child: Text(
                                              (nome.isNotEmpty
                                                      ? nome[0]
                                                      : '?')
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nome,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          if (cpf.isNotEmpty)
                                            Text(
                                              'CPF: ${_formatCpf(cpf)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (_batchMode)
                                      Checkbox(
                                        value: batchSel,
                                        onChanged: (_) {
                                          setState(() {
                                            if (batchSel) {
                                              _batchMemberIds.remove(docId);
                                            } else {
                                              _batchMemberIds.add(docId);
                                            }
                                          });
                                        },
                                      )
                                    else
                                      Icon(
                                        Icons.workspace_premium_rounded,
                                        color: ThemeCleanPremium.primary
                                            .withOpacity(0.6),
                                        size: 26,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: docs.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
            if (_batchMode && _batchMemberIds.isNotEmpty)
              Positioned(
                right: pageEdge.right + 8,
                bottom: 24,
                child: SafeArea(
                  child: Material(
                    elevation: 6,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    color: ThemeCleanPremium.primary,
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      onTap: () => _onBatchFabTap(
                          context, docs, allDocs, signatoryOptionsAll),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _batchPreferSinglePdf
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.folder_zip_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Gerar em massa (${_batchMemberIds.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
                    _CertificadosEmitidosHistoricoView(
                      tenantId: widget.tenantId,
                      onReprint: (cid) =>
                          _reemitirCertificadoPorProtocolo(context, cid),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _safeCertFileStub(String id) {
    final s = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return s.isEmpty ? 'membro' : s.substring(0, s.length > 40 ? 40 : s.length);
  }

  int _intFromFirestore(dynamic v, int fallback) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return fallback;
  }

  Map<String, dynamic> _certificateProtocolSnapshot({
    required String memberId,
    required _CertTemplate template,
    required String nomeMembro,
    required String cpfFormatado,
    required String textoCorpo,
    required String textoAdicional,
    required String issuedDateStr,
    required String local,
    required String visualTemplateId,
    required String layoutId,
    required String fontStyleId,
    required int colorPrimaryArgb,
    required int colorTextArgb,
    required bool includeInstitutionalPastorSignature,
    required bool useDigitalSignature,
    required String pastorManual,
    required String cargoManual,
    required String institutionalPastorNome,
    required String institutionalPastorCargo,
    required List<_SignatoryOption> effectiveSignatories,
  }) {
    return <String, dynamic>{
      'memberId': memberId,
      'tipoCertificadoId': template.id,
      'tipoCertificadoNome': template.nome,
      'nomeMembro': nomeMembro,
      'cpfFormatado': cpfFormatado,
      'titulo': _tituloForTemplate(template),
      'subtitulo': _subtituloForTemplate(template),
      'textoCorpo': textoCorpo,
      'textoAdicional': textoAdicional,
      'local': local,
      'nomeIgreja': _nomeIgreja,
      'issuedDateStr': issuedDateStr,
      'visualTemplateId': visualTemplateId,
      'layoutId': layoutId,
      'fontStyleId': fontStyleId,
      'colorPrimaryArgb': colorPrimaryArgb,
      'colorTextArgb': colorTextArgb,
      'includeInstitutionalPastorSignature': includeInstitutionalPastorSignature,
      'useDigitalSignature': useDigitalSignature,
      'pastorManual': pastorManual,
      'cargoManual': cargoManual,
      'institutionalPastorNome': institutionalPastorNome,
      'institutionalPastorCargo': institutionalPastorCargo,
      'signatariosSnapshot': <dynamic>[
        for (final s in effectiveSignatories)
          <String, dynamic>{
            'memberId': s.memberId,
            'nome': s.nome,
            'cargo': s.cargo,
          },
      ],
    };
  }

  Future<void> _reemitirCertificadoPorProtocolo(
    BuildContext context,
    String certificadoId,
  ) async {
    final cid = certificadoId.trim();
    if (cid.isEmpty) {
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    final phase = ValueNotifier<String>('A carregar protocolo…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: ValueListenableBuilder<String>(
              valueListenable: phase,
              builder: (_, msg, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(msg, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      },
    );
    try {
      final snap = await CertificateEmitidoService.getPublic(cid);
      if (!snap.exists || snap.data() == null) {
        throw Exception('Protocolo não encontrado');
      }
      final d = snap.data()!;
      final tid = (d['tenantId'] ?? '').toString().trim();
      if (tid.isEmpty || tid != widget.tenantId) {
        throw Exception('Este certificado não pertence a esta igreja.');
      }
      phase.value = 'A gerar PDF…';
      final sigs = <CertPdfPipelineSignatory>[];
      for (final raw in (d['signatariosSnapshot'] as List<dynamic>? ??
          const <dynamic>[])) {
        if (raw is Map<String, dynamic>) {
          sigs.add(
            CertPdfPipelineSignatory(
              memberId: (raw['memberId'] ?? '').toString(),
              nome: (raw['nome'] ?? '').toString(),
              cargo: (raw['cargo'] ?? '').toString(),
            ),
          );
        } else if (raw is Map) {
          sigs.add(
            CertPdfPipelineSignatory(
              memberId: (raw['memberId'] ?? '').toString(),
              nome: (raw['nome'] ?? '').toString(),
              cargo: (raw['cargo'] ?? '').toString(),
            ),
          );
        }
      }
      final textoAd = (d['textoAdicional'] ?? '').toString();
      final textoBase = (d['textoCorpo'] ?? '').toString();
      final textoCorpo = textoAd.trim().isEmpty
          ? textoBase
          : '${textoBase.trim()}\n\n${textoAd.trim()}';
      final bytes = await runCertificatePdfPipeline(
        CertPdfPipelineParams(
          tenantId: tid,
          logoFetchCandidates: _logoCertCandidateUrls,
          logoUrlFallback: _logoCert,
          titulo: (d['titulo'] ?? '').toString(),
          subtitulo: (d['subtitulo'] ?? '').toString(),
          texto: textoCorpo,
          textoAdicional: '',
          visualTemplateId: (d['visualTemplateId'] ?? 'classico_dourado')
              .toString(),
          includeInstitutionalPastorSignature:
              d['includeInstitutionalPastorSignature'] == true,
          institutionalPastorNome:
              (d['institutionalPastorNome'] ?? '').toString(),
          institutionalPastorCargo:
              (d['institutionalPastorCargo'] ?? '').toString(),
          nomeMembro: (d['nomeMembro'] ?? '').toString(),
          cpfFormatado: (d['cpfFormatado'] ?? '').toString(),
          nomeIgreja: (d['nomeIgreja'] ?? _nomeIgreja).toString(),
          local: (d['local'] ?? '').toString(),
          issuedDate: (d['issuedDateStr'] ?? '').toString(),
          layoutId: (d['layoutId'] ?? _certPdfLayoutId).toString(),
          fontStyleId: (d['fontStyleId'] ?? 'moderna').toString(),
          colorPrimaryArgb:
              _intFromFirestore(d['colorPrimaryArgb'], 0xFF2563EB),
          colorTextArgb: _intFromFirestore(d['colorTextArgb'], 0xFF1E1E1E),
          pastorManual: (d['pastorManual'] ?? '').toString(),
          cargoManual: (d['cargoManual'] ?? '').toString(),
          useDigitalSignature: d['useDigitalSignature'] == true,
          qrValidationUrl: CertificadoConsultaUrl.protocolValidationUrl(cid),
          signatoriesForPdf: sigs,
        ),
        onProgress: (m, _) {
          phase.value = m;
        },
      );
      if (mounted && nav.canPop()) {
        nav.pop();
      }
      if (mounted) {
        await showPdfActions(
          context,
          bytes: bytes,
          filename: 'certificado_$cid.pdf',
        );
      }
    } catch (e) {
      if (mounted && nav.canPop()) {
        nav.pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível reimprimir: $e')),
        );
      }
    } finally {
      phase.dispose();
    }
  }

  List<_SignatoryOption> _effectiveSignatoriesForBatch(
      List<_SignatoryOption> options) {
    final initialIds = _initialSelectedSignatoryIds(options);
    if (initialIds.isEmpty) return [];
    final selected =
        options.where((o) => initialIds.contains(o.memberId)).toList();
    return selected;
  }

  Future<void> _onBatchFabTap(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    List<_SignatoryOption> signatoryOptionsAll,
  ) async {
    final selectedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in filteredDocs) {
      if (_batchMemberIds.contains(d.id)) selectedDocs.add(d);
    }
    if (selectedDocs.isEmpty) return;

    final picked = await _showBatchTemplatePicker(context);
    if (!mounted || picked == null) return;
    final t = picked.template;
    final singlePdf = picked.singlePdf;

    if (selectedDocs.length > 10) {
      await _runCloudCertBatch(context, t, selectedDocs);
      return;
    }

    await _gerarLocalmente(context, t, selectedDocs, allDocs,
        signatoryOptionsAll,
        singlePdf: singlePdf);
  }

  /// Até 10 membros: gera PDF único (Gala Luxo) ou ZIP localmente.
  Future<void> _gerarLocalmente(
    BuildContext context,
    _CertTemplate template,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    List<_SignatoryOption> signatoryOptionsAll, {
    bool singlePdf = true,
  }) {
    return _runLocalCertBatch(
      context,
      template,
      selectedDocs,
      allDocs,
      signatoryOptionsAll,
      singlePdf: singlePdf,
    );
  }

  Future<({_CertTemplate template, bool singlePdf})?> _showBatchTemplatePicker(
      BuildContext context) {
    var singlePdf = _batchPreferSinglePdf;
    return showModalBottomSheet<({_CertTemplate template, bool singlePdf})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ThemeCleanPremium.radiusMd)),
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.58,
          maxChildSize: 0.92,
          minChildSize: 0.38,
          builder: (ctx, scrollCtrl) => StatefulBuilder(
            builder: (context, setModal) {
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ThemeCleanPremium.spaceLg,
                      ThemeCleanPremium.spaceLg,
                      ThemeCleanPremium.spaceLg,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Certificados em lote',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600)),
                        const SizedBox(height: 6),
                        const Text('Escolha o modelo',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Um único PDF'),
                          subtitle: Text(
                            'Todas as páginas num ficheiro (ideal para impressão). Desligue para gerar ZIP com um PDF por pessoa.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              height: 1.35,
                            ),
                          ),
                          value: singlePdf,
                          onChanged: (v) {
                            setModal(() => singlePdf = v);
                            setState(() => _batchPreferSinglePdf = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                  controller: scrollCtrl,
                  padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 0,
                      ThemeCleanPremium.spaceLg, 24),
                  itemCount: _templates.length,
                  itemBuilder: (context, i) {
                    final t = _templates[i];
                    final cor = _corForTemplate(t);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: cor.withOpacity(0.2)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          onTap: () => Navigator.pop(ctx,
                              (template: t, singlePdf: singlePdf)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: cor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                  child: Icon(t.icon, color: cor, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_tituloForTemplate(t),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text(
                                          'Usar para todos os selecionados',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded,
                                    size: 16, color: cor.withOpacity(0.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _runCloudCertBatch(
    BuildContext context,
    _CertTemplate template,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedDocs,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final phase = ValueNotifier<String>('Enviando pedido à nuvem…');
    final cloudTotal = selectedDocs.length;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
            content: ValueListenableBuilder<String>(
              valueListenable: phase,
              builder: (_, msg, __) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Processando lote grande na nuvem…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'você receberá o link em instantes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$cloudTotal certificado(s) em um único PDF',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('processarCertificadosLote');
      final res = await callable.call<Map<String, dynamic>>({
        'igrejaId': widget.tenantId,
        'listaMembrosId': selectedDocs.map((e) => e.id).toList(),
        'idAssinatura': template.id,
      });
      final data = res.data;
      final url = (data['downloadUrl'] ?? '').toString().trim();
      if (url.isEmpty) {
        throw Exception('Resposta sem link de download');
      }
      phase.value = 'Pronto! Abrindo download…';
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'PDF único gerado na nuvem. Se o download não abrir, verifique o link no navegador.'),
            duration: Duration(seconds: 6),
          ),
        );
      }
      setState(() {
        _batchMemberIds.clear();
        _batchMode = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro na nuvem: $e')),
        );
      }
    } finally {
      phase.dispose();
      if (mounted && nav.canPop()) nav.pop();
    }
  }

  Future<void> _runLocalCertBatch(
    BuildContext context,
    _CertTemplate template,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    List<_SignatoryOption> signatoryOptionsAll, {
    bool singlePdf = true,
  }) async {
    await _loadCertConfig();
    if (!mounted) return;
    if (!context.mounted) return;
    final signatoryOptions = signatoryOptionsAll;
    final effective = _effectiveSignatoriesForBatch(signatoryOptions);
    final useDigital =
        (_certConfig?['defaultSignatureMode'] ?? '').toString().trim() !=
            'manual';
    final includeInstRaw =
        _certConfig?['includeInstitutionalPastorSignature'];
    final includeInstitutionalPastorSignature = includeInstRaw is bool
        ? includeInstRaw
        : true;
    String fallbackNome = (_tenantData?['gestorNome'] ?? '').toString();
    String fallbackCargo = 'Pastor(a) Presidente';
    if (signatoryOptions.isNotEmpty && effective.isNotEmpty) {
      fallbackNome = effective.first.nome;
      fallbackCargo = effective.first.cargo;
    }

    final nav = Navigator.of(context, rootNavigator: true);
    final phase = ValueNotifier<String>('Preparando…');
    final total = selectedDocs.length;
    final cur = ValueNotifier<int>(total > 0 ? 1 : 0);
    final layoutBatch = _layoutForTemplate(template);
    final galaSingle = singlePdf && layoutBatch == _certPdfLayoutId;
    final prog01 = ValueNotifier<double>(total > 0 ? 0.04 : 0.02);
    final titleNv = ValueNotifier<String>(
      galaSingle
          ? 'PDF único — $total página(s)'
          : 'Certificado ${cur.value}/$total',
    );
    final batchAccent = _corForTemplate(template);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        return _CertificatePdfProgressShell(
          phase: phase,
          progress01: prog01,
          title: titleNv,
          accent: batchAccent,
          showDigitalSigningLine: useDigital,
        );
      },
    );

    final zipEntries = <String, Uint8List>{};
    try {
      final layoutLote = layoutBatch;
      if (singlePdf && layoutLote == _certPdfLayoutId) {
        final dataHoje = _formatDateBr(DateTime.now());
        final localTxt = _tenantData?['cidade'] != null
            ? '${_tenantData!['cidade']}/${_tenantData?['estado'] ?? ''}'
            : '';
        final visualLote = () {
          final v = (_certConfig?['defaultVisualTemplateId'] ?? 'classico_dourado')
              .toString()
              .trim();
          if (v.isEmpty) return 'classico_dourado';
          return v;
        }();
        final snapshots = <Map<String, dynamic>>[];
        final sliceRows = <({String nome, String cpf, String texto})>[];
        for (var i = 0; i < selectedDocs.length; i++) {
          final doc = selectedDocs[i];
          final data = doc.data();
          final nome =
              (data['NOME_COMPLETO'] ?? data['nome'] ?? '').toString();
          final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString();
          final textoModelo = _textoModeloForTemplate(template);
          final textoComPlaceholders = textoModelo
              .replaceAll('{NOME}', nome)
              .replaceAll('{CPF}', _formatCpf(cpf));
          final textoFinal = _resolveCertificateText(
            textoComPlaceholders,
            issuedDate: dataHoje,
          );
          snapshots.add(
            _certificateProtocolSnapshot(
              memberId: doc.id,
              template: template,
              nomeMembro: nome,
              cpfFormatado: _formatCpf(cpf),
              textoCorpo: textoFinal,
              textoAdicional: '',
              issuedDateStr: dataHoje,
              local: localTxt,
              visualTemplateId: visualLote,
              layoutId: layoutLote,
              fontStyleId: _fontStyleForTemplate(template),
              colorPrimaryArgb: _corForTemplate(template).toARGB32(),
              colorTextArgb: _corTextoForTemplate(template).toARGB32(),
              includeInstitutionalPastorSignature:
                  includeInstitutionalPastorSignature,
              useDigitalSignature: useDigital,
              pastorManual: fallbackNome,
              cargoManual: fallbackCargo,
              institutionalPastorNome: fallbackNome,
              institutionalPastorCargo: fallbackCargo,
              effectiveSignatories: effective,
            ),
          );
          sliceRows.add((nome: nome, cpf: cpf, texto: textoFinal));
        }
        cur.value = total;
        titleNv.value = 'PDF único — $total página(s)';
        prog01.value = 0.08;
        phase.value = 'A registar protocolos (${snapshots.length})…';
        final protocolIds = await CertificateEmitidoService.registerEmissaoBatch(
          tenantId: widget.tenantId,
          snapshots: snapshots,
        );
        final slices = <CertPdfGalaBatchMemberSlice>[
          for (var i = 0; i < sliceRows.length; i++)
            CertPdfGalaBatchMemberSlice(
              nomeMembro: sliceRows[i].nome,
              cpfFormatado: _formatCpf(sliceRows[i].cpf),
              texto: sliceRows[i].texto,
              qrValidationUrl: CertificadoConsultaUrl.protocolValidationUrl(
                  protocolIds[i]),
            ),
        ];
        phase.value = 'A gerar PDF único (${slices.length} páginas)…';
        prog01.value = 0.12;
        final first = selectedDocs.first.data();
        final firstNome =
            (first['NOME_COMPLETO'] ?? first['nome'] ?? '').toString();
        final firstCpf = (first['CPF'] ?? first['cpf'] ?? '').toString();
        final signatoriesForPdf = [
          for (final s in effective)
            CertPdfPipelineSignatory(
              memberId: s.memberId,
              nome: s.nome,
              cargo: s.cargo,
              assinaturaUrlHint:
                  s.assinaturaUrl.isNotEmpty ? s.assinaturaUrl : null,
            ),
        ];
        final pdfBytes = await runCertificateGalaLuxoBatchPdfPipeline(
          shared: CertPdfPipelineParams(
            tenantId: widget.tenantId,
            logoFetchCandidates: _logoCertCandidateUrls,
            logoUrlFallback: _logoCert,
            titulo: _tituloForTemplate(template),
            subtitulo: _subtituloForTemplate(template),
            texto: slices.first.texto,
            textoAdicional: '',
            visualTemplateId: visualLote,
            includeInstitutionalPastorSignature:
                includeInstitutionalPastorSignature,
            institutionalPastorNome: fallbackNome,
            institutionalPastorCargo: fallbackCargo,
            nomeMembro: firstNome,
            cpfFormatado: _formatCpf(firstCpf),
            nomeIgreja: _nomeIgreja,
            local: localTxt,
            issuedDate: dataHoje,
            layoutId: layoutLote,
            fontStyleId: _fontStyleForTemplate(template),
            colorPrimaryArgb: _corForTemplate(template).toARGB32(),
            colorTextArgb: _corTextoForTemplate(template).toARGB32(),
            pastorManual: fallbackNome,
            cargoManual: fallbackCargo,
            useDigitalSignature: useDigital,
            qrValidationUrl: slices.first.qrValidationUrl,
            signatoriesForPdf: signatoriesForPdf,
          ),
          members: slices,
          onProgress: (m, p) {
            phase.value = m;
            prog01.value = p.clamp(0.0, 1.0);
            cur.value = (p * total).ceil().clamp(1, total);
            titleNv.value = 'PDF único — ${cur.value}/$total';
          },
        );
        phase.value = 'A preparar partilha…';
        prog01.value = 0.98;
        final pdfFname =
            'certificados_lote_${selectedDocs.length}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        if (mounted && nav.canPop()) nav.pop();
        final openedPdf = await writeCertZipAndOpen(pdfBytes, pdfFname);
        if (openedPdf != null) {
          await Share.shareXFiles(
            [
              XFile(openedPdf),
            ],
            text: 'Certificados da igreja (PDF único)',
            subject: 'Certificados',
          );
        } else {
          await Share.shareXFiles(
            [
              XFile.fromData(
                pdfBytes,
                name: pdfFname,
                mimeType: 'application/pdf',
              ),
            ],
            text: 'Certificados da igreja (PDF único)',
            subject: 'Certificados',
          );
        }
        if (mounted) {
          imageCache.clear();
          setState(() {
            _batchMemberIds.clear();
            _batchMode = false;
          });
        }
        return;
      }

      final dataHojeZip = _formatDateBr(DateTime.now());
      final localTxtZip = _tenantData?['cidade'] != null
          ? '${_tenantData!['cidade']}/${_tenantData?['estado'] ?? ''}'
          : '';
      final visualLoteZip = () {
        final v = (_certConfig?['defaultVisualTemplateId'] ?? 'classico_dourado')
            .toString()
            .trim();
        if (v.isEmpty) return 'classico_dourado';
        return v;
      }();
      final layoutLoteZip = _layoutForTemplate(template);

      final zipSnapshots = <Map<String, dynamic>>[];
      final zipRows = <
          ({
            String docId,
            String nome,
            String cpf,
            String textoFinal,
          })>[];
      for (var i = 0; i < selectedDocs.length; i++) {
        final doc = selectedDocs[i];
        final data = doc.data();
        final nome =
            (data['NOME_COMPLETO'] ?? data['nome'] ?? '').toString();
        final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString();
        final textoModelo = _textoModeloForTemplate(template);
        final textoComPlaceholders = textoModelo
            .replaceAll('{NOME}', nome)
            .replaceAll('{CPF}', _formatCpf(cpf));
        final textoFinal = _resolveCertificateText(
          textoComPlaceholders,
          issuedDate: dataHojeZip,
        );
        zipSnapshots.add(
          _certificateProtocolSnapshot(
            memberId: doc.id,
            template: template,
            nomeMembro: nome,
            cpfFormatado: _formatCpf(cpf),
            textoCorpo: textoFinal,
            textoAdicional: '',
            issuedDateStr: dataHojeZip,
            local: localTxtZip,
            visualTemplateId: visualLoteZip,
            layoutId: layoutLoteZip,
            fontStyleId: _fontStyleForTemplate(template),
            colorPrimaryArgb: _corForTemplate(template).toARGB32(),
            colorTextArgb: _corTextoForTemplate(template).toARGB32(),
            includeInstitutionalPastorSignature:
                includeInstitutionalPastorSignature,
            useDigitalSignature: useDigital,
            pastorManual: fallbackNome,
            cargoManual: fallbackCargo,
            institutionalPastorNome: fallbackNome,
            institutionalPastorCargo: fallbackCargo,
            effectiveSignatories: effective,
          ),
        );
        zipRows.add((
          docId: doc.id,
          nome: nome,
          cpf: cpf,
          textoFinal: textoFinal,
        ));
      }

      titleNv.value = 'Certificado 1/$total';
      phase.value = 'A registar protocolos (${zipSnapshots.length})…';
      prog01.value = 0.06;
      final protocolIdsZip =
          await CertificateEmitidoService.registerEmissaoBatch(
        tenantId: widget.tenantId,
        snapshots: zipSnapshots,
      );

      final signatoriesForZip = [
        for (final s in effective)
          CertPdfPipelineSignatory(
            memberId: s.memberId,
            nome: s.nome,
            cargo: s.cargo,
            assinaturaUrlHint:
                s.assinaturaUrl.isNotEmpty ? s.assinaturaUrl : null,
          ),
      ];

      final firstRow = zipRows.first;
      phase.value =
          'A preparar imagens e fontes (uma vez para $total certificados)…';
      final sharedZipResolved = await resolveCertificatePdfShared(
        CertPdfPipelineParams(
          tenantId: widget.tenantId,
          logoFetchCandidates: _logoCertCandidateUrls,
          logoUrlFallback: _logoCert,
          titulo: _tituloForTemplate(template),
          subtitulo: _subtituloForTemplate(template),
          texto: firstRow.textoFinal,
          textoAdicional: '',
          visualTemplateId: visualLoteZip,
          includeInstitutionalPastorSignature:
              includeInstitutionalPastorSignature,
          institutionalPastorNome: fallbackNome,
          institutionalPastorCargo: fallbackCargo,
          nomeMembro: firstRow.nome,
          cpfFormatado: _formatCpf(firstRow.cpf),
          nomeIgreja: _nomeIgreja,
          local: localTxtZip,
          issuedDate: dataHojeZip,
          layoutId: layoutLoteZip,
          fontStyleId: _fontStyleForTemplate(template),
          colorPrimaryArgb: _corForTemplate(template).toARGB32(),
          colorTextArgb: _corTextoForTemplate(template).toARGB32(),
          pastorManual: fallbackNome,
          cargoManual: fallbackCargo,
          useDigitalSignature: useDigital,
          qrValidationUrl: CertificadoConsultaUrl.protocolValidationUrl(
              protocolIdsZip.first),
          signatoriesForPdf: signatoriesForZip,
        ),
        onProgress: (m, p) {
          phase.value = m;
          prog01.value = 0.05 + p * 0.40;
        },
        currentIndex: 1,
        totalCount: total,
      );

      for (var i = 0; i < zipRows.length; i++) {
        final row = zipRows[i];
        cur.value = i + 1;
        titleNv.value = 'Certificado ${i + 1}/$total';
        prog01.value = 0.45 + (i + 0.08) / total * 0.47;
        phase.value =
            'Certificado ${i + 1} de $total — a gerar PDF…';

        final bytes = await runCertificatePdfPipeline(
          CertPdfPipelineParams(
            tenantId: widget.tenantId,
            logoFetchCandidates: _logoCertCandidateUrls,
            logoUrlFallback: _logoCert,
            titulo: _tituloForTemplate(template),
            subtitulo: _subtituloForTemplate(template),
            texto: row.textoFinal,
            textoAdicional: '',
            visualTemplateId: visualLoteZip,
            includeInstitutionalPastorSignature:
                includeInstitutionalPastorSignature,
            institutionalPastorNome: fallbackNome,
            institutionalPastorCargo: fallbackCargo,
            nomeMembro: row.nome,
            cpfFormatado: _formatCpf(row.cpf),
            nomeIgreja: _nomeIgreja,
            local: localTxtZip,
            issuedDate: dataHojeZip,
            layoutId: layoutLoteZip,
            fontStyleId: _fontStyleForTemplate(template),
            colorPrimaryArgb: _corForTemplate(template).toARGB32(),
            colorTextArgb: _corTextoForTemplate(template).toARGB32(),
            pastorManual: fallbackNome,
            cargoManual: fallbackCargo,
            useDigitalSignature: useDigital,
            qrValidationUrl: CertificadoConsultaUrl.protocolValidationUrl(
                protocolIdsZip[i]),
            signatoriesForPdf: signatoriesForZip,
          ),
          preResolvedShared: sharedZipResolved,
          onProgress: (m, p) {
            phase.value = m;
            prog01.value =
                (0.45 + (i + p) / total * 0.47).clamp(0.0, 0.94);
          },
          currentIndex: i + 1,
          totalCount: total,
        );
        zipEntries['certificado_${_safeCertFileStub(row.docId)}.pdf'] = bytes;
        await Future<void>.delayed(Duration.zero);
      }

      cur.value = total;
      titleNv.value = 'Compactando arquivo…';
      prog01.value = 0.92;
      phase.value = 'Compactando ZIP…';

      if (zipEntries.isEmpty) {
        throw Exception('Nenhum PDF gerado');
      }
      final zipBytes = CarteirinhaZipExport.buildZip(zipEntries);
      final fname =
          'certificados_lote_${selectedDocs.length}_${DateTime.now().millisecondsSinceEpoch}.zip';
      if (mounted && nav.canPop()) nav.pop();

      final openedPath = await writeCertZipAndOpen(zipBytes, fname);
      if (openedPath != null) {
        await Share.shareXFiles(
          [
            XFile(openedPath),
          ],
          text: 'Certificados da igreja — envie pelo WhatsApp',
          subject: 'Certificados',
        );
      } else {
        await Share.shareXFiles(
          [
            XFile.fromData(zipBytes, name: fname, mimeType: 'application/zip'),
          ],
          text: 'Certificados da igreja — envie pelo WhatsApp',
          subject: 'Certificados',
        );
      }

      if (mounted) {
        imageCache.clear();
        setState(() {
          _batchMemberIds.clear();
          _batchMode = false;
        });
      }
    } catch (e) {
      if (mounted && nav.canPop()) nav.pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no lote local: $e')),
        );
      }
    } finally {
      phase.dispose();
      cur.dispose();
      prog01.dispose();
      titleNv.dispose();
      if (mounted) {
        imageCache.clear();
      }
    }
  }

  // ─── Selecionar Template ──────────────────────────────────────────────────
  void _showTemplateSelector(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> memberDoc,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allMembers) {
    final data = memberDoc.data();
    final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? '').toString();
    final signatoryOptions = _buildSignatoryOptions(allMembers);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var visualId = 'classico_dourado';
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(ThemeCleanPremium.radiusMd)),
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            maxChildSize: 0.95,
            minChildSize: 0.45,
            builder: (ctx2, scrollCtrl) => StatefulBuilder(
              builder: (context, setModal) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(2))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ThemeCleanPremium.spaceLg,
                        ThemeCleanPremium.spaceSm,
                        ThemeCleanPremium.spaceLg,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modelo visual do papel',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 132,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: kCertificateVisualTemplates.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, vi) {
                                final vt = kCertificateVisualTemplates[vi];
                                final sel = visualId == vt.id;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () =>
                                        setModal(() => visualId = vt.id),
                                    child: Ink(
                                      width: 116,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: sel
                                              ? ThemeCleanPremium.primary
                                              : Colors.grey.shade300,
                                          width: sel ? 2.5 : 1,
                                        ),
                                        boxShadow:
                                            ThemeCleanPremium.softUiCardShadow,
                                        gradient: LinearGradient(
                                          colors: vt.previewGradient,
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.layers_rounded,
                                              color: vt.previewAccent,
                                              size: 26,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              vt.nome,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              vt.descricao,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 9,
                                                height: 1.2,
                                                color: Colors.grey.shade800
                                                    .withValues(alpha: 0.78),
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
                          const SizedBox(height: 6),
                          Text(
                            'Logo dedicada (opcional): igrejas/{id}/certificados/logo_atual.jpg. '
                            'Fundos em alta resolução: igrejas/{id}/templates/certificados/'
                            '(ex.: modelo_classico_dourado.png). Impressão: PDF em alta definição; '
                            'CMYK depende da gráfica.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                      child: Column(
                        children: [
                          Text('Emitir certificado para',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          Text(nome,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollCtrl,
                        padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 0,
                            ThemeCleanPremium.spaceLg, 24),
                        itemCount: _templates.length,
                        itemBuilder: (context, i) {
                          final t = _templates[i];
                          final cor = _corForTemplate(t);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd),
                              boxShadow: ThemeCleanPremium.softUiCardShadow,
                              border: Border.all(color: cor.withOpacity(0.2)),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusMd),
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  await _openEditor(
                                    context,
                                    t,
                                    memberDoc,
                                    signatoryOptions,
                                    initialVisualTemplateId: visualId,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                            color: cor.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(
                                                ThemeCleanPremium.radiusSm)),
                                        child: Icon(t.icon, color: cor, size: 26),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(_tituloForTemplate(t),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14)),
                                            const SizedBox(height: 2),
                                            Text(
                                                'Toque para personalizar e gerar PDF',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade500)),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios_rounded,
                                          size: 16, color: cor.withOpacity(0.5)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                  },
                ),
              ),
            ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ─── Editor do Certificado ────────────────────────────────────────────────
  Future<void> _openEditor(
      BuildContext context,
      _CertTemplate template,
      QueryDocumentSnapshot<Map<String, dynamic>> memberDoc,
      List<_SignatoryOption> signatoryOptions,
      {String initialVisualTemplateId = 'classico_dourado'}) async {
    await _loadCertConfig();
    if (!mounted) return;
    if (!context.mounted) return;
    final data = memberDoc.data();
    final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? '').toString();
    final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString();
    final now = DateTime.now();
    final dataHoje = _formatDateBr(now);

    final textoModelo = _textoModeloForTemplate(template);
    final textoFinal = textoModelo
        .replaceAll('{NOME}', nome)
        .replaceAll('{CPF}', _formatCpf(cpf))
        .replaceAll('{DATA_CERTIFICADO}', '{DATA_CERTIFICADO}');

    final tituloCtrl =
        TextEditingController(text: _tituloForTemplate(template));
    final subtituloCtrl =
        TextEditingController(text: _subtituloForTemplate(template));
    final textoCtrl = TextEditingController(text: textoFinal);
    final localCtrl = TextEditingController(
        text: _tenantData?['cidade'] != null
            ? '${_tenantData!['cidade']}/${_tenantData?['estado'] ?? ''}'
            : '');
    final dataCertCtrl = TextEditingController(text: dataHoje);
    final initialSelectedIds = _initialSelectedSignatoryIds(signatoryOptions);
    final initialSignatureMode =
        ((_certConfig?['defaultSignatureMode'] ?? '').toString().trim() == 'manual')
            ? 'manual'
            : 'digital';
    String fallbackNome = (_tenantData?['gestorNome'] ?? '').toString();
    String fallbackCargo = 'Pastor(a) Presidente';
    if (signatoryOptions.isNotEmpty && initialSelectedIds.isNotEmpty) {
      final first = signatoryOptions.firstWhere(
          (o) => o.memberId == initialSelectedIds.first,
          orElse: () => signatoryOptions.first);
      fallbackNome = first.nome;
      fallbackCargo = first.cargo;
    }
    final pastorCtrl = TextEditingController(text: fallbackNome);
    final cargoCtrl = TextEditingController(text: fallbackCargo);
    final textoAdicionalCtrl = TextEditingController();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CertEditorPage(
          tenantId: widget.tenantId,
          memberFirestoreDocId: memberDoc.id,
          template: template,
          corOverride: _corForTemplate(template),
          corTextoOverride: _corTextoForTemplate(template),
          nomeIgreja: _nomeIgreja,
          logoUrl: _logoCert,
          logoFetchCandidates: _logoCertCandidateUrls,
          tenantData: _tenantData,
          nomeMembro: nome,
          cpfFormatado: _formatCpf(cpf),
          tituloCtrl: tituloCtrl,
          subtituloCtrl: subtituloCtrl,
          textoCtrl: textoCtrl,
          textoAdicionalCtrl: textoAdicionalCtrl,
          localCtrl: localCtrl,
          dataCertCtrl: dataCertCtrl,
          pastorCtrl: pastorCtrl,
          cargoCtrl: cargoCtrl,
          signatoryOptions: signatoryOptions,
          initialSelectedSignatoryIds: initialSelectedIds,
          initialLayoutId: _layoutForTemplate(template),
          initialFontStyleId: _fontStyleForTemplate(template),
          initialSignatureMode: initialSignatureMode,
          initialVisualTemplateId: initialVisualTemplateId,
        ),
      ),
    );
  }
}

class _CertificadosInsightsPanel extends StatelessWidget {
  final int totalMembros;
  final int membrosFiltrados;
  final int signatariosElegiveis;
  final int totalTemplates;
  final int templatesCustomizados;
  final Map<String, int> modelDistribution;

  const _CertificadosInsightsPanel({
    required this.totalMembros,
    required this.membrosFiltrados,
    required this.signatariosElegiveis,
    required this.totalTemplates,
    required this.templatesCustomizados,
    required this.modelDistribution,
  });

  @override
  Widget build(BuildContext context) {
    final cobertura = totalTemplates == 0
        ? 0.0
        : (templatesCustomizados / totalTemplates).clamp(0.0, 1.0);
    final sections = <PieChartSectionData>[];
    const colors = <String, Color>{
      'gala_luxo': Color(0xFFB8860B),
    };
    modelDistribution.forEach((id, value) {
      if (value <= 0) return;
      sections.add(
        PieChartSectionData(
          value: value.toDouble(),
          color: colors[id] ?? ThemeCleanPremium.primary,
          title: '$value',
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          radius: 28,
        ),
      );
    });

    Widget metricTile(String label, String value, IconData icon, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              metricTile('Membros', '$totalMembros', Icons.groups_rounded,
                  const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              metricTile('Visíveis', '$membrosFiltrados',
                  Icons.filter_alt_rounded, const Color(0xFF0891B2)),
              const SizedBox(width: 8),
              metricTile('Signatários', '$signatariosElegiveis',
                  Icons.draw_rounded, const Color(0xFF7C3AED)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personalização dos modelos',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: cobertura,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${templatesCustomizados.toString()}/$totalTemplates modelos com ajustes salvos',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (sections.length > 1) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 88,
                  height: 88,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 20,
                      sections: sections,
                    ),
                  ),
                ),
              ] else if (sections.length == 1) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Gala Luxo (A4 paisagem) com QR; três modelos visuais de fundo (Storage) e tipografia premium no PDF.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Configuração dos modelos (cor, logo, textos editáveis por modelo)
// ═══════════════════════════════════════════════════════════════════════════════
class _CertificadosConfigPage extends StatefulWidget {
  final String tenantId;
  final Map<String, dynamic>? tenantData;
  final Map<String, dynamic>? certConfig;
  final String logoIgreja;
  final String nomeIgreja;

  const _CertificadosConfigPage({
    required this.tenantId,
    this.tenantData,
    this.certConfig,
    required this.logoIgreja,
    required this.nomeIgreja,
  });

  @override
  State<_CertificadosConfigPage> createState() =>
      _CertificadosConfigPageState();
}

class _CertificadosConfigPageState extends State<_CertificadosConfigPage> {
  late TextEditingController _logoCtrl;
  final Map<String, String> _corByTemplate = {};
  final Map<String, String> _corTextoByTemplate = {};
  final Map<String, String> _fontStyleByTemplate = {};
  final Map<String, TextEditingController> _tituloByTemplate = {};
  final Map<String, TextEditingController> _subtituloByTemplate = {};
  final Map<String, TextEditingController> _textoByTemplate = {};
  bool _saving = false;
  bool _uploadingLogo = false;

  bool get _cadastroPodeTerLogo {
    if (widget.logoIgreja.isNotEmpty) return true;
    final d = widget.tenantData;
    if (d == null) return false;
    if (churchTenantLogoUrlCandidates(d).isNotEmpty) return true;
    final p = ChurchImageFields.logoStoragePath(d);
    return p != null && p.trim().isNotEmpty;
  }

  /// Campo vazio → Firestore grava logoUrl null → certificados usam sempre a logo do cadastro.
  Future<void> _usarLogoDoCadastro() async {
    setState(() => _logoCtrl.clear());
    if (!_cadastroPodeTerLogo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Campo limpo. Cadastre a logo em Cadastro da Igreja e toque em Salvar aqui para usar nos certificados.',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar(
        'Logo do cadastro: ao salvar, será usada a identidade visual da igreja (URL ou arquivo no Storage).',
      ),
    );
  }

  Future<void> _escolherDaGaleria() async {
    final file = await MediaHandlerService.instance.pickAndProcessLogoFromGallery();
    if (file == null || !mounted) return;
    setState(() => _uploadingLogo = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
      final bytes = await file.readAsBytes();
      await FirebaseStorageCleanupService.deleteCertificadoDedicatedLogoArtifacts(
        tenantId: widget.tenantId,
        certConfig: widget.certConfig != null
            ? Map<String, dynamic>.from(widget.certConfig!)
            : null,
      );
      final basePath = ChurchStorageLayout.certificadoDedicatedLogoBaseWithoutExt(
          widget.tenantId);
      final upload = await MediaUploadService.uploadBytesDetailed(
        storagePath: '$basePath.jpg',
        bytes: bytes,
        contentType: 'image/jpeg',
      );
      if (mounted) {
        // Um ficheiro canónico no Storage (estilo ECOFIRE); PDF/web usam logoUrl + logoPath.
        final primaryHttps = upload.downloadUrl;
        setState(() {
          _logoCtrl.text = primaryHttps;
          _uploadingLogo = false;
        });
        await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.tenantId)
            .collection('config')
            .doc('certificados')
            .set({
          'logoUrl': primaryHttps.trim(),
          'logoPath': upload.storagePath,
          'logoVariants': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Logo da galeria definido.'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingLogo = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao enviar logo: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final logo = (widget.certConfig?['logoUrl'] ?? '').toString().trim();
    _logoCtrl = TextEditingController(text: logo.isNotEmpty ? logo : '');
    for (final t in _templates) {
      final templates = widget.certConfig?['templates'];
      Map? data;
      if (templates is Map) {
        data = templates[t.id] is Map ? templates[t.id] as Map : null;
        if (data == null && t.id == 'apresentacao')
          data = templates['dedicacao'] is Map
              ? templates['dedicacao'] as Map
              : null;
      }
      String hex = (data?['corPrimaria'] ?? '').toString().trim();
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (hex.length != 6)
        hex = t.cor.value.toRadixString(16).padLeft(8, '0').substring(2);
      _corByTemplate[t.id] = hex;
      String textHex = (data?['corTexto'] ?? '').toString().trim();
      if (textHex.startsWith('#')) textHex = textHex.substring(1);
      if (textHex.length != 6) textHex = '1E1E1E';
      _corTextoByTemplate[t.id] = textHex;
      final fontStyleId = (data?['fontStyleId'] ?? '').toString().trim();
      _fontStyleByTemplate[t.id] =
          _certFontStyleOptions.any((e) => e.id == fontStyleId)
              ? fontStyleId
              : 'moderna';
      _tituloByTemplate[t.id] = TextEditingController(
        text: (data?['titulo'] ?? '').toString().trim().isNotEmpty
            ? (data!['titulo'] ?? '').toString()
            : t.nome,
      );
      final hasSubKey = data != null && data.containsKey('subtitulo');
      _subtituloByTemplate[t.id] = TextEditingController(
        text: hasSubKey
            ? (data['subtitulo'] ?? '').toString()
            : t.subtituloPadrao,
      );
      _textoByTemplate[t.id] = TextEditingController(
        text: (data?['textoModelo'] ?? '').toString().trim().isNotEmpty
            ? (data!['textoModelo'] ?? '').toString()
            : t.textoModelo,
      );
    }
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    for (final c in _tituloByTemplate.values) c.dispose();
    for (final c in _subtituloByTemplate.values) c.dispose();
    for (final c in _textoByTemplate.values) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final templates = <String, Map<String, String>>{};
      for (final t in _templates) {
        final titulo = _tituloByTemplate[t.id]?.text.trim() ?? t.nome;
        final subtitulo = _subtituloByTemplate[t.id]?.text.trim() ?? '';
        final texto = _textoByTemplate[t.id]?.text.trim() ?? t.textoModelo;
        final cor = _corByTemplate[t.id] ??
            t.cor.value.toRadixString(16).padLeft(8, '0').substring(2);
        final corTexto = _corTextoByTemplate[t.id] ?? '1E1E1E';
        final fontStyle = _fontStyleByTemplate[t.id] ?? 'moderna';
        templates[t.id] = {
          'corPrimaria': cor,
          'corTexto': corTexto,
          'layoutId': _certPdfLayoutId,
          'fontStyleId': fontStyle,
          'titulo': titulo,
          'subtitulo': subtitulo,
          'textoModelo': texto,
        };
      }
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('certificados')
          .set({
        'logoUrl': _logoCtrl.text.trim().isEmpty ? null : _logoCtrl.text.trim(),
        if (_logoCtrl.text.trim().isEmpty) 'logoPath': null,
        'logoVariants': FieldValue.delete(),
        'certLayoutId': _certPdfLayoutId,
        'templates': templates,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Configuração salva!'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Redação e aparência dos certificados',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Salvando...' : 'Salvar',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            Container(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.image_rounded,
                          color: ThemeCleanPremium.primary, size: 22),
                      const SizedBox(width: 10),
                      Text('Logo nos certificados',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _logoCtrl,
                    decoration: InputDecoration(
                      hintText: 'Vazio = logo do Cadastro da Igreja (recomendado)',
                      prefixIcon: const Icon(Icons.link_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploadingLogo ? null : _usarLogoDoCadastro,
                        icon:
                            const Icon(Icons.account_balance_rounded, size: 18),
                        label: const Text('Usar logo do cadastro'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ThemeCleanPremium.primary,
                          side: BorderSide(
                              color:
                                  ThemeCleanPremium.primary.withOpacity(0.6)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _uploadingLogo ? null : _escolherDaGaleria,
                        icon: _uploadingLogo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.photo_library_rounded, size: 18),
                        label: Text(_uploadingLogo
                            ? 'Enviando...'
                            : 'Escolher da galeria'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ThemeCleanPremium.primary,
                          side: BorderSide(
                              color:
                                  ThemeCleanPremium.primary.withOpacity(0.6)),
                        ),
                      ),
                    ],
                  ),
                  if (_logoCtrl.text.trim().isEmpty &&
                      widget.tenantId.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Prévia — logo do cadastro (quando existir)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      child: Container(
                        width: 120,
                        height: 120,
                        color: const Color(0xFFF8FAFC),
                        alignment: Alignment.center,
                        child: StableChurchLogo(
                          tenantId: widget.tenantId,
                          tenantData: widget.tenantData,
                          width: 112,
                          height: 112,
                          memCacheWidth: 512,
                          memCacheHeight: 512,
                        ),
                      ),
                    ),
                  ],
                  if (_cadastroPodeTerLogo || widget.logoIgreja.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                          'Vazio = mesma logo do Cadastro da Igreja. Use o botão acima e Salvar para aplicar.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            Container(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.style_rounded, color: ThemeCleanPremium.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Layout do PDF',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      '${_certLayoutOptions.first.nome} — ${_certLayoutOptions.first.descricao}',
                      style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            ..._templates.map((t) {
              final corHex = _corByTemplate[t.id] ??
                  t.cor.value.toRadixString(16).padLeft(8, '0').substring(2);
              final corAtual = Color(int.parse('FF$corHex', radix: 16));
              final corTextoHex = _corTextoByTemplate[t.id] ?? '1E1E1E';
              final corTextoAtual = Color(int.parse('FF$corTextoHex', radix: 16));
              final fontStyleAtual = _fontStyleByTemplate[t.id] ?? 'moderna';
              return Container(
                margin:
                    const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                  border: Border.all(color: corAtual.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: corAtual.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          child: Icon(t.icon, color: corAtual, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(t.nome,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Estilo da fonte',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: fontStyleAtual,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                            borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      items: _certFontStyleOptions
                          .map((o) => DropdownMenuItem<String>(
                                value: o.id,
                                child: Text('${o.nome} — ${o.descricao}'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _fontStyleByTemplate[t.id] = v);
                      },
                    ),
                    const SizedBox(height: 14),
                    Text('Cor do modelo',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _certificadoCores.map((c) {
                        final hex = c.value
                            .toRadixString(16)
                            .padLeft(8, '0')
                            .substring(2);
                        final selected = _corByTemplate[t.id] == hex;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _corByTemplate[t.id] = hex),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: selected
                                      ? ThemeCleanPremium.primary
                                      : Colors.grey.shade300,
                                  width: selected ? 3 : 1),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text('Cor da letra/texto',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _certificadoCores.map((c) {
                        final hex = c.value
                            .toRadixString(16)
                            .padLeft(8, '0')
                            .substring(2);
                        final selected = _corTextoByTemplate[t.id] == hex;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _corTextoByTemplate[t.id] = hex),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: selected
                                      ? ThemeCleanPremium.primary
                                      : Colors.grey.shade300,
                                  width: selected ? 3 : 1),
                            ),
                            child: selected
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 18)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        'Prévia da cor da letra',
                        style: TextStyle(
                          color: corTextoAtual,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Título do certificado',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _tituloByTemplate[t.id],
                      decoration: InputDecoration(
                        hintText: 'Ex: Certificado de Batismo',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                        'Versículo ou frase curta (sob o título — tradicional, premium gold, moderno)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _subtituloByTemplate[t.id],
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Ex.: Quem crer e for batizado… (deixe vazio para ocultar)',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text('Texto principal do corpo (use {NOME}, {CPF}, {DATA_CERTIFICADO})',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _textoByTemplate[t.id],
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: 'Texto que aparece no certificado...',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _tituloByTemplate[t.id]?.text = t.nome;
                            _subtituloByTemplate[t.id]?.text = t.subtituloPadrao;
                            _textoByTemplate[t.id]?.text = t.textoModelo;
                            _corByTemplate[t.id] = t.cor.value
                                .toRadixString(16)
                                .padLeft(8, '0')
                                .substring(2);
                            _corTextoByTemplate[t.id] = '1E1E1E';
                            _fontStyleByTemplate[t.id] = 'moderna';
                          });
                        },
                        icon: const Icon(Icons.restore_rounded, size: 18),
                        label: const Text('Restaurar texto e versículo padrão do sistema'),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de progresso ao gerar PDF(s) — etapas claras, percentual e ícone por fase.
class _CertificatePdfProgressShell extends StatelessWidget {
  const _CertificatePdfProgressShell({
    required this.phase,
    required this.progress01,
    required this.title,
    required this.accent,
    this.showDigitalSigningLine = false,
  });

  final ValueNotifier<String> phase;
  final ValueNotifier<double> progress01;
  final ValueNotifier<String> title;
  final Color accent;
  final bool showDigitalSigningLine;

  static IconData _iconForPhase(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('fonte') || m.contains('mídia') || m.contains('midia')) {
      return Icons.text_fields_rounded;
    }
    if (m.contains('baixando') || m.contains('paralelo')) {
      return Icons.cloud_sync_rounded;
    }
    if (m.contains('otimiz')) {
      return Icons.auto_fix_high_rounded;
    }
    if (m.contains('montando') || m.contains('página') || m.contains('pagina')) {
      return Icons.layers_rounded;
    }
    if (m.contains('compact')) {
      return Icons.folder_zip_rounded;
    }
    if (m.contains('concluí') || m.contains('concluido')) {
      return Icons.check_circle_rounded;
    }
    if (m.contains('regist') || m.contains('protocol')) {
      return Icons.verified_rounded;
    }
    if (m.contains('partilha') || m.contains('preparar')) {
      return Icons.share_rounded;
    }
    return Icons.picture_as_pdf_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: ValueListenableBuilder<String>(
              valueListenable: title,
              builder: (context, titleText, _) {
                return ValueListenableBuilder<String>(
                  valueListenable: phase,
                  builder: (context, msg, __) {
                    return ValueListenableBuilder<double>(
                      valueListenable: progress01,
                      builder: (context, v, ___) {
                        final ind = v.clamp(0.0, 1.0);
                        final pctLabel = (ind * 100).clamp(0, 100).round();
                        final icon = _iconForPhase(msg);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(icon, color: accent, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        titleText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$pctLabel% concluído',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 10,
                                value: ind >= 0.995
                                    ? null
                                    : ind.clamp(0.03, 0.99),
                                backgroundColor: Colors.grey.shade200,
                                color: accent,
                              ),
                            ),
                            if (showDigitalSigningLine) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.draw_rounded,
                                      size: 16, color: Colors.blue.shade700),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Incluindo assinaturas no PDF',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                msg,
                                key: ValueKey<String>(msg),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Rede otimizada: fontes, logo, fundo e assinaturas em paralelo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Página de Edição do Certificado
// ═══════════════════════════════════════════════════════════════════════════════
class _CertEditorPage extends StatefulWidget {
  final String tenantId;
  final _CertTemplate template;
  final Color? corOverride;
  final Color? corTextoOverride;
  final String nomeIgreja;
  final String logoUrl;
  /// Ordem de tentativa ao baixar a logo para o PDF (config + fallbacks do tenant).
  final List<String> logoFetchCandidates;
  /// Cadastro `igrejas/{id}` — usado para resolver logo só no Storage (sem URL no Firestore).
  final Map<String, dynamic>? tenantData;
  final String nomeMembro;
  final String cpfFormatado;
  final TextEditingController tituloCtrl;
  final TextEditingController subtituloCtrl;
  final TextEditingController textoCtrl;
  final TextEditingController textoAdicionalCtrl;
  final TextEditingController localCtrl;
  final TextEditingController dataCertCtrl;
  final TextEditingController pastorCtrl;
  final TextEditingController cargoCtrl;
  final List<_SignatoryOption> signatoryOptions;
  final List<String> initialSelectedSignatoryIds;
  final String initialLayoutId;
  final String initialFontStyleId;
  final String initialSignatureMode;
  final String initialVisualTemplateId;
  /// ID do documento do membro no Firestore (QR Gala Luxo).
  final String memberFirestoreDocId;

  const _CertEditorPage({
    required this.tenantId,
    required this.memberFirestoreDocId,
    required this.template,
    this.corOverride,
    this.corTextoOverride,
    required this.nomeIgreja,
    required this.logoUrl,
    required this.logoFetchCandidates,
    this.tenantData,
    required this.nomeMembro,
    required this.cpfFormatado,
    required this.tituloCtrl,
    required this.subtituloCtrl,
    required this.textoCtrl,
    required this.textoAdicionalCtrl,
    required this.localCtrl,
    required this.dataCertCtrl,
    required this.pastorCtrl,
    required this.cargoCtrl,
    required this.signatoryOptions,
    required this.initialSelectedSignatoryIds,
    required this.initialLayoutId,
    required this.initialFontStyleId,
    required this.initialSignatureMode,
    required this.initialVisualTemplateId,
  });

  @override
  State<_CertEditorPage> createState() => _CertEditorPageState();
}

class _CertEditorPageState extends State<_CertEditorPage> {
  bool _generating = false;
  late List<String> _selectedSignatoryIds;
  final Map<String, String> _selectedCargoByMemberId = <String, String>{};
  String _fontStyleId = 'moderna';
  String _signatureMode = 'digital';
  late String _visualTemplateId;
  bool _includeInstitutionalPastorSignature = true;

  Future<String?>? _previewLogoResolvedFuture;
  String _previewLogoResolveSig = '';
  Future<String?>? _previewTemplateBgFuture;
  String _previewTemplateBgSig = '';

  Color get _cor => widget.corOverride ?? widget.template.cor;
  Color get _corTexto => widget.corTextoOverride ?? const Color(0xFF1E1E1E);

  TextStyle _previewNomeMembroStyle() {
    switch (_fontStyleId) {
      case 'classica':
        return GoogleFonts.greatVibes(
          fontSize: 28,
          color: _corTexto,
        );
      case 'gotica':
        return GoogleFonts.unifrakturMaguntia(
          fontSize: 22,
          color: _corTexto,
        );
      default:
        return GoogleFonts.pinyonScript(
          fontSize: 22,
          color: const Color(0xFF5C3D1E),
        );
    }
  }

  void _refreshTemplateBgFuture() {
    final vt = certificateVisualTemplateById(_visualTemplateId);
    final sig = '${widget.tenantId}|${vt?.storageStem ?? ''}';
    if (_previewTemplateBgSig == sig && _previewTemplateBgFuture != null) {
      return;
    }
    _previewTemplateBgSig = sig;
    _previewTemplateBgFuture = _resolveTemplateBgDownloadUrl();
  }

  Future<String?> _resolveTemplateBgDownloadUrl() async {
    final vt = certificateVisualTemplateById(_visualTemplateId);
    if (vt == null) return null;
    for (final path in ChurchStorageLayout.certificateTemplateBackgroundPaths(
        widget.tenantId, vt.storageStem)) {
      try {
        final u = await FirebaseStorage.instance.ref(path).getDownloadURL();
        if (u.isNotEmpty) return sanitizeImageUrl(u);
      } catch (_) {}
    }
    return null;
  }

  void _refreshPreviewLogoFuture() {
    final sig =
        '${widget.tenantId}\u241e${widget.logoUrl}\u241e${widget.logoFetchCandidates.join('\u241f')}\u241e${churchTenantLogoUrl(widget.tenantData ?? {})}\u241e${ChurchImageFields.logoStoragePath(widget.tenantData) ?? ''}';
    if (_previewLogoResolveSig == sig && _previewLogoResolvedFuture != null) {
      return;
    }
    _previewLogoResolveSig = sig;
    _previewLogoResolvedFuture = _resolvePreviewDisplayLogoUrl();
  }

  Future<String?> _resolvePreviewDisplayLogoUrl() async {
    Future<String?> tryHttps(String s) async {
      final norm = sanitizeImageUrl(s);
      if (!isValidImageUrl(norm)) return null;
      if (!(norm.startsWith('http://') || norm.startsWith('https://'))) {
        return norm;
      }
      final r =
          await AppStorageImageService.instance.resolveImageUrl(imageUrl: norm);
      final out = r != null ? sanitizeImageUrl(r) : '';
      if (out.isNotEmpty && isValidImageUrl(out)) return out;
      return norm;
    }

    for (final u in widget.logoFetchCandidates) {
      final raw = u.trim();
      if (raw.isEmpty) continue;
      final s = sanitizeImageUrl(raw);
      if (isValidImageUrl(s)) {
        final got = await tryHttps(s);
        if (got != null) return got;
      }
      if (firebaseStorageMediaUrlLooksLike(raw) &&
          !raw.toLowerCase().startsWith('http')) {
        final path = normalizeFirebaseStorageObjectPath(
            raw.replaceFirst(RegExp(r'^/+'), ''));
        if (path.isNotEmpty) {
          final r = await AppStorageImageService.instance.resolveChurchTenantLogoUrl(
            tenantId: widget.tenantId,
            tenantData: widget.tenantData,
            preferStoragePath: path,
          );
          if (r != null && r.trim().isNotEmpty) return sanitizeImageUrl(r);
        }
      }
    }
    final fb = sanitizeImageUrl(widget.logoUrl);
    if (isValidImageUrl(fb)) {
      final got = await tryHttps(fb);
      if (got != null) return got;
    }
    return AppStorageImageService.instance.resolveChurchTenantLogoUrl(
      tenantId: widget.tenantId,
      tenantData: widget.tenantData,
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedSignatoryIds = List.from(widget.initialSelectedSignatoryIds);
    if (_selectedSignatoryIds.isEmpty && widget.signatoryOptions.isNotEmpty) {
      _selectedSignatoryIds = [widget.signatoryOptions.first.memberId];
    }
    for (final o in widget.signatoryOptions) {
      _selectedCargoByMemberId[o.memberId] = o.cargo;
    }
    _fontStyleId =
        _certFontStyleOptions.any((e) => e.id == widget.initialFontStyleId)
            ? widget.initialFontStyleId
            : 'moderna';
    _signatureMode = widget.initialSignatureMode == 'manual' ? 'manual' : 'digital';
    _visualTemplateId = certificateVisualTemplateById(
                widget.initialVisualTemplateId)
            ?.id ??
        'classico_dourado';
    _refreshPreviewLogoFuture();
    _refreshTemplateBgFuture();
  }

  @override
  void dispose() {
    widget.tituloCtrl.dispose();
    widget.subtituloCtrl.dispose();
    widget.textoCtrl.dispose();
    widget.textoAdicionalCtrl.dispose();
    widget.localCtrl.dispose();
    widget.dataCertCtrl.dispose();
    widget.pastorCtrl.dispose();
    widget.cargoCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CertEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.logoUrl != widget.logoUrl ||
        !listEquals(oldWidget.logoFetchCandidates, widget.logoFetchCandidates) ||
        oldWidget.tenantData != widget.tenantData) {
      _refreshPreviewLogoFuture();
    }
  }

  List<_SignatoryOption> get _selectedSignatories {
    return widget.signatoryOptions
        .where((o) => _selectedSignatoryIds.contains(o.memberId))
        .toList();
  }

  List<_SignatoryOption> get _effectiveSignatories {
    if (_selectedSignatories.isEmpty) return const <_SignatoryOption>[];
    return _selectedSignatories
        .map(
          (o) => _SignatoryOption(
            memberId: o.memberId,
            nome: o.nome,
            cargo: (_selectedCargoByMemberId[o.memberId] ?? o.cargo).trim().isEmpty
                ? o.cargo
                : (_selectedCargoByMemberId[o.memberId] ?? o.cargo),
            cargoOptions: o.cargoOptions,
            assinaturaUrl: o.assinaturaUrl,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: _cor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: () => Navigator.maybePop(context),
        ),
        title:
            Text(t.nome, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Gerar PDF',
            style: IconButton.styleFrom(
                minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget)),
            onPressed: _generating ? null : _generatePdf,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview card — Super Premium
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: [
                    BoxShadow(
                        color: _cor.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12)),
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                  border: Border.all(color: _cor.withOpacity(0.25), width: 2),
                ),
                child: _buildGalaLuxoPreview(t),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              _SectionLabel(label: 'Título do Certificado'),
              _EditBox(
                  controller: widget.tituloCtrl,
                  onChanged: () => setState(() {})),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              _SectionLabel(
                  label:
                      'Versículo ou frase curta (sob o título no PDF; opcional)'),
              _EditBox(
                controller: widget.subtituloCtrl,
                maxLines: 2,
                hint: 'Deixe vazio para não exibir',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              _SectionLabel(label: 'Texto do Certificado'),
              _EditBox(
                  controller: widget.textoCtrl,
                  maxLines: 8,
                  onChanged: () => setState(() {})),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              _SectionLabel(
                  label: 'Texto adicional (mensagem personalizada)',
                  subtitle:
                      'Aparece no PDF após o texto principal, antes das assinaturas.',
              ),
              _EditBox(
                controller: widget.textoAdicionalCtrl,
                maxLines: 4,
                hint: 'Opcional — dedicatória, versículo extra, observações…',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionLabel(label: 'Local'),
                        _EditBox(
                            controller: widget.localCtrl,
                            hint: 'Cidade/Estado'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionLabel(
                            label: 'Data do certificado (emissão)'),
                        InkWell(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm),
                          onTap: () async {
                            final parsed =
                                _parseDateBr(widget.dataCertCtrl.text) ??
                                    DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: parsed,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => widget.dataCertCtrl.text =
                                  _formatDateBr(picked));
                            }
                          },
                          child: AbsorbPointer(
                            child: _EditBox(
                              controller: widget.dataCertCtrl,
                              hint: 'dd/mm/aaaa',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              _SectionLabel(
                label: 'Modelo visual (papel de fundo)',
                subtitle:
                    'Gala Luxo A4 paisagem + tipografia premium no PDF. Fundos HD no Storage.',
              ),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kCertificateVisualTemplates.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, vi) {
                    final vt = kCertificateVisualTemplates[vi];
                    final sel = _visualTemplateId == vt.id;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          setState(() {
                            _visualTemplateId = vt.id;
                            _refreshTemplateBgFuture();
                          });
                        },
                        child: Ink(
                          width: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: sel
                                  ? ThemeCleanPremium.primary
                                  : Colors.grey.shade300,
                              width: sel ? 2.5 : 1,
                            ),
                            gradient: LinearGradient(
                              colors: vt.previewGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                vt.nome,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Assinatura institucional do pastor'),
                subtitle: Text(
                  'Inclui a imagem de igrejas/{id}/configuracoes/assinatura.png no rodapé, '
                  'além dos signatários selecionados (se houver).',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                value: _includeInstitutionalPastorSignature,
                onChanged: (v) => setState(
                    () => _includeInstitutionalPastorSignature = v),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              _SectionLabel(label: 'Estilo da fonte'),
              DropdownButtonFormField<String>(
                value: _fontStyleId,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  ),
                ),
                items: _certFontStyleOptions
                    .map((o) => DropdownMenuItem<String>(
                          value: o.id,
                          child: Text(o.nome),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _fontStyleId = v);
                },
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              _SectionLabel(label: 'Modo de assinatura para impressão'),
              DropdownButtonFormField<String>(
                value: _signatureMode,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  ),
                ),
                items: const [
                  DropdownMenuItem<String>(
                    value: 'digital',
                    child: Text('Com assinatura digital no PDF'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'manual',
                    child: Text('Sem assinatura digital (assinar após imprimir)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _signatureMode = v);
                },
              ),
              const SizedBox(height: 6),
              Text(
                _signatureMode == 'manual'
                    ? 'O PDF sai com linhas e nomes para assinatura manual no papel.'
                    : 'O PDF sai com as imagens de assinatura cadastradas.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              if (widget.signatoryOptions.isNotEmpty) ...[
                _SectionLabel(label: 'Quem vai assinar (escolha um ou mais)'),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _selectedSignatoryIds
                                ..clear()
                                ..addAll(widget.signatoryOptions
                                    .map((e) => e.memberId));
                            }),
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: const Text('Marcar todos'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _selectedSignatoryIds.clear()),
                            icon: const Icon(Icons.layers_clear_rounded,
                                size: 18),
                            label: const Text('Limpar seleção'),
                          ),
                        ],
                      ),
                      Divider(height: 16, color: Colors.grey.shade300),
                      ...widget.signatoryOptions.map((o) {
                        final selected =
                            _selectedSignatoryIds.contains(o.memberId);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                if (!_selectedSignatoryIds.contains(o.memberId)) {
                                  _selectedSignatoryIds.add(o.memberId);
                                }
                              } else {
                                _selectedSignatoryIds.remove(o.memberId);
                              }
                            });
                          },
                          title: Text(o.nome,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(o.cargo,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        );
                      }),
                      ...widget.signatoryOptions
                          .where((o) =>
                              _selectedSignatoryIds.contains(o.memberId) &&
                              o.cargoOptions.length > 1)
                          .map((o) => Padding(
                                padding: const EdgeInsets.only(
                                    left: 38, right: 8, bottom: 8),
                                child: DropdownButtonFormField<String>(
                                  value: _selectedCargoByMemberId[o.memberId] ??
                                      o.cargoOptions.first,
                                  decoration: InputDecoration(
                                    labelText:
                                        'Cargo no certificado para ${o.nome}',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm),
                                    ),
                                  ),
                                  items: o.cargoOptions
                                      .map(
                                        (cargo) => DropdownMenuItem<String>(
                                          value: cargo,
                                          child: Text(cargo),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() {
                                      _selectedCargoByMemberId[o.memberId] = v;
                                    });
                                  },
                                ),
                              )),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (_selectedSignatoryIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Assinaturas no PDF: ${_selectedSignatoryIds.length} (conforme a seleção acima).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text(
                  'Marque uma ou mais pessoas. É preciso ter assinatura cadastrada em Membros → Editar (imagem) para aparecer no PDF.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
              ] else ...[
                _SectionLabel(label: 'Assinatura — Nome'),
                _EditBox(
                    controller: widget.pastorCtrl,
                    hint: 'Nome do pastor/líder'),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                _SectionLabel(label: 'Assinatura — Cargo'),
                _EditBox(
                    controller: widget.cargoCtrl,
                    hint: 'Ex: Pastor(a) Presidente'),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
              ],
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Em breve: opção de usar certificado digital (nuvem, token ou local) para assinatura no ato da emissão.',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _generating ? null : _generatePdf,
                  icon: _generating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded),
                  label: Text(
                      _generating ? 'Gerando...' : 'Gerar Certificado PDF',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  style: FilledButton.styleFrom(
                      backgroundColor: _cor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm))),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generatePdf() async {
    if (widget.signatoryOptions.isNotEmpty && _selectedSignatories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um signatário na lista (ou use os campos manuais abaixo se não houver opções).'),
        ),
      );
      return;
    }
    setState(() => _generating = true);
    final phase = ValueNotifier<String>(
        'Processando certificado 1 de 1 — preparando…');
    final pct = ValueNotifier<double>(0.02);
    final titleNv = ValueNotifier<String>('Gerando certificado');
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        return _CertificatePdfProgressShell(
          phase: phase,
          progress01: pct,
          title: titleNv,
          accent: _cor,
          showDigitalSigningLine: _signatureMode == 'digital',
        );
      },
    );
    try {
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('certificados')
          .set({
        'defaultSignatoryMemberIds': _selectedSignatoryIds,
        'defaultSignaturesCount': _selectedSignatoryIds.length,
        'certLayoutId': _certPdfLayoutId,
        'defaultFontStyleId': _fontStyleId,
        'defaultSignatureMode': _signatureMode,
        'defaultVisualTemplateId': _visualTemplateId,
        'includeInstitutionalPastorSignature':
            _includeInstitutionalPastorSignature,
      }, SetOptions(merge: true));
      final bytes = Uint8List.fromList(await _buildCertPdf(
        PdfPageFormat.a4,
        onProgress: (m, p) {
          phase.value = m;
          pct.value = p;
        },
      ));
      if (mounted) {
        await showPdfActions(context,
            bytes: bytes, filename: 'certificado.pdf');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e')));
      }
    } finally {
      if (mounted && nav.canPop()) nav.pop();
      phase.dispose();
      pct.dispose();
      titleNv.dispose();
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Prévia aproximada do layout Gala Luxo (paisagem + QR de rascunho).
  Widget _buildGalaLuxoPreview(_CertTemplate t) {
    final previewQrUrl = CertificadoConsultaUrl.protocolValidationUrl(
      '00000000-0000-4000-8000-000000000001',
    );
    final adicPreview = widget.textoAdicionalCtrl.text.trim();
    final bodyCore = _resolveCertificateText(
      widget.textoCtrl.text,
      issuedDate: widget.dataCertCtrl.text.trim(),
    );
    final bodyText =
        adicPreview.isEmpty ? bodyCore : '$bodyCore\n\n$adicPreview';
    final pastorNome = _effectiveSignatories.isNotEmpty
        ? _effectiveSignatories.first.nome
        : widget.pastorCtrl.text.trim();
    final pastorCargo = _effectiveSignatories.isNotEmpty
        ? _effectiveSignatories.first.cargo
        : widget.cargoCtrl.text.trim();

    Widget miniLogo() {
      const logoSz = 96.0;
      final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
      final cachePx = (logoSz * dpr).round().clamp(160, 512);
      return FutureBuilder<String?>(
        future: _previewLogoResolvedFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return SizedBox(
              width: logoSz,
              height: logoSz,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _cor.withValues(alpha: 0.75),
                  ),
                ),
              ),
            );
          }
          final raw = snap.data;
          final displayUrl =
              raw != null && raw.isNotEmpty ? sanitizeImageUrl(raw) : '';
          final hasUrl =
              displayUrl.isNotEmpty && isValidImageUrl(displayUrl);
          if (!hasUrl) {
            return Icon(t.icon, size: 40, color: const Color(0xFFB8860B));
          }
          // URL já veio com token renovado de [AppStorageImageService] — evita segunda fila em [FreshFirebaseStorageImage] (web ficava no spinner).
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: logoSz,
              height: logoSz,
              child: SafeNetworkImage(
                imageUrl: displayUrl,
                fit: BoxFit.contain,
                width: logoSz,
                height: logoSz,
                memCacheWidth: cachePx,
                memCacheHeight: cachePx,
                skipFreshDisplayUrl: true,
                errorWidget: Icon(t.icon, size: 36),
                placeholder: SizedBox(
                  width: logoSz,
                  height: logoSz,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cor.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.clamp(260.0, 620.0);
        return Center(
          child: SizedBox(
            width: maxW,
            child: AspectRatio(
              aspectRatio: 297 / 210,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF6B4E16),
                      Color(0xFFC9A227),
                      Color(0xFFE8D060),
                      Color(0xFF8B6914),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(5),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFC9A227), width: 1.4),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Builder(
                          builder: (context) {
                            final vt = certificateVisualTemplateById(
                                _visualTemplateId);
                            final g = vt?.previewGradient ??
                                const [
                                  Color(0xFFFDF8F2),
                                  Color(0xFFF2E8D8),
                                ];
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: g,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned.fill(
                        child: FutureBuilder<String?>(
                          key: ValueKey<String>(
                              '${widget.tenantId}_$_visualTemplateId'),
                          future: _previewTemplateBgFuture,
                          builder: (ctx, snap) {
                            final displayUrl = snap.data ?? '';
                            if (displayUrl.isEmpty ||
                                !isValidImageUrl(displayUrl)) {
                              return const SizedBox();
                            }
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                FreshFirebaseStorageImage(
                                  imageUrl: displayUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 800,
                                  memCacheHeight: 600,
                                  errorWidget: const SizedBox(),
                                  placeholder: Container(
                                    color: Colors.white24,
                                  ),
                                ),
                                ColoredBox(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Positioned.fill(
                        child: FutureBuilder<String?>(
                          future: _previewLogoResolvedFuture,
                          builder: (ctx, snap) {
                            final raw = snap.data;
                            final displayUrl = raw != null && raw.isNotEmpty
                                ? sanitizeImageUrl(raw)
                                : '';
                            final hasUrl = displayUrl.isNotEmpty &&
                                isValidImageUrl(displayUrl);
                            if (!hasUrl) return const SizedBox();
                            return Center(
                              child: Opacity(
                                opacity: 0.06,
                                child: SafeNetworkImage(
                                  imageUrl: displayUrl,
                                  fit: BoxFit.contain,
                                  width: 220,
                                  height: 220,
                                  memCacheWidth: 440,
                                  memCacheHeight: 440,
                                  skipFreshDisplayUrl: true,
                                  errorWidget: const SizedBox(),
                                  placeholder: const SizedBox(),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 14, 62),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                miniLogo(),
                                if (widget.nomeIgreja.trim().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.nomeIgreja.toUpperCase(),
                                    style: GoogleFonts.libreBaskerville(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF5C3D1E),
                                      letterSpacing: 0.35,
                                      height: 1.2,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.tituloCtrl.text.toUpperCase(),
                              style: GoogleFonts.cinzelDecorative(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1E1E1E),
                                letterSpacing: 0.6,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.subtituloCtrl.text
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.subtituloCtrl.text.trim(),
                                style: GoogleFonts.lora(
                                  fontSize: 9,
                                  fontStyle: FontStyle.italic,
                                  color: const Color(0xFF333333),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              widget.nomeMembro,
                              style: _previewNomeMembroStyle().copyWith(
                                color: const Color(0xFF5C3D1E),
                                fontSize: _fontStyleId == 'moderna'
                                    ? 14
                                    : (_fontStyleId == 'gotica' ? 18.0 : 22.0),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  bodyText,
                                  style: GoogleFonts.libreBaskerville(
                                    fontSize: 8.5,
                                    height: 1.35,
                                    color: const Color(0xFF2D2D2D),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    height: 1,
                                    width: 100,
                                    color: const Color(0xFF5C3D1E),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    pastorNome,
                                    style: GoogleFonts.libreBaskerville(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF5C3D1E),
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    pastorCargo,
                                    style: GoogleFonts.libreBaskerville(
                                      fontSize: 7.5,
                                      color: const Color(0xFF8B6914),
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFC9A227),
                                  width: 2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: QrImageView(
                                data: previewQrUrl,
                                size: 44,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            if ([
                              widget.localCtrl.text.trim(),
                              widget.dataCertCtrl.text.trim(),
                            ].where((e) => e.isNotEmpty).join(', ').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, left: 2),
                                child: SizedBox(
                                  width: 108,
                                  child: Text(
                                    [
                                      widget.localCtrl.text.trim(),
                                      widget.dataCertCtrl.text.trim(),
                                    ].where((e) => e.isNotEmpty).join(', '),
                                    style: GoogleFonts.inter(
                                      fontSize: 7.5,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF8B6914),
                                    ),
                                    textAlign: TextAlign.left,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<int>> _buildCertPdf(
    PdfPageFormat format, {
    void Function(String message, double progress01)? onProgress,
  }) async {
    final selectedForPdf = _effectiveSignatories;
    final useDigitalSignature = _signatureMode == 'digital';
    final issuedDate = widget.dataCertCtrl.text.trim();
    final textoBase = _resolveCertificateText(
      widget.textoCtrl.text,
      issuedDate: issuedDate,
    );
    var institutionalNome =
        (widget.tenantData?['gestorNome'] ?? '').toString().trim();
    if (institutionalNome.isEmpty) {
      institutionalNome = widget.pastorCtrl.text.trim();
    }
    var institutionalCargo =
        (widget.tenantData?['gestorCargo'] ?? '').toString().trim();
    if (institutionalCargo.isEmpty) {
      institutionalCargo = widget.cargoCtrl.text.trim();
    }
    final protocolId = await CertificateEmitidoService.registerEmissao(
      tenantId: widget.tenantId,
      snapshot: <String, dynamic>{
        'memberId': widget.memberFirestoreDocId,
        'tipoCertificadoId': widget.template.id,
        'tipoCertificadoNome': widget.template.nome,
        'nomeMembro': widget.nomeMembro,
        'cpfFormatado': widget.cpfFormatado,
        'titulo': widget.tituloCtrl.text,
        'subtitulo': widget.subtituloCtrl.text.trim(),
        'textoCorpo': textoBase,
        'textoAdicional': widget.textoAdicionalCtrl.text.trim(),
        'local': widget.localCtrl.text,
        'nomeIgreja': widget.nomeIgreja,
        'issuedDateStr': issuedDate,
        'visualTemplateId': _visualTemplateId,
        'layoutId': _certPdfLayoutId,
        'fontStyleId': _fontStyleId,
        'colorPrimaryArgb': _cor.toARGB32(),
        'colorTextArgb': _corTexto.toARGB32(),
        'includeInstitutionalPastorSignature':
            _includeInstitutionalPastorSignature,
        'useDigitalSignature': useDigitalSignature,
        'pastorManual': widget.pastorCtrl.text,
        'cargoManual': widget.cargoCtrl.text,
        'institutionalPastorNome': institutionalNome,
        'institutionalPastorCargo': institutionalCargo,
        'signatariosSnapshot': <dynamic>[
          for (final s in selectedForPdf)
            <String, dynamic>{
              'memberId': s.memberId,
              'nome': s.nome,
              'cargo': s.cargo,
            },
        ],
      },
    );
    final qrUrl =
        CertificadoConsultaUrl.protocolValidationUrl(protocolId);
    final bytes = await runCertificatePdfPipeline(
      CertPdfPipelineParams(
        tenantId: widget.tenantId,
        logoFetchCandidates: widget.logoFetchCandidates,
        logoUrlFallback: widget.logoUrl,
        titulo: widget.tituloCtrl.text,
        subtitulo: widget.subtituloCtrl.text.trim(),
        texto: textoBase,
        textoAdicional: widget.textoAdicionalCtrl.text.trim(),
        visualTemplateId: _visualTemplateId,
        includeInstitutionalPastorSignature:
            _includeInstitutionalPastorSignature,
        institutionalPastorNome: institutionalNome,
        institutionalPastorCargo: institutionalCargo,
        nomeMembro: widget.nomeMembro,
        cpfFormatado: widget.cpfFormatado,
        nomeIgreja: widget.nomeIgreja,
        local: widget.localCtrl.text,
        issuedDate: issuedDate,
        layoutId: _certPdfLayoutId,
        fontStyleId: _fontStyleId,
        colorPrimaryArgb: _cor.toARGB32(),
        colorTextArgb: _corTexto.toARGB32(),
        pastorManual: widget.pastorCtrl.text,
        cargoManual: widget.cargoCtrl.text,
        useDigitalSignature: useDigitalSignature,
        qrValidationUrl: qrUrl,
        signatoriesForPdf: [
          for (final s in selectedForPdf)
            CertPdfPipelineSignatory(
              memberId: s.memberId,
              nome: s.nome,
              cargo: s.cargo,
              assinaturaUrlHint:
                  s.assinaturaUrl.isNotEmpty ? s.assinaturaUrl : null,
            ),
        ],
      ),
      onProgress: onProgress,
    );
    return bytes.toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ═══════════════════════════════════════════════════════════════════════════════

class _CertificadosEmitidosHistoricoView extends StatelessWidget {
  final String tenantId;
  final void Function(String certificadoId) onReprint;

  const _CertificadosEmitidosHistoricoView({
    required this.tenantId,
    required this.onReprint,
  });

  @override
  Widget build(BuildContext context) {
    final edge = ThemeCleanPremium.pagePadding(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: CertificateEmitidoService.historicoQuery(tenantId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: edge,
            child: Center(
              child: Text(
                'Não foi possível carregar o histórico.\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Padding(
            padding: edge,
            child: Center(
              child: Text(
                'Ainda não há emissões registadas. Ao gerar certificados, '
                'os protocolos aparecem aqui para consulta e reimpressão.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: edge.copyWith(top: 12, bottom: 24),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data();
            final nome = (d['nomeMembro'] ?? '').toString();
            final tipo =
                (d['tipoCertificadoNome'] ?? d['titulo'] ?? '').toString();
            final ts = d['dataEmissao'];
            var dataTxt = '—';
            if (ts is Timestamp) {
              dataTxt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                  .format(ts.toDate());
            }
            final cid = (d['certificadoId'] ?? doc.id).toString();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                title: Text(
                  nome.isEmpty ? '—' : nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${tipo.isEmpty ? 'Certificado' : tipo} · $dataTxt',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: IconButton(
                  tooltip: 'Reimprimir PDF',
                  icon: Icon(Icons.print_rounded,
                      color: ThemeCleanPremium.primary),
                  onPressed: () => onReprint(cid),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? subtitle;
  const _SectionLabel({required this.label, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700)),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditBox extends StatelessWidget {
  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  final VoidCallback? onChanged;

  const _EditBox(
      {required this.controller, this.maxLines = 1, this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => onChanged?.call(),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

String _formatCpf(String cpf) {
  final d = cpf.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return cpf;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

String _formatDateBr(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

DateTime? _parseDateBr(String raw) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw.trim());
  if (m == null) return null;
  final d = int.tryParse(m.group(1) ?? '');
  final mo = int.tryParse(m.group(2) ?? '');
  final y = int.tryParse(m.group(3) ?? '');
  if (d == null || mo == null || y == null) return null;
  if (y < 1900 || y > 2100 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

String _resolveCertificateText(String text, {required String issuedDate}) {
  if (issuedDate.trim().isEmpty) return text;
  return text.replaceAll('{DATA_CERTIFICADO}', issuedDate.trim());
}

/// Opção de signatário (membro elegível para assinar certificados).
class _SignatoryOption {
  final String memberId;
  final String nome;
  final String cargo;
  final List<String> cargoOptions;
  /// URL da assinatura (evita leitura extra no Firestore ao gerar o PDF).
  final String assinaturaUrl;
  const _SignatoryOption({
    required this.memberId,
    required this.nome,
    required this.cargo,
    this.cargoOptions = const [],
    this.assinaturaUrl = '',
  });
}
