import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/core/noticia_event_feed.dart'
    show noticiaDocEhEventoSpecialFeed;
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaPhotoUrls,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaVideosFromDoc,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaExternalVideoUrl,
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaVideoThumbUrl,
        looksLikeHostedVideoFileUrl,
        postFeedCarouselAspectRatioForIndex;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/video_handler_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        SafeNetworkImage,
        SafeCircleAvatarImage,
        FreshFirebaseStorageImage,
        dedupeImageRefsByStorageIdentity,
        firebaseStorageMediaUrlLooksLike,
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlFromMap,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        preloadNetworkImages,
        sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart';
import 'package:gestao_yahweh/ui/widgets/noticia_comments_bottom_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_feed_video.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_video_platform.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/firebase_storage_video_playback.dart';
import 'package:gestao_yahweh/ui/widgets/church_noticia_share_sheet.dart'
    show showChurchNoticiaShareSheet, shareRectFromContext;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show resolveNoticiaSharePreviewImageUrl;
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show buildNoticiaInviteShareMessage, resolveNoticiaHostedVideoShareUrl;

class EventsManagerPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Dentro do shell: sem AppBar azul duplicada; abas compactas no corpo.
  final bool embeddedInShell;

  /// Pré-preenche a busca do feed (ex.: busca global).
  final String? initialFeedSearchQuery;

  const EventsManagerPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
    this.initialFeedSearchQuery,
  });

  @override
  State<EventsManagerPage> createState() => _EventsManagerPageState();
}

class _EventsManagerPageState extends State<EventsManagerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, dynamic>? _tenantData;
  final GlobalKey<_FeedTabState> _feedTabKey = GlobalKey<_FeedTabState>();
  final GlobalKey<_FixosTabState> _fixosTabKey = GlobalKey<_FixosTabState>();

  /// Membro só visualiza o mural de eventos; edição fica com equipe (pastor, secretário, tesoureiro, etc.).
  bool get _canWrite {
    if (AppPermissions.isRestrictedMember(widget.role)) return false;
    final r = widget.role.toLowerCase();
    return r == 'adm' ||
        r == 'admin' ||
        r == 'gestor' ||
        r == 'master' ||
        r == 'lider' ||
        r == 'pastor' ||
        r == 'pastora' ||
        r == 'secretario' ||
        r == 'presbitero' ||
        r == 'tesoureiro' ||
        r == 'tesouraria' ||
        r == 'diacono' ||
        r == 'evangelista';
  }

  CollectionReference<Map<String, dynamic>> get _noticias =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('noticias');
  CollectionReference<Map<String, dynamic>> get _templates =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('event_templates');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _canWrite ? 3 : 1, vsync: this);
    _loadTenant();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadTenant() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .get();
      if (mounted) setState(() => _tenantData = snap.data());
    } catch (_) {}
  }

  String get _nomeIgreja =>
      (_tenantData?['name'] ?? _tenantData?['nome'] ?? '').toString();
  String get _logoUrl => imageUrlFromMap(_tenantData);

  Future<void> _novoEvento(
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => _EventoFormPage(
                tenantId: widget.tenantId, noticias: _noticias, doc: doc)));
    if (result == true && mounted) {
      _feedTabKey.currentState?._refresh();
      setState(() {});
      _feedTabKey.currentState?._refresh();
    }
  }

  Future<void> _excluirEvento(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final nome = (doc.data()?['title'] ?? doc.id).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir evento'),
        content: Text('Deseja excluir "$nome"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await _noticias.doc(doc.id).delete();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Evento excluído.'));
    }
  }

  Future<void> _deleteTemplate(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final nome = (doc.data()?['title'] ?? doc.id).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir evento fixo'),
        content: Text(
            'Deseja excluir "$nome"? O evento fixo será removido e não aparecerá mais na lista.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Evento fixo excluído.'));
        _fixosTabKey.currentState?._refresh();
      }
    }
  }

  Future<void> _editTemplate(
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? {};
    final titleCtrl =
        TextEditingController(text: (data['title'] ?? '').toString());
    final dow = ValueNotifier<int>((data['weekday'] ?? 7) as int);
    final timeCtrl =
        TextEditingController(text: (data['time'] ?? '19:30').toString());
    final locCtrl =
        TextEditingController(text: (data['location'] ?? '').toString());
    final recurrence =
        ValueNotifier<String>((data['recurrence'] ?? 'weekly').toString());
    // Mesma extração do feed/eventos: imageUrls (lista ou mapas), imageUrl, defaultImageUrl, fotos, etc.
    final urls = _eventImageUrlsFromData(data);
    final initialPhoto = urls.isNotEmpty ? urls.first : '';
    final defaultPhotoUrl = ValueNotifier<String>(initialPhoto);
    final tenantId = widget.tenantId;

    Future<void> fillLocationFromCadastro() async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tenantId)
            .get();
        final d = snap.data() ?? {};
        final endereco = (d['endereco'] ?? '').toString().trim();
        if (endereco.isEmpty) {
          final rua = (d['rua'] ?? d['address'] ?? '').toString().trim();
          final bairro = (d['bairro'] ?? '').toString().trim();
          final cidade =
              (d['cidade'] ?? d['localidade'] ?? '').toString().trim();
          final estado = (d['estado'] ?? d['uf'] ?? '').toString().trim();
          final cep = (d['cep'] ?? '').toString().trim();
          final parts = <String>[];
          if (rua.isNotEmpty) parts.add(rua);
          if (bairro.isNotEmpty) parts.add(bairro);
          if (cidade.isNotEmpty && estado.isNotEmpty)
            parts.add('$cidade - $estado');
          else if (cidade.isNotEmpty) parts.add(cidade);
          if (cep.isNotEmpty) parts.add('CEP $cep');
          locCtrl.text = parts.join(', ');
        } else {
          locCtrl.text = endereco;
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Local preenchido com o endereço do cadastro da igreja.'));
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Cadastre o endereço em Cadastro da Igreja primeiro.'));
      }
    }

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(doc == null ? 'Novo Evento Fixo' : 'Editar Evento Fixo',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Título',
                          prefixIcon: Icon(Icons.title_rounded))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: ValueListenableBuilder<int>(
                            valueListenable: dow,
                            builder: (_, v, __) => DropdownButtonFormField<int>(
                                  value: v,
                                  decoration:
                                      const InputDecoration(labelText: 'Dia'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 1, child: Text('Seg')),
                                    DropdownMenuItem(
                                        value: 2, child: Text('Ter')),
                                    DropdownMenuItem(
                                        value: 3, child: Text('Qua')),
                                    DropdownMenuItem(
                                        value: 4, child: Text('Qui')),
                                    DropdownMenuItem(
                                        value: 5, child: Text('Sex')),
                                    DropdownMenuItem(
                                        value: 6, child: Text('Sáb')),
                                    DropdownMenuItem(
                                        value: 7, child: Text('Dom'))
                                  ],
                                  onChanged: (nv) => dow.value = nv ?? 7,
                                ))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: timeCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Horário'))),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: TextField(
                            controller: locCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Local (opcional)',
                                prefixIcon: Icon(Icons.location_on_outlined)))),
                    const SizedBox(width: 8),
                    TextButton.icon(
                        onPressed: () async {
                          await fillLocationFromCadastro();
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.business_rounded, size: 18),
                        label: const Text('Do cadastro')),
                  ]),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                      valueListenable: defaultPhotoUrl,
                      builder: (_, url, __) {
                        if (url.isNotEmpty) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Foto padrão escolhida',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700)),
                                const SizedBox(height: 8),
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SafeNetworkImage(
                                          imageUrl: url,
                                          width: 96,
                                          height: 96,
                                          fit: BoxFit.cover,
                                          placeholder: Container(
                                              width: 96,
                                              height: 96,
                                              color: Colors.grey.shade200,
                                              child: Icon(Icons.photo_rounded,
                                                  size: 36,
                                                  color: Colors.grey.shade400)),
                                          errorWidget: Container(
                                              width: 96,
                                              height: 96,
                                              color: Colors.grey.shade200,
                                              child: Icon(
                                                  Icons.broken_image_rounded,
                                                  size: 36,
                                                  color: Colors.grey.shade500)),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(
                                                'Esta foto aparece na lista de Eventos Fixos. O Feed não mistura com a rotina semanal.',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        Colors.grey.shade600)),
                                            const SizedBox(height: 8),
                                            OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.change_circle_rounded,
                                                    size: 18),
                                                label:
                                                    const Text('Trocar foto'),
                                                onPressed: () async {
                                                  final file =
                                                      await MediaHandlerService
                                                          .instance
                                                          .pickAndProcessImage(
                                                              source:
                                                                  ImageSource
                                                                      .gallery);
                                                  if (file == null ||
                                                      !ctx.mounted) return;
                                                  setSheetState(() {});
                                                  try {
                                                    await FirebaseAuth
                                                        .instance.currentUser
                                                        ?.getIdToken(true);
                                                    final bytes = await file
                                                        .readAsBytes();
                                                    final compressed =
                                                        await ImageHelper
                                                            .compressImage(
                                                      bytes,
                                                      minWidth: 800,
                                                      minHeight: 600,
                                                      quality: 70,
                                                    );
                                                    final templateStorageId =
                                                        doc?.id ??
                                                            DateTime.now()
                                                                .millisecondsSinceEpoch
                                                                .toString();
                                                    final ref = FirebaseStorage
                                                        .instance
                                                        .ref(
                                                            ChurchStorageLayout.eventTemplateCoverPath(
                                                                tenantId,
                                                                templateStorageId));
                                                    await ref.putData(
                                                        compressed,
                                                        SettableMetadata(
                                                            contentType:
                                                                'image/jpeg',
                                                            cacheControl:
                                                                'public, max-age=31536000'));
                                                    final downloadUrl =
                                                        await ref
                                                            .getDownloadURL();
                                                    FirebaseStorageCleanupService
                                                        .scheduleCleanupAfterEventTemplateCoverUpload(
                                                      tenantId: tenantId,
                                                      templateUniqueId:
                                                          templateStorageId,
                                                    );
                                                    if (ctx.mounted) {
                                                      defaultPhotoUrl.value =
                                                          downloadUrl;
                                                      setSheetState(() {});
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              ThemeCleanPremium
                                                                  .successSnackBar(
                                                                      'Foto enviada.'));
                                                    }
                                                  } catch (e) {
                                                    if (ctx.mounted)
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(SnackBar(
                                                              content: Text(
                                                                  'Erro ao enviar foto: $e'),
                                                              backgroundColor:
                                                                  ThemeCleanPremium
                                                                      .error));
                                                  }
                                                }),
                                          ])),
                                      IconButton(
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () {
                                            defaultPhotoUrl.value = '';
                                            setSheetState(() {});
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(ThemeCleanPremium
                                                    .successSnackBar(
                                                        'Foto removida.'));
                                          },
                                          tooltip: 'Remover foto'),
                                    ]),
                              ]);
                        }
                        return OutlinedButton.icon(
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 20),
                          label: const Text('Foto padrão (opcional)'),
                          onPressed: () async {
                            final file = await MediaHandlerService.instance
                                .pickAndProcessImage(
                                    source: ImageSource.gallery);
                            if (file == null || !ctx.mounted) return;
                            setSheetState(() {});
                            try {
                              await FirebaseAuth.instance.currentUser
                                  ?.getIdToken(true);
                              final bytes = await file.readAsBytes();
                              final compressed =
                                  await ImageHelper.compressImage(
                                bytes,
                                minWidth: 800,
                                minHeight: 600,
                                quality: 70,
                              );
                              final templateStorageId = doc?.id ??
                                  DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString();
                              final ref = FirebaseStorage.instance.ref(
                                  ChurchStorageLayout.eventTemplateCoverPath(
                                      tenantId, templateStorageId));
                              await ref.putData(
                                  compressed,
                                  SettableMetadata(
                                      contentType: 'image/jpeg',
                                      cacheControl:
                                          'public, max-age=31536000'));
                              final downloadUrl = await ref.getDownloadURL();
                              FirebaseStorageCleanupService
                                  .scheduleCleanupAfterEventTemplateCoverUpload(
                                tenantId: tenantId,
                                templateUniqueId: templateStorageId,
                              );
                              if (ctx.mounted) {
                                defaultPhotoUrl.value = downloadUrl;
                                setSheetState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                    ThemeCleanPremium.successSnackBar(
                                        'Foto enviada.'));
                              }
                            } catch (e) {
                              if (ctx.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('Erro ao enviar foto: $e'),
                                        backgroundColor:
                                            ThemeCleanPremium.error));
                            }
                          },
                        );
                      }),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                      valueListenable: recurrence,
                      builder: (_, v, __) => DropdownButtonFormField<String>(
                            value: v,
                            decoration:
                                const InputDecoration(labelText: 'Recorrência'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'weekly', child: Text('Semanal')),
                              DropdownMenuItem(
                                  value: 'biweekly', child: Text('Quinzenal')),
                              DropdownMenuItem(
                                  value: 'monthly', child: Text('Mensal'))
                            ],
                            onChanged: (nv) =>
                                recurrence.value = nv ?? 'weekly',
                          )),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Salvar'))),
                  ]),
                ]),
          ),
        ),
      ),
    );
    if (res != true) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 150));
    final now = Timestamp.now();
    final payload = <String, dynamic>{
      'title': titleCtrl.text.trim(),
      'weekday': dow.value,
      'time': timeCtrl.text.trim(),
      'location': locCtrl.text.trim(),
      'recurrence': recurrence.value,
      'active': true,
      'updatedAt': now,
    };
    if (defaultPhotoUrl.value.isNotEmpty) {
      final u = defaultPhotoUrl.value;
      payload['defaultImageUrl'] = u;
      payload['imageUrl'] = u;
      payload['imageUrls'] = <String>[u];
      payload['imagemUrl'] = u;
      payload['imagem_url'] = u;
    }
    if (doc == null) {
      payload['createdAt'] = now;
      payload['createdByUid'] = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _templates.add(payload);
    } else {
      await doc.reference.update(payload);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Evento fixo salvo.'));
      _fixosTabKey.currentState?._refresh();
    }
  }

  Future<void> _generateFromTemplate(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    final title = (data['title'] ?? '').toString();
    final defaultImageUrl =
        (data['defaultImageUrl'] ?? data['imageUrl'] ?? '').toString().trim();
    final daysCtrl = TextEditingController(text: '60');
    final useFullYear = ValueNotifier<bool>(false);
    final result = await showDialog<({bool ok, bool fullYear})>(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg)),
                title: const Text('Gerar eventos futuros'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Cria entradas em massa no banco (útil para relatórios). Esses itens não aparecem no Feed — o Feed é só para eventos especiais publicados manualmente.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: daysCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Próximos X dias'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: useFullYear.value,
                      onChanged: (v) {
                        useFullYear.value = v ?? false;
                        if (useFullYear.value) daysCtrl.text = '365';
                        setDialogState(() {});
                      },
                      title: const Text('Gerar pro ano todo'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () =>
                          Navigator.pop(ctx, (ok: false, fullYear: false)),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(
                          ctx, (ok: true, fullYear: useFullYear.value)),
                      child: const Text('Gerar')),
                ],
              ),
            ));
    if (result == null || !result.ok) return;
    final weekday = (data['weekday'] ?? 7) as int;
    final time = (data['time'] ?? '19:30').toString();
    final location = (data['location'] ?? '').toString();
    final recurrence = (data['recurrence'] ?? 'weekly').toString();
    final daysAhead =
        result.fullYear ? 365 : (int.tryParse(daysCtrl.text.trim()) ?? 60);
    final now = DateTime.now();
    final until = now.add(Duration(days: daysAhead));
    final tp = time.split(':');
    final hh = int.tryParse(tp.isNotEmpty ? tp[0] : '') ?? 19;
    final mm = int.tryParse(tp.length > 1 ? tp[1] : '') ?? 30;
    final dates = <DateTime>[];
    var cursor = _nextWeekday(now, weekday);
    while (cursor.isBefore(until)) {
      dates.add(DateTime(cursor.year, cursor.month, cursor.day, hh, mm));
      if (recurrence == 'biweekly')
        cursor = cursor.add(const Duration(days: 14));
      else if (recurrence == 'monthly')
        cursor = DateTime(cursor.year, cursor.month + 1, cursor.day);
      else
        cursor = cursor.add(const Duration(days: 7));
    }
    final batch = FirebaseFirestore.instance.batch();
    final tsNow = Timestamp.now();
    final imageUrls =
        defaultImageUrl.isNotEmpty ? <String>[defaultImageUrl] : <String>[];
    for (final dt in dates) {
      batch.set(_noticias.doc(), {
        'type': 'evento',
        'title': title,
        'text': '',
        'imageUrl': defaultImageUrl,
        'imageUrls': imageUrls,
        if (defaultImageUrl.isNotEmpty) 'imagemUrl': defaultImageUrl,
        if (defaultImageUrl.isNotEmpty) 'imagem_url': defaultImageUrl,
        'location': location,
        'videoUrl': '',
        'startAt': Timestamp.fromDate(dt),
        'templateId': doc.id,
        'generated': true,
        'active': true,
        'likes': <String>[],
        'rsvp': <String>[],
        'createdAt': tsNow,
        'updatedAt': tsNow,
      });
    }
    await batch.commit();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              '${dates.length} eventos gerados!'));
  }

  DateTime _nextWeekday(DateTime from, int weekday) {
    var d = DateTime(from.year, from.month, from.day);
    while (d.weekday != weekday) d = d.add(const Duration(days: 1));
    return d;
  }

  Future<void> _seedDefaults() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusLg)),
              title: const Text('Criar eventos padrão'),
              content: const Text(
                  'Cria eventos fixos comuns (oração, EBD, culto). Pode editar depois.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Criar'))
              ],
            ));
    if (ok != true) return;
    final now = Timestamp.now();
    final batch = FirebaseFirestore.instance.batch();
    for (final it in [
      {
        'title': 'Culto de Oração',
        'weekday': 1,
        'time': '19:30',
        'recurrence': 'weekly'
      },
      {
        'title': 'Campanha da Libertação',
        'weekday': 5,
        'time': '19:30',
        'recurrence': 'weekly'
      },
      {
        'title': 'Escola Dominical',
        'weekday': 7,
        'time': '09:00',
        'recurrence': 'weekly'
      },
      {
        'title': 'Culto da Família',
        'weekday': 7,
        'time': '19:00',
        'recurrence': 'weekly'
      }
    ]) {
      batch.set(_templates.doc(), {
        'title': it['title'],
        'weekday': it['weekday'],
        'time': it['time'],
        'location': '',
        'recurrence': it['recurrence'],
        'active': true,
        'createdAt': now,
        'updatedAt': now
      });
    }
    await batch.commit();
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(ThemeCleanPremium.successSnackBar('Padrões criados!'));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final showAppBar = !widget.embeddedInShell &&
        (!isMobile || Navigator.canPop(context));
    TabBar tabBarPrimary() => TabBar(
          controller: _tab,
          labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          unselectedLabelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: ThemeCleanPremium.navSidebarAccent,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Eventos Fixos'),
            Tab(text: 'Dashboard'),
          ],
        );
    TabBar tabBarLight() => TabBar(
          controller: _tab,
          labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          unselectedLabelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600),
          labelColor: ThemeCleanPremium.primary,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: ThemeCleanPremium.primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Eventos Fixos'),
            Tab(text: 'Dashboard'),
          ],
        );
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: !showAppBar
          ? null
          : AppBar(
              toolbarHeight: isMobile ? kToolbarHeight : 48,
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar')
                  : null,
              title: Text(
                'Mural de Eventos',
                style: TextStyle(
                    fontSize: isMobile ? 17 : 16,
                    fontWeight: FontWeight.w700),
              ),
              bottom: _canWrite
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(40),
                      child: SizedBox(height: 40, child: tabBarPrimary()),
                    )
                  : null,
            ),
      body: SafeArea(
          child: Column(children: [
        if (_canWrite && !showAppBar)
          Material(
            color: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shape: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            child: SizedBox(
              height: 44,
              child: tabBarLight(),
            ),
          ),
        Expanded(
            child: TabBarView(controller: _tab, children: [
          _FeedTab(
              key: _feedTabKey,
              tenantId: widget.tenantId,
              churchSlug: (_tenantData?['slug'] ?? _tenantData?['slugId'] ?? '')
                  .toString()
                  .trim(),
              noticias: _noticias,
              nomeIgreja: _nomeIgreja,
              logoUrl: _logoUrl,
              canWrite: _canWrite,
              onNovoEvento: () => _novoEvento(),
              onEditEvento: (doc) => _novoEvento(doc: doc),
              onDeleteEvento: _excluirEvento,
              initialFeedSearchQuery: widget.initialFeedSearchQuery),
          if (_canWrite)
            _FixosTab(
                key: _fixosTabKey,
                templates: _templates,
                canWrite: _canWrite,
                onEdit: _editTemplate,
                onDelete: _deleteTemplate,
                onGenerate: _generateFromTemplate,
                onSeed: _seedDefaults),
          if (_canWrite)
            _DashboardEventosTab(noticias: _noticias, canWrite: _canWrite),
        ])),
      ])),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _novoEvento(),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Novo evento'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Feed Tab — leitura pontual (.get()) para evitar INTERNAL ASSERTION FAILED (web/mobile).
// ═══════════════════════════════════════════════════════════════════════════════
class _FeedTab extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> noticias;
  final String nomeIgreja, logoUrl;
  final bool canWrite;
  final VoidCallback onNovoEvento;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onEditEvento,
      onDeleteEvento;
  final String churchSlug;
  final String? initialFeedSearchQuery;
  const _FeedTab(
      {super.key,
      required this.tenantId,
      this.churchSlug = '',
      required this.noticias,
      required this.nomeIgreja,
      required this.logoUrl,
      required this.canWrite,
      required this.onNovoEvento,
      required this.onEditEvento,
      required this.onDeleteEvento,
      this.initialFeedSearchQuery});

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _eventsFuture;
  String _filterPeriod = 'all';
  int _filterWeekday = 0;
  final _searchCtrl = TextEditingController();
  bool _selectMode = false;
  final Set<String> _selectedEventIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialFeedSearchQuery != null &&
        widget.initialFeedSearchQuery!.trim().isNotEmpty) {
      _searchCtrl.text = widget.initialFeedSearchQuery!.trim();
    }
    _eventsFuture = _loadEvents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadEvents() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 150));
    return widget.noticias
        .orderBy('startAt', descending: true)
        .limit(200)
        .get();
  }

  Future<void> _refresh() async {
    setState(() => _eventsFuture = _loadEvents());
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedEventIds.clear();
    });
  }

  Future<void> _deleteFeedRefs(
      List<DocumentReference<Map<String, dynamic>>> refs) async {
    if (refs.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nada para excluir.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir eventos'),
        content: Text('Deseja excluir ${refs.length} evento(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    const int chunkSize = 400; // limite seguro de batch
    for (var i = 0; i < refs.length; i += chunkSize) {
      final batch = FirebaseFirestore.instance.batch();
      final chunk = refs.sublist(
          i, i + chunkSize > refs.length ? refs.length : i + chunkSize);
      for (final r in chunk) {
        batch.delete(r);
      }
      await batch.commit();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Eventos excluídos.'));
      _selectedEventIds.clear();
      _selectMode = false;
      _eventsFuture = _loadEvents();
      setState(() {});
    }
  }

  Future<void> _deleteSelectedFeed() async {
    final ids = _selectedEventIds.toList();
    final refs = ids.map((id) => widget.noticias.doc(id)).toList();
    await _deleteFeedRefs(refs);
  }

  Future<void> _deleteByCurrentPeriod() async {
    final snap = await _loadEvents();
    final allDocs =
        snap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
    final docs = _applyFilters(allDocs, DateTime.now(), _filterPeriod,
        _filterWeekday, _searchCtrl.text);
    final refs = docs.map((d) => d.reference).toList();
    await _deleteFeedRefs(refs);
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
    String period,
    int weekday,
    String searchQuery,
  ) {
    // Feed = só eventos especiais (não rotina semanal nem cópias geradas).
    var out = docs.where(noticiaDocEhEventoSpecialFeed).where((d) {
      final v = d.data()['validUntil'];
      if (v == null) return true;
      if (v is Timestamp) return v.toDate().isAfter(now);
      return true;
    }).toList();
    if (period != 'all') {
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 7));
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final startLastMonth = DateTime(now.year, now.month - 1, 1);
      final endLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);
      final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);
      out = out.where((d) {
        DateTime? dt;
        try {
          dt = (d.data()['startAt'] as Timestamp).toDate();
        } catch (_) {}
        if (dt == null) return false;
        if (period == 'week')
          return !dt.isBefore(now) && dt.isBefore(endOfWeek);
        if (period == 'month')
          return dt.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              dt.isBefore(endOfMonth.add(const Duration(days: 1)));
        if (period == 'last_month')
          return !dt.isBefore(startLastMonth) && !dt.isAfter(endLastMonth);
        if (period == 'year')
          return !dt.isBefore(now) && !dt.isAfter(endOfYear);
        return true;
      }).toList();
    }
    if (weekday > 0 && weekday < 8) {
      out = out.where((d) {
        try {
          final dt = (d.data()['startAt'] as Timestamp).toDate();
          return dt.weekday == weekday;
        } catch (_) {
          return false;
        }
      }).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      out = out
          .where((d) =>
              (d.data()['title'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _eventsFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar os eventos',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          return const _FeedSkeleton();
        }
        final now = DateTime.now();
        final allDocs =
            snap.data!.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
        final docs = _applyFilters(
            allDocs, now, _filterPeriod, _filterWeekday, _searchCtrl.text);

        final preloadUrls = docs
            .take(8)
            .map((d) {
              final data = d.data();
              final photos = eventNoticiaPhotoUrls(data);
              if (photos.isNotEmpty) return photos.first;
              final thumb = eventNoticiaDisplayVideoThumbnailUrl(data);
              return (thumb ?? '').toString().trim();
            })
            .where((u) => u.isNotEmpty)
            .toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && preloadUrls.isNotEmpty) {
            preloadNetworkImages(context, preloadUrls, maxItems: 6);
          }
        });

        if (docs.isEmpty) {
          return ThemeCleanPremium.premiumEmptyState(
            icon: Icons.event_available_rounded,
            title: 'Nenhum evento ainda',
            subtitle:
                'Use o Feed para cultos especiais, campanhas e datas comemorativas. A programação semanal fica em Eventos Fixos.',
            action: widget.canWrite
                ? FilledButton.icon(
                    onPressed: widget.onNovoEvento,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('Criar primeiro evento'),
                  )
                : null,
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                ThemeCleanPremium.spaceMd,
                ThemeCleanPremium.spaceSm,
                ThemeCleanPremium.spaceMd,
                80),
            children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Buscar por evento',
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusMd)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _filterPeriod,
                                decoration: const InputDecoration(
                                    labelText: 'Período',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8)),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'all', child: Text('Todos')),
                                  DropdownMenuItem(
                                      value: 'week',
                                      child: Text('Esta semana')),
                                  DropdownMenuItem(
                                      value: 'month', child: Text('Este mês')),
                                  DropdownMenuItem(
                                      value: 'last_month',
                                      child: Text('Mês anterior')),
                                  DropdownMenuItem(
                                      value: 'year', child: Text('Este ano')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _filterPeriod = v ?? 'all'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: DropdownButtonFormField<int>(
                                value: _filterWeekday,
                                decoration: const InputDecoration(
                                    labelText: 'Dia',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8)),
                                items: const [
                                  DropdownMenuItem(
                                      value: 0, child: Text('Qualquer')),
                                  DropdownMenuItem(
                                      value: 1, child: Text('Seg')),
                                  DropdownMenuItem(
                                      value: 2, child: Text('Ter')),
                                  DropdownMenuItem(
                                      value: 3, child: Text('Qua')),
                                  DropdownMenuItem(
                                      value: 4, child: Text('Qui')),
                                  DropdownMenuItem(
                                      value: 5, child: Text('Sex')),
                                  DropdownMenuItem(
                                      value: 6, child: Text('Sáb')),
                                  DropdownMenuItem(
                                      value: 7, child: Text('Dom')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _filterWeekday = v ?? 0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _toggleSelectMode,
                              icon: Icon(
                                  _selectMode
                                      ? Icons.close_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 18),
                              label: Text(_selectMode
                                  ? 'Cancelar seleção'
                                  : 'Selecionar'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(
                                    0, ThemeCleanPremium.minTouchTarget),
                                side: BorderSide(
                                    color: ThemeCleanPremium.primary
                                        .withOpacity(0.25)),
                                backgroundColor: Colors.white,
                                foregroundColor: ThemeCleanPremium.primary,
                              ),
                            ),
                            if (_selectMode)
                              FilledButton.icon(
                                onPressed: _selectedEventIds.isEmpty
                                    ? null
                                    : _deleteSelectedFeed,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: Text(
                                    'Excluir (${_selectedEventIds.length})'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.error,
                                  minimumSize: const Size(
                                      0, ThemeCleanPremium.minTouchTarget),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                ),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _deleteByCurrentPeriod,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Excluir por período'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.error,
                                  minimumSize: const Size(
                                      0, ThemeCleanPremium.minTouchTarget),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ...docs.map((d) {
                    final selected = _selectedEventIds.contains(d.id);
                    return Stack(
                      children: [
                        _EventoPost(
                          tenantId: widget.tenantId,
                          churchSlug: widget.churchSlug,
                          doc: d,
                          nomeIgreja: widget.nomeIgreja,
                          logoUrl: widget.logoUrl,
                          canWrite: widget.canWrite,
                          selectionMode: _selectMode,
                          onEdit: () => widget.onEditEvento(d),
                          onDelete: () => widget.onDeleteEvento(d),
                        ),
                        if (_selectMode)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: SizedBox(
                              width: ThemeCleanPremium.minTouchTarget,
                              height: ThemeCleanPremium.minTouchTarget,
                              child: Checkbox(
                                value: selected,
                                onChanged: (_) {
                                  setState(() {
                                    if (selected) {
                                      _selectedEventIds.remove(d.id);
                                    } else {
                                      _selectedEventIds.add(d.id);
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Stories Bar — estilo Instagram
// ═══════════════════════════════════════════════════════════════════════════════
class _StoriesBar extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String nomeIgreja, logoUrl, tenantId;
  final CollectionReference<Map<String, dynamic>> noticias;
  const _StoriesBar(
      {required this.docs,
      required this.nomeIgreja,
      required this.logoUrl,
      required this.noticias,
      required this.tenantId});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 96,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        itemCount: docs.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _StoryCircle(
                  label: 'Sua Igreja',
                  imageUrl: logoUrl,
                  isFirst: true,
                  onTap: () {}),
            );
          }
          final d = docs[i - 1].data();
          final title = (d['title'] ?? '').toString();
          final imgs = _eventImageUrlsFromData(d);
          final thumbV = eventNoticiaDisplayVideoThumbnailUrl(d);
          var img = imgs.isNotEmpty ? imgs.first : '';
          if (img.isEmpty && thumbV != null && thumbV.isNotEmpty) img = thumbV;
          if (img.isEmpty) img = (d['imageUrl'] ?? '').toString();
          if (img.isNotEmpty && looksLikeHostedVideoFileUrl(img)) {
            img = thumbV ?? '';
          }
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _StoryCircle(
              label: title.length > 10 ? '${title.substring(0, 10)}...' : title,
              imageUrl: img,
              onTap: () => _openStory(context, docs[i - 1]),
            ),
          );
        },
      ),
    );
  }

  void _openStory(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = (data['title'] ?? '').toString();
    final text = (data['text'] ?? '').toString();
    final imgs = _eventImageUrlsFromData(data);
    final displayThumbAll = eventNoticiaDisplayVideoThumbnailUrl(data) ?? '';
    var img = imgs.isNotEmpty ? imgs.first : '';
    if (img.isEmpty && displayThumbAll.isNotEmpty) img = displayThumbAll;
    if (img.isEmpty) img = (data['imageUrl'] ?? '').toString();
    if (img.isNotEmpty && looksLikeHostedVideoFileUrl(img))
      img = displayThumbAll;
    final loc = (data['location'] ?? '').toString();
    DateTime? dt;
    try {
      dt = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    final dateStr = dt != null
        ? '${_wn(dt.weekday)}, ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        onVerticalDragEnd: (_) => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
              child: Stack(children: [
            Builder(builder: (ctx2) {
              final vidPlay = eventNoticiaHostedVideoPlayUrl(data);
              final extVid = eventNoticiaExternalVideoUrl(data);
              final storyThumb =
                  eventNoticiaDisplayVideoThumbnailUrl(data) ?? '';
              if (isValidImageUrl(img)) {
                return Center(
                  child: SafeNetworkImage(
                    imageUrl: sanitizeImageUrl(img),
                    fit: BoxFit.contain,
                    placeholder: const Center(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54),
                      ),
                    ),
                    errorWidget: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_rounded,
                              size: 64, color: Colors.white54),
                          const SizedBox(height: 16),
                          Text('Falha ao carregar foto',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (vidPlay != null && vidPlay.isNotEmpty) {
                Future<void> openVid() async {
                  final u = Uri.tryParse(vidPlay.startsWith('http')
                      ? vidPlay
                      : 'https://$vidPlay');
                  if (u != null && await canLaunchUrl(u)) {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  }
                }

                if (isValidImageUrl(storyThumb)) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: openVid,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SafeNetworkImage(
                                  imageUrl: sanitizeImageUrl(storyThumb),
                                  fit: BoxFit.cover,
                                  placeholder: Container(
                                      color: Colors.black54,
                                      child: const Center(
                                          child: SizedBox(
                                              width: 40,
                                              height: 40,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white54)))),
                                  errorWidget: Container(
                                      color: const Color(0xFF1E3A8A),
                                      child: Icon(
                                          Icons.play_circle_filled_rounded,
                                          color: Colors.white.withOpacity(0.9),
                                          size: 72)),
                                ),
                                Container(color: Colors.black38),
                                const Center(
                                    child: Icon(Icons.play_circle_fill_rounded,
                                        size: 72, color: Colors.white)),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 10,
                                  child: Text(title,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          shadows: [
                                            Shadow(
                                                blurRadius: 8,
                                                color: Colors.black54)
                                          ]),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: openVid,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_filled_rounded,
                              color: Colors.white.withOpacity(0.95), size: 72),
                          const SizedBox(height: 16),
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          Text('Toque para assistir ao vídeo',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (extVid != null && extVid.isNotEmpty) {
                Future<void> openExt() async {
                  final u = Uri.tryParse(
                      extVid.startsWith('http') ? extVid : 'https://$extVid');
                  if (u != null && await canLaunchUrl(u)) {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  }
                }

                if (isValidImageUrl(storyThumb)) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: openExt,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SafeNetworkImage(
                                  imageUrl: sanitizeImageUrl(storyThumb),
                                  fit: BoxFit.cover,
                                  placeholder: Container(
                                      color: Colors.black54,
                                      child: const Center(
                                          child: SizedBox(
                                              width: 40,
                                              height: 40,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white54)))),
                                  errorWidget: Container(
                                      color:
                                          Colors.red.shade900.withOpacity(0.4),
                                      child: Icon(Icons.ondemand_video_rounded,
                                          color: Colors.red.shade200,
                                          size: 64)),
                                ),
                                Container(color: Colors.black38),
                                Center(
                                    child: Icon(Icons.ondemand_video_rounded,
                                        color: Colors.red.shade200, size: 64)),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 10,
                                  child: Text('YouTube / Vimeo',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: openExt,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ondemand_video_rounded,
                              color: Colors.red.shade300, size: 72),
                          const SizedBox(height: 14),
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          Text('Toque para abrir no YouTube / Vimeo',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_rounded,
                          color: Colors.white70, size: 56),
                      const SizedBox(height: 16),
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }),
            Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Row(children: [
                  SafeCircleAvatarImage(
                      imageUrl: logoUrl.isNotEmpty ? logoUrl : null,
                      radius: 18,
                      fallbackIcon: Icons.church_rounded,
                      fallbackColor: Colors.white,
                      backgroundColor: Colors.white24),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(nomeIgreja.isNotEmpty ? nomeIgreja : 'Igreja',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        if (dateStr.isNotEmpty)
                          Text(dateStr,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                      ])),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48))),
                ])),
            Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (loc.isNotEmpty)
                        Row(children: [
                          const Icon(Icons.location_on_rounded,
                              color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                              child: Text(loc,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)))
                        ]),
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(text,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis)
                      ],
                    ])),
          ])),
        ),
      ),
    );
  }

  static String _wn(int w) => const [
        '',
        'Seg',
        'Ter',
        'Qua',
        'Qui',
        'Sex',
        'Sáb',
        'Dom'
      ][w.clamp(0, 7)];
}

class _StoryCircle extends StatelessWidget {
  final String label, imageUrl;
  final bool isFirst;
  final VoidCallback onTap;
  const _StoryCircle(
      {required this.label,
      required this.imageUrl,
      this.isFirst = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isFirst
                  ? null
                  : const LinearGradient(colors: [
                      Color(0xFF833AB4),
                      Color(0xFFE1306C),
                      Color(0xFFF77737)
                    ]),
              border: isFirst
                  ? Border.all(color: Colors.grey.shade300, width: 2)
                  : null,
            ),
            child: SafeCircleAvatarImage(
              imageUrl:
                  isValidImageUrl(imageUrl) ? sanitizeImageUrl(imageUrl) : null,
              radius: 25,
              fallbackIcon:
                  isFirst ? Icons.church_rounded : Icons.event_rounded,
              fallbackColor: Colors.grey.shade500,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

List<String> _eventImageUrlsFromData(Map<String, dynamic> data) =>
    eventNoticiaPhotoUrls(data);

/// Fotos do card do Feed sem repetir a capa/miniatura do vídeo (evita faixa cinza/branca + vídeo).
/// Índice da foto no doc original (para [eventNoticiaPhotoStoragePathAt]) a partir da URL filtrada.
int? _eventPhotoUrlIndexInDoc(Map<String, dynamic> data, String candidateUrl) {
  final target = sanitizeImageUrl(candidateUrl);
  if (target.isEmpty) return null;
  final photos = eventNoticiaPhotoUrls(data);
  for (var i = 0; i < photos.length; i++) {
    if (sanitizeImageUrl(photos[i]) == target) return i;
  }
  return null;
}

List<String> _eventFeedCardPhotoUrls(Map<String, dynamic> data) {
  final raw = _eventImageUrlsFromData(data);
  final thumbUrls = <String>{
    sanitizeImageUrl(eventNoticiaDisplayVideoThumbnailUrl(data) ?? ''),
    sanitizeImageUrl(eventNoticiaVideoThumbUrl(data) ?? ''),
  }..removeWhere((e) => e.isEmpty);
  final thumbPaths = <String>{};
  for (final u in thumbUrls) {
    final p = firebaseStorageObjectPathFromHttpUrl(u);
    if (p != null && p.isNotEmpty) {
      thumbPaths.add(normalizeFirebaseStorageObjectPath(p));
    }
  }
  return dedupeImageRefsByStorageIdentity(raw.where((u) {
    final s = sanitizeImageUrl(u);
    if (thumbUrls.contains(s)) return false;
    final p = firebaseStorageObjectPathFromHttpUrl(s);
    if (p != null && p.isNotEmpty &&
        thumbPaths.contains(normalizeFirebaseStorageObjectPath(p))) {
      return false;
    }
    return true;
  }).toList());
}

List<Map<String, String>> _eventVideosFromData(Map<String, dynamic> data) =>
    eventNoticiaVideosFromDoc(data);

// ═══════════════════════════════════════════════════════════════════════════════
// Post do Evento — Instagram completo (foto, vídeo, comentários)
// ═══════════════════════════════════════════════════════════════════════════════
class _EventoPost extends StatefulWidget {
  final String tenantId;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String nomeIgreja, logoUrl;
  final bool canWrite;
  final bool selectionMode;
  final VoidCallback onEdit, onDelete;
  final String churchSlug;
  const _EventoPost({
    required this.tenantId,
    this.churchSlug = '',
    required this.doc,
    required this.nomeIgreja,
    required this.logoUrl,
    required this.canWrite,
    this.selectionMode = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_EventoPost> createState() => _EventoPostState();
}

class _EventoPostState extends State<_EventoPost>
    with SingleTickerProviderStateMixin {
  bool _showHeart = false;
  int _carouselIndex = 0;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  Future<({String name, String photo})> _memberDisplay() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (name: 'Membro', photo: '');
    var name = user.displayName?.trim() ?? '';
    var photo = user.photoURL?.trim() ?? '';
    if (name.isEmpty) {
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final d = uDoc.data() ?? {};
        name = (d['nome'] ?? d['name'] ?? 'Membro').toString();
        photo = (d['fotoUrl'] ?? d['photoUrl'] ?? photo).toString();
      } catch (_) {
        name = 'Membro';
      }
    }
    return (name: name.isEmpty ? 'Membro' : name, photo: photo);
  }

  Future<void> _toggleLike() async {
    if (_myUid == null) return;
    final data = widget.doc.data() ?? {};
    final merged = NoticiaSocialService.mergedLikeUids(data);
    final liked = merged.contains(_myUid!);
    try {
      final m = await _memberDisplay();
      await NoticiaSocialService.toggleCurtida(
        tenantId: widget.tenantId,
        postId: widget.doc.id,
        uid: _myUid!,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyLiked: liked,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Não foi possível curtir agora.'),
        );
      }
    }
  }

  void _onDoubleTap() async {
    final data = widget.doc.data() ?? {};
    final merged = NoticiaSocialService.mergedLikeUids(data);
    final liked = _myUid != null && merged.contains(_myUid!);
    if (liked || _myUid == null) {
      setState(() => _showHeart = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showHeart = false);
      });
      return;
    }
    setState(() => _showHeart = true);
    await _toggleLike();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  Future<void> _toggleRsvp() async {
    if (_myUid == null) return;
    final data = widget.doc.data() ?? {};
    final rsvpList = List<String>.from(
        ((data['rsvp'] as List?) ?? []).map((e) => e.toString()));
    final rsvp = rsvpList.contains(_myUid!);
    try {
      final m = await _memberDisplay();
      await NoticiaSocialService.toggleConfirmacaoPresenca(
        tenantId: widget.tenantId,
        postId: widget.doc.id,
        uid: _myUid!,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyConfirmed: rsvp,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Não foi possível atualizar a confirmação.'),
        );
      }
    }
  }

  void _openComments() {
    showNoticiaCommentsBottomSheet(
      context,
      commentsRef: widget.doc.reference.collection('comentarios'),
      tenantId: widget.tenantId,
      canDelete: widget.canWrite,
    );
  }

  Future<void> _openShareSheet(Rect? shareOrigin) async {
    final data = widget.doc.data() ?? {};
    final title = (data['title'] ?? '').toString();
    final text = (data['text'] ?? '').toString();
    final loc = (data['location'] ?? '').toString();
    DateTime? dt;
    try {
      dt = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    final churchName = widget.nomeIgreja.trim().isNotEmpty
        ? widget.nomeIgreja.trim()
        : 'Nossa igreja';
    final slug = widget.churchSlug.trim();
    final inviteUrl = slug.isNotEmpty
        ? AppConstants.shareNoticiaIgrejaEventoUrl(slug, widget.doc.id)
        : AppConstants.shareNoticiaCardUrl(widget.tenantId, widget.doc.id);
    final publicSite = AppConstants.publicSiteShortUrl(slug);
    final elat = _eventPostParseDouble(data['locationLat']);
    final elng = _eventPostParseDouble(data['locationLng']);
    final msg = buildNoticiaInviteShareMessage(
      churchName: churchName,
      noticiaKind: 'evento',
      title: title,
      bodyText: text,
      startAt: dt,
      location: loc.isNotEmpty ? loc : null,
      locationLat: elat,
      locationLng: elng,
      publicSiteUrl: publicSite,
      inviteCardUrl: inviteUrl,
    );
    final coverUrl = await resolveNoticiaSharePreviewImageUrl(data);
    final videoUrl = await resolveNoticiaHostedVideoShareUrl(data);
    if (!mounted) return;
    await showChurchNoticiaShareSheet(
      context,
      shareLink: inviteUrl,
      shareMessage: msg,
      shareSubject: 'Convite — $churchName',
      previewImageUrl: coverUrl,
      videoPlayUrl: videoUrl,
      sharePositionOrigin: shareOrigin,
    );
  }

  void _openFullScreen(List<String> images) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                _FullScreenGallery(images: images, initial: _carouselIndex)));
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}m';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}min';
    return 'agora';
  }

  Widget _buildEventFeedPhotoSlide({
    required Map<String, dynamic> data,
    required String imageUrl,
    required double w,
    required double h,
    required int memW,
    required int memH,
    required Widget Function() errorWidget,
  }) {
    final url = sanitizeImageUrl(imageUrl);
    final ph = Container(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ThemeCleanPremium.primary.withOpacity(0.6),
          ),
        ),
      ),
    );
    final err = errorWidget();
    final origIdx = _eventPhotoUrlIndexInDoc(data, imageUrl);
    final path = origIdx != null
        ? eventNoticiaPhotoStoragePathAt(data, origIdx)
        : null;
    if (path != null && path.trim().isNotEmpty) {
      return StableStorageImage(
        key: ValueKey('evt_st_${path}_$url'),
        storagePath: path,
        imageUrl: isValidImageUrl(url) ? url : null,
        gsUrl: url.toLowerCase().startsWith('gs://') ? url : null,
        width: w,
        height: h,
        fit: BoxFit.cover,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: ph,
        errorWidget: err,
      );
    }
    final storageLike = url.isNotEmpty &&
        (isFirebaseStorageHttpUrl(url) || firebaseStorageMediaUrlLooksLike(url));
    if (storageLike) {
      return FreshFirebaseStorageImage(
        key: ValueKey('evt_ff_$url'),
        imageUrl: url,
        fit: BoxFit.cover,
        width: w,
        height: h,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: ph,
        errorWidget: err,
      );
    }
    if (isValidImageUrl(url)) {
      return SafeNetworkImage(
        key: ValueKey('evt_sn_$url'),
        imageUrl: url,
        fit: BoxFit.cover,
        width: w,
        height: h,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: false,
      );
    }
    return err;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() ?? {};
    final mergedLikes = NoticiaSocialService.mergedLikeUids(data);
    final liked = _myUid != null && mergedLikes.contains(_myUid!);
    final likeCount = NoticiaSocialService.likeDisplayCount(data, mergedLikes);
    final rsvpUids = List<String>.from(
      ((data['rsvp'] as List?) ?? []).map((e) => e.toString()),
    );
    final rsvp = _myUid != null && rsvpUids.contains(_myUid!);
    final rsvpCount = NoticiaSocialService.rsvpDisplayCount(data, rsvpUids);
    final title = (data['title'] ?? '').toString();
    final text = (data['text'] ?? '').toString();
    final allImages = _eventFeedCardPhotoUrls(data);
    final hasImages = allImages.isNotEmpty;
    final location = (data['location'] ?? '').toString();
    final eventVideos = _eventVideosFromData(data);
    final videoUrl = eventVideos.isNotEmpty
        ? (eventVideos.first['videoUrl'] ?? '')
        : (data['videoUrl'] ?? '').toString().trim();
    final displayVideoThumb = eventNoticiaDisplayVideoThumbnailUrl(data) ?? '';
    final rawHosted = eventNoticiaHostedVideoPlayUrl(data) ?? '';
    final hostedVideoUrl = sanitizeImageUrl(rawHosted);
    final useHostedPlayer = hostedVideoUrl.isNotEmpty &&
        (hostedVideoUrl.startsWith('http://') ||
            hostedVideoUrl.startsWith('https://')) &&
        looksLikeHostedVideoFileUrl(hostedVideoUrl);
    var externalLaunchUrl = '';
    if (!useHostedPlayer) {
      final ext = eventNoticiaExternalVideoUrl(data);
      if (ext != null && ext.trim().isNotEmpty) {
        externalLaunchUrl = sanitizeImageUrl(ext.trim());
      } else if (videoUrl.isNotEmpty) {
        externalLaunchUrl = sanitizeImageUrl(videoUrl);
      }
    }
    final hasVideoRow = useHostedPlayer || externalLaunchUrl.isNotEmpty;

    DateTime? eventDt;
    try {
      eventDt = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    DateTime? createdDt;
    try {
      createdDt = (data['createdAt'] as Timestamp).toDate();
    } catch (_) {}
    final eventDateStr = eventDt != null
        ? '${_wn(eventDt.weekday)}, ${eventDt.day.toString().padLeft(2, '0')}/${eventDt.month.toString().padLeft(2, '0')}/${eventDt.year} às ${eventDt.hour.toString().padLeft(2, '0')}:${eventDt.minute.toString().padLeft(2, '0')}'
        : '';
    final createdAgo = createdDt != null ? _timeAgo(createdDt) : '';
    final isFuture = eventDt != null && eventDt.isAfter(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header (endereço vai para os links no fim do card)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  border: Border.all(
                      color: ThemeCleanPremium.primary.withOpacity(0.3),
                      width: 1.5)),
              child: SafeCircleAvatarImage(
                  imageUrl: widget.logoUrl.isNotEmpty ? widget.logoUrl : null,
                  radius: 19,
                  fallbackIcon: Icons.church_rounded,
                  fallbackColor: ThemeCleanPremium.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      widget.nomeIgreja.isNotEmpty
                          ? widget.nomeIgreja
                          : 'Igreja',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ])),
            if (widget.canWrite && !widget.selectionMode)
              PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      color: Colors.grey.shade700),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (v) {
                    if (v == 'edit') widget.onEdit();
                    if (v == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit',
                            child: Row(children: [
                              Icon(Icons.edit_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Editar')
                            ])),
                        PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Excluir',
                                  style: TextStyle(color: Colors.red))
                            ]))
                      ]),
          ]),
        ),
        // Título + data ficam só como barra fina sobre foto/vídeo (estilo avisos / EcoFire)
        // Fotos e vídeo (preview visível)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasImages)
              GestureDetector(
                onDoubleTap: widget.selectionMode ? null : _onDoubleTap,
                onTap: !widget.selectionMode
                    ? () => _openFullScreen(allImages)
                    : null,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    if (allImages.length == 1)
                      LayoutBuilder(
                        builder: (context, c) {
                          final w = c.maxWidth.isFinite && c.maxWidth > 0
                              ? c.maxWidth
                              : 400.0;
                          final ar = postFeedCarouselAspectRatioForIndex(
                              data, 0, allImages.length);
                          final h = w / ar;
                          final dpr = MediaQuery.devicePixelRatioOf(context);
                          final memW = (w * dpr).round().clamp(64, 2048);
                          final memH = (h * dpr).round().clamp(64, 2048);
                          return AspectRatio(
                            aspectRatio: ar,
                            child: _buildEventFeedPhotoSlide(
                              data: data,
                              imageUrl: allImages[0],
                              w: w,
                              h: h,
                              memW: memW,
                              memH: memH,
                              errorWidget: () => _eventImageErrorWithOverlay(
                                  title: title, dateStr: eventDateStr),
                            ),
                          );
                        },
                      ),
                    if (allImages.length > 1)
                      LayoutBuilder(
                        builder: (context, c) {
                          final w = c.maxWidth.isFinite && c.maxWidth > 0
                              ? c.maxWidth
                              : 400.0;
                          final ar = postFeedCarouselAspectRatioForIndex(
                              data, _carouselIndex, allImages.length);
                          final h = w / ar;
                          return AspectRatio(
                            aspectRatio: ar,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                PageView.builder(
                                  physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics()),
                                  padEnds: false,
                                  itemCount: allImages.length,
                                  onPageChanged: (p) =>
                                      setState(() => _carouselIndex = p),
                                  itemBuilder: (_, idx) {
                                    final dpr =
                                        MediaQuery.devicePixelRatioOf(context);
                                    final memW =
                                        (w * dpr).round().clamp(64, 2048);
                                    final memH =
                                        (h * dpr).round().clamp(64, 2048);
                                    return _buildEventFeedPhotoSlide(
                                      data: data,
                                      imageUrl: allImages[idx],
                                      w: w,
                                      h: h,
                                      memW: memW,
                                      memH: memH,
                                      errorWidget: () =>
                                          _eventImageErrorWithOverlay(
                                              title: title,
                                              dateStr: eventDateStr),
                                    );
                                  },
                                ),
                                Positioned(
                                  bottom: 44,
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Arraste para ver ${allImages.length} fotos',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if ((title.isNotEmpty || eventDateStr.isNotEmpty) &&
                        !widget.selectionMode)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: _EventMediaOverlayBar(
                              title: title, dateStr: eventDateStr),
                        ),
                      ),
                    AnimatedOpacity(
                      opacity: _showHeart ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.thumb_up_rounded,
                          color: Colors.white,
                          size: 80,
                          shadows: [
                            Shadow(blurRadius: 20, color: Colors.black38)
                          ]),
                    ),
                    if (allImages.length > 1)
                      Positioned(
                        bottom: 10,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            allImages.length,
                            (idx) => Container(
                              width: idx == _carouselIndex ? 8 : 6,
                              height: idx == _carouselIndex ? 8 : 6,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: idx == _carouselIndex
                                    ? ThemeCleanPremium.primary
                                    : Colors.white60,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!widget.selectionMode)
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Material(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.zoom_in_rounded,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text('Ampliar',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (hasVideoRow)
              Padding(
                padding:
                    EdgeInsets.only(top: hasImages ? 8 : 0, left: 4, right: 4),
                child: _EventVideoBlock(
                  title: title,
                  dateStr: eventDateStr,
                  hostedVideoUrl: useHostedPlayer ? hostedVideoUrl : '',
                  externalLaunchUrl: externalLaunchUrl,
                  thumbUrl: displayVideoThumb,
                ),
              ),
            if (!hasImages &&
                !hasVideoRow &&
                (title.isNotEmpty || eventDateStr.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFE2E8F0),
                                Colors.grey.shade100
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Icon(
                            Icons.event_rounded,
                            size: 44,
                            color: Colors.white.withValues(alpha: 0.95),
                            shadows: const [
                              Shadow(blurRadius: 14, color: Colors.black26)
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _EventMediaOverlayBar(
                              title: title, dateStr: eventDateStr),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            IconButton(
              onPressed: widget.selectionMode ? null : _toggleLike,
              icon: Icon(
                  liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  color:
                      liked ? ThemeCleanPremium.primary : Colors.grey.shade800,
                  size: 26),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
            IconButton(
              onPressed: widget.selectionMode ? null : _openComments,
              icon: Icon(Icons.forum_outlined,
                  color: Colors.grey.shade800, size: 24),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
            IconButton(
              onPressed: widget.selectionMode
                  ? null
                  : () {
                      final origin = shareRectFromContext(context);
                      _openShareSheet(origin);
                    },
              icon: Icon(Icons.share_rounded,
                  color: Colors.grey.shade800, size: 24),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
            const Spacer(),
            if (isFuture)
              Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.selectionMode ? null : _toggleRsvp,
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: rsvp
                              ? ThemeCleanPremium.success
                              : ThemeCleanPremium.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  ThemeCleanPremium.success.withOpacity(0.3))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            rsvp
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            size: 16,
                            color: rsvp
                                ? Colors.white
                                : ThemeCleanPremium.success),
                        const SizedBox(width: 4),
                        Text(rsvp ? 'Confirmado' : 'Participar',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: rsvp
                                    ? Colors.white
                                    : ThemeCleanPremium.success)),
                      ]),
                    ),
                  )),
          ]),
        ),
        // Likes + RSVP count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (likeCount > 0)
              Text('$likeCount curtida${likeCount > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            if (rsvpCount > 0 && isFuture)
              Text(
                  '$rsvpCount pessoa${rsvpCount > 1 ? 's' : ''} confirmou presença',
                  style: TextStyle(
                      fontSize: 12,
                      color: ThemeCleanPremium.success,
                      fontWeight: FontWeight.w600)),
          ]),
        ),
        // Texto de divulgação (título já está na faixa)
        if (text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SelectableText(
              text,
              style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500),
            ),
          ),
        // Convite, site público e mapa
        _EventPostLinksRow(
          tenantId: widget.tenantId,
          churchSlug: widget.churchSlug,
          shareInviteUrl: widget.churchSlug.trim().isNotEmpty
              ? AppConstants.shareNoticiaIgrejaEventoUrl(
                  widget.churchSlug, widget.doc.id)
              : AppConstants.shareNoticiaCardUrl(
                  widget.tenantId, widget.doc.id),
          eventLocation: location,
          eventLat: _eventPostParseDouble(data['locationLat']),
          eventLng: _eventPostParseDouble(data['locationLng']),
        ),
        // Link(s) do(s) vídeo(s)
        if (eventVideos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: eventVideos.asMap().entries.map((e) {
                final vUrl = e.value['videoUrl'] ?? '';
                if (vUrl.isEmpty) return const SizedBox.shrink();
                return InkWell(
                  onTap: () async {
                    final uri = Uri.tryParse(
                        vUrl.startsWith('http') ? vUrl : 'https://$vUrl');
                    if (uri != null && await canLaunchUrl(uri))
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_circle_filled_rounded,
                          size: 20, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                          eventVideos.length > 1
                              ? 'Vídeo ${e.key + 1}'
                              : 'Assistir vídeo',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        // Comments — link sem stream para evitar INTERNAL ASSERTION FAILED
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: GestureDetector(
              onTap: _openComments,
              child: Text('Ver comentários',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            )),
        // Time ago
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: Text(createdAgo.isNotEmpty ? 'há $createdAgo' : '',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400))),
      ]),
    );
  }

  static String _wn(int w) => const [
        '',
        'Seg',
        'Ter',
        'Qua',
        'Qui',
        'Sex',
        'Sáb',
        'Dom'
      ][w.clamp(0, 7)];
}

// ═══════════════════════════════════════════════════════════════════════════════
// Vídeo em tela cheia — Chewie (controles) no app; HTML5 na web.
// ═══════════════════════════════════════════════════════════════════════════════
class _FullScreenNetworkVideoPage extends StatelessWidget {
  final String videoUrl;
  final String title;
  final String? thumbnailUrl;
  const _FullScreenNetworkVideoPage({
    required this.videoUrl,
    this.title = '',
    this.thumbnailUrl,
  });

  Future<void> _openBrowser() async {
    final u = Uri.tryParse(videoUrl);
    if (u != null && await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoLayer = kIsWeb
        ? LayoutBuilder(
            builder: (context, c) {
              return Center(
                child: SizedBox(
                  width: c.maxWidth,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: buildPremiumHtmlVideo(
                        videoUrl,
                        autoplay: true,
                        muted: false,
                        loop: false,
                        controls: true,
                      ),
                    ),
                  ),
                ),
              );
            },
          )
        : Center(
            child: ChurchHostedVideoSurface(
              videoUrl: videoUrl,
              thumbnailUrl: thumbnailUrl,
              autoPlay: true,
            ),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: videoLayer),
          SafeArea(
            child: Stack(
              children: [
                if (title.isNotEmpty)
                  Positioned(
                    top: 4,
                    left: 12,
                    right: 56,
                    child: IgnorePointer(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                                blurRadius: 14,
                                color: Colors.black.withValues(alpha: 0.85))
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  right: 4,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 26),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Fechar',
                    ),
                  ),
                ),
                if (kIsWeb)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.outlined(
                              style: IconButton.styleFrom(
                                foregroundColor: Colors.white70,
                                minimumSize: const Size(
                                    ThemeCleanPremium.minTouchTarget,
                                    ThemeCleanPremium.minTouchTarget),
                              ),
                              onPressed: _openBrowser,
                              icon: const Icon(Icons.open_in_new_rounded),
                              tooltip: 'Navegador',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Vídeo hospedado: foto/vídeo em destaque + barra fina no topo + toque → tela cheia (EcoFire)
// ═══════════════════════════════════════════════════════════════════════════════
class _HostedVideoInlinePanel extends StatefulWidget {
  final String videoUrl;
  final String thumbUrl;
  final String title;
  final String dateStr;
  const _HostedVideoInlinePanel(
      {required this.videoUrl,
      required this.thumbUrl,
      required this.title,
      required this.dateStr});

  @override
  State<_HostedVideoInlinePanel> createState() =>
      _HostedVideoInlinePanelState();
}

class _HostedVideoInlinePanelState extends State<_HostedVideoInlinePanel> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _posterLoading = false;

  /// EcoFire: URL fresca do Storage para pré-carregar vídeo (web + mobile).
  String? _resolvedVideoUrl;

  void _listener() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _posterLoading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAndInit());
  }

  Future<void> _resolveAndInit() async {
    if (!mounted || widget.videoUrl.trim().isEmpty) {
      if (mounted) setState(() => _posterLoading = false);
      return;
    }
    try {
      final resolved =
          await resolveFirebaseStorageVideoPlayUrl(widget.videoUrl);
      if (!mounted) return;
      if (resolved.isEmpty || Uri.tryParse(resolved) == null) {
        setState(() {
          _posterLoading = false;
          _failed = true;
        });
        return;
      }
      setState(() => _resolvedVideoUrl = resolved);
      if (kIsWeb) {
        setState(() => _posterLoading = false);
        return;
      }
      final safeThumb = sanitizeImageUrl(widget.thumbUrl);
      if (isValidImageUrl(safeThumb)) {
        setState(() => _posterLoading = false);
        return;
      }
      final controller = networkVideoControllerForUrl(resolved);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.pause();
      controller.addListener(_listener);
      setState(() {
        _c = controller;
        _posterLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _posterLoading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_listener);
    _c?.dispose();
    super.dispose();
  }

  Future<void> _openFullscreen() async {
    _c?.pause();
    if (!mounted) return;
    final t = sanitizeImageUrl(widget.thumbUrl);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullScreenNetworkVideoPage(
          videoUrl: widget.videoUrl,
          title: widget.title,
          thumbnailUrl: isValidImageUrl(t) ? t : null,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final safeThumb = sanitizeImageUrl(widget.thumbUrl);
    final useThumb = isValidImageUrl(safeThumb);
    final resolved = _resolvedVideoUrl ?? '';
    /// Web: sempre player HTML no feed (igual Instagram mural / site divulgação). Antes só sem thumb —
    /// com miniatura Storage falhava no canvas e virava cinza + play.
    final webHostedPlayer =
        kIsWeb && resolved.isNotEmpty && !_failed;
    final thumbOrPosterReady =
        useThumb || (_c != null && _c!.value.isInitialized);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: const Color(0xFF0F172A),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                if (webHostedPlayer)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusLg),
                      child: PremiumHtmlFeedVideo(
                        videoUrl: widget.videoUrl,
                        visibilityKey:
                            'emgr_${identityHashCode(this)}',
                        showControls: true,
                        posterUrl: useThumb ? safeThumb : null,
                        startLoadingImmediately: true,
                        videoObjectFitContain: false,
                      ),
                    ),
                  )
                else if (_c != null && _c!.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _c!.value.size.width,
                      height: _c!.value.size.height,
                      child: VideoPlayer(_c!),
                    ),
                  )
                else if (useThumb)
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final h = c.maxHeight;
                      final dpr = MediaQuery.devicePixelRatioOf(context);
                      return SafeNetworkImage(
                        key: ValueKey(safeThumb),
                        imageUrl: safeThumb,
                        fit: BoxFit.cover,
                        width: w,
                        height: h,
                        memCacheWidth: (w * dpr).round().clamp(64, 1920),
                        memCacheHeight: (h * dpr).round().clamp(64, 1920),
                        placeholder: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.grey.shade800,
                                const Color(0xFF0F172A)
                              ],
                            ),
                          ),
                          child: const Center(
                              child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white38))),
                        ),
                        errorWidget: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.grey.shade700,
                              const Color(0xFF0F172A)
                            ]),
                          ),
                          child: Center(
                              child: Icon(Icons.videocam_off_rounded,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  size: 40)),
                        ),
                      );
                    },
                  )
                else if (_posterLoading)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.grey.shade800,
                        const Color(0xFF0F172A)
                      ]),
                    ),
                    child: const Center(
                        child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white38))),
                  )
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.grey.shade700,
                        const Color(0xFF0F172A)
                      ]),
                    ),
                    child: Center(
                        child: Icon(Icons.play_circle_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 56)),
                  ),
                if (widget.title.isNotEmpty || widget.dateStr.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: _EventMediaOverlayBar(
                          title: widget.title, dateStr: widget.dateStr),
                    ),
                  ),
                if (_failed)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          final u = Uri.tryParse(widget.videoUrl);
                          if (u != null && await canLaunchUrl(u)) {
                            await launchUrl(u,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.open_in_browser_rounded,
                            color: Colors.white, size: 20),
                        label: const Text('Abrir vídeo',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: 'Tela cheia',
                      icon: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white, size: 22),
                      onPressed: _openFullscreen,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
                  ),
                ),
                if (!_failed &&
                    !webHostedPlayer &&
                    !_posterLoading &&
                    thumbOrPosterReady)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openFullscreen,
                      child: Center(
                        child: Icon(Icons.play_circle_rounded,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.92)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
          child: Text(
            webHostedPlayer
                ? 'Controles do navegador · ícone Tela cheia para ampliar'
                : 'Toque no vídeo para abrir em tela cheia nesta mesma sessão',
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bloco de vídeo do evento — Storage: player inline; YouTube/link: abre rápido
// ═══════════════════════════════════════════════════════════════════════════════
class _EventVideoBlock extends StatelessWidget {
  final String title, dateStr;
  final String hostedVideoUrl;
  final String externalLaunchUrl;
  final String thumbUrl;

  const _EventVideoBlock({
    required this.title,
    required this.dateStr,
    this.hostedVideoUrl = '',
    this.externalLaunchUrl = '',
    this.thumbUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    if (hostedVideoUrl.isNotEmpty) {
      return _HostedVideoInlinePanel(
        videoUrl: hostedVideoUrl,
        thumbUrl: thumbUrl,
        title: title,
        dateStr: dateStr,
      );
    }

    final launch = externalLaunchUrl.trim();
    if (launch.isEmpty) {
      return const SizedBox.shrink();
    }
    final uri = Uri.tryParse(
        launch.startsWith('http://') || launch.startsWith('https://')
            ? launch
            : 'https://$launch');
    final safeThumb = sanitizeImageUrl(thumbUrl);
    final useThumb = isValidImageUrl(safeThumb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: const Color(0xFF1E3A8A),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            child: InkWell(
              onTap: () async {
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: useThumb
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth.isFinite && c.maxWidth > 0
                                ? c.maxWidth
                                : 400.0;
                            final h = c.maxHeight.isFinite && c.maxHeight > 0
                                ? c.maxHeight
                                : 225.0;
                            final dpr = MediaQuery.devicePixelRatioOf(context);
                            return SafeNetworkImage(
                              key: ValueKey(safeThumb),
                              imageUrl: safeThumb,
                              fit: BoxFit.cover,
                              width: w,
                              height: h,
                              memCacheWidth: (w * dpr).round().clamp(64, 1920),
                              memCacheHeight: (h * dpr).round().clamp(64, 1920),
                              placeholder: Container(
                                  color: const Color(0xFF1E3A8A),
                                  child: const Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white54))),
                              errorWidget:
                                  _externalVideoFallback(title, dateStr),
                            );
                          },
                        ),
                        Container(color: Colors.black26),
                        if (title.isNotEmpty || dateStr.isNotEmpty)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: _EventMediaOverlayBar(
                                  title: title, dateStr: dateStr),
                            ),
                          ),
                        Center(
                            child: Icon(Icons.play_circle_rounded,
                                size: 64,
                                color: Colors.white.withValues(alpha: 0.95))),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Abrir link',
                              icon: const Icon(Icons.open_in_new_rounded,
                                  color: Colors.white, size: 20),
                              onPressed: () async {
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                  minWidth: 44, minHeight: 44),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _externalVideoFallback(title, dateStr),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Toque para abrir no navegador (YouTube / Vimeo)',
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  static Widget _externalVideoFallback(String title, String dateStr) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
              ),
            ),
          ),
          if (title.isNotEmpty || dateStr.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _EventMediaOverlayBar(title: title, dateStr: dateStr),
              ),
            ),
          Center(
            child: Icon(Icons.play_circle_rounded,
                color: Colors.white.withValues(alpha: 0.88), size: 52),
          ),
        ],
      );
}

/// Erro de imagem no feed: fundo neutro + barra fina (sem faixa azul alta).
Widget _eventImageErrorWithOverlay(
    {required String title, required String dateStr}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: Colors.grey.shade300),
      if (title.isNotEmpty || dateStr.isNotEmpty)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _EventMediaOverlayBar(title: title, dateStr: dateStr),
        ),
      const Center(
          child:
              Icon(Icons.broken_image_rounded, size: 44, color: Colors.grey)),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Barra fina sobre foto/vídeo (título + data em uma linha) — estilo avisos / EcoFire
// ═══════════════════════════════════════════════════════════════════════════════
class _EventMediaOverlayBar extends StatelessWidget {
  final String title;
  final String dateStr;
  const _EventMediaOverlayBar({required this.title, required this.dateStr});

  @override
  Widget build(BuildContext context) {
    if (title.isEmpty && dateStr.isEmpty) return const SizedBox.shrink();
    final line = [
      if (title.isNotEmpty) title,
      if (dateStr.isNotEmpty) dateStr,
    ].join(' · ');
    return ClipRect(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.78),
              Colors.black.withValues(alpha: 0.4),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.event_rounded,
                color: Colors.white.withValues(alpha: 0.92), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  shadows: [
                    Shadow(
                        blurRadius: 10,
                        color: Colors.black.withValues(alpha: 0.65))
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double? _eventPostParseDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v != null) return double.tryParse(v.toString());
  return null;
}

/// Links rápidos: convite (OG), site público da igreja e mapa (evento ou cadastro).
class _EventPostLinksRow extends StatelessWidget {
  final String tenantId;
  final String churchSlug;
  final String shareInviteUrl;
  final String eventLocation;
  final double? eventLat;
  final double? eventLng;

  const _EventPostLinksRow({
    required this.tenantId,
    required this.churchSlug,
    required this.shareInviteUrl,
    required this.eventLocation,
    this.eventLat,
    this.eventLng,
  });

  @override
  Widget build(BuildContext context) {
    final slug = churchSlug.trim();
    final publicSite = AppConstants.publicSiteShortUrl(slug);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('igrejas').doc(tenantId).get(),
      builder: (context, snap) {
        double? lat = eventLat;
        double? lng = eventLng;
        final church = snap.data?.data();
        if (church != null) {
          if (lat == null) lat = _eventPostParseDouble(church['latitude']);
          if (lng == null) lng = _eventPostParseDouble(church['longitude']);
        }
        String? mapsUrl;
        if (lat != null && lng != null) {
          mapsUrl = AppConstants.mapsShortUrl(lat: lat, lng: lng);
        } else if (eventLocation.trim().isNotEmpty) {
          mapsUrl = AppConstants.mapsShortUrl(address: eventLocation.trim());
        } else if (church != null) {
          final end = (church['endereco'] ?? '').toString().trim();
          if (end.isNotEmpty) {
            mapsUrl = AppConstants.mapsShortUrl(address: end);
          }
        }

        Future<void> open(String url) async {
          final u = Uri.tryParse(url);
          if (u != null && await canLaunchUrl(u)) {
            await launchUrl(u, mode: LaunchMode.externalApplication);
          }
        }

        Widget chip(
            {required IconData icon,
            required String label,
            required String url}) {
          return Material(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => open(url),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: ThemeCleanPremium.primary),
                    const SizedBox(width: 8),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Convite (link)',
                  url: shareInviteUrl),
              chip(
                  icon: Icons.public_rounded,
                  label: 'Site público',
                  url: publicSite),
              if (mapsUrl != null)
                chip(
                    icon: Icons.map_rounded,
                    label: 'Localização',
                    url: mapsUrl),
            ],
          ),
        );
      },
    );
  }
}

// Galeria full screen: web usa HTTP+memory (FreshFirebaseStorageImage); fallback abrir no navegador.
class _ResilientGalleryImage extends StatelessWidget {
  final String imageUrl;
  const _ResilientGalleryImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = (mq.size.height - mq.padding.vertical - kToolbarHeight - 24)
        .clamp(200.0, mq.size.height);
    final dpr = mq.devicePixelRatio;
    final memW = (w * dpr).round().clamp(64, 4096);
    final memH = (h * dpr).round().clamp(64, 4096);
    return FreshFirebaseStorageImage(
      key: ValueKey(imageUrl),
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      width: w,
      height: h,
      memCacheWidth: memW,
      memCacheHeight: memH,
      placeholder: const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      ),
      errorWidget: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text('Falha ao carregar',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () async {
                final u = Uri.tryParse(imageUrl.trim());
                if (u != null && await canLaunchUrl(u)) {
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_browser_rounded,
                  color: Colors.white70),
              label: const Text('Abrir no navegador',
                  style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full Screen Gallery (zoom/pan)
// ═══════════════════════════════════════════════════════════════════════════════
class _FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initial;
  const _FullScreenGallery({required this.images, this.initial = 0});

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _ctrl = PageController(initialPage: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Voltar'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.images.length > 1
            ? Text('${_current + 1} / ${widget.images.length}',
                style: const TextStyle(fontSize: 14))
            : null,
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (p) => setState(() => _current = p),
        itemBuilder: (_, i) {
          final raw = widget.images[i].trim();
          final url = sanitizeImageUrl(raw);
          final valid = url.startsWith('http://') ||
              url.startsWith('https://') ||
              url.toLowerCase().startsWith('gs://') ||
              firebaseStorageMediaUrlLooksLike(url);
          if (!valid) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_rounded,
                      size: 64, color: Colors.white54),
                  const SizedBox(height: 16),
                  Text('Imagem indisponível',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              ),
            );
          }
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: _ResilientGalleryImage(imageUrl: url),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Skeleton Loading
// ═══════════════════════════════════════════════════════════════════════════════
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(top: 8), children: [
      Container(
          height: 100,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
              children: List.generate(
                  4,
                  (_) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(children: [
                        Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.shade200)),
                        const SizedBox(height: 6),
                        Container(
                            width: 40,
                            height: 8,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4))),
                      ]))))),
      const SizedBox(height: 8),
      for (var i = 0; i < 3; i++)
        Container(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.white,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade200)),
                    const SizedBox(width: 10),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 120,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 4),
                          Container(
                              width: 80,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4))),
                        ]),
                  ])),
              Container(
                  width: double.infinity,
                  height: 300,
                  color: Colors.grey.shade200),
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: 200,
                            height: 10,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4))),
                        const SizedBox(height: 8),
                        Container(
                            width: double.infinity,
                            height: 8,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4))),
                      ])),
            ])),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Formulário de Evento (com múltiplas imagens)
// ═══════════════════════════════════════════════════════════════════════════════
class _EventoFormPage extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> noticias;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  const _EventoFormPage(
      {required this.tenantId, required this.noticias, this.doc});

  @override
  State<_EventoFormPage> createState() => _EventoFormPageState();
}

class _EventoFormPageState extends State<_EventoFormPage> {
  late TextEditingController _title, _text, _videoUrl;
  late TextEditingController _cep,
      _logradouro,
      _numero,
      _bairro,
      _cidade,
      _uf,
      _quadraLote,
      _referencia;
  final List<String> _existingUrls = [];
  final List<Uint8List> _newImages = [];
  final List<String> _newNames = [];

  /// Vídeos enviados (máx. 2): cada um com videoUrl e thumbUrl para carregamento rápido.
  final List<Map<String, String>> _eventVideos = [];
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  DateTime? _validUntil;
  bool _publicSite = true;
  bool _saving = false;
  bool _uploadingVideo = false;
  bool _buscandoCep = false;

  /// Novo evento: mesmo id desde o init, para vídeos ficarem em paths estáveis `…/eventos/videos/{id}_v0.mp4`.
  late final DocumentReference<Map<String, dynamic>> _eventDocRef;

  /// Endereço da igreja (com lat/lng) vs. endereço manual por CEP.
  bool _useChurchLocation = false;
  String? _churchAddressText;
  double? _locationLat;
  double? _locationLng;
  static const int _maxVideoSeconds = 60;
  static const int _maxVideosPerEvent = 2;
  static const int _maxPhotosPerEvent = 20;

  static String _buildEnderecoFromTenant(Map<String, dynamic> data) {
    final endereco = (data['endereco'] ?? '').toString().trim();
    if (endereco.isNotEmpty) return endereco;
    final rua = (data['rua'] ?? data['address'] ?? '').toString().trim();
    final bairro = (data['bairro'] ?? '').toString().trim();
    final cidade =
        (data['cidade'] ?? data['localidade'] ?? '').toString().trim();
    final estado = (data['estado'] ?? data['uf'] ?? '').toString().trim();
    final cep = (data['cep'] ?? '').toString().trim();
    final parts = <String>[];
    if (rua.isNotEmpty) parts.add(rua);
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty && estado.isNotEmpty)
      parts.add('$cidade - $estado');
    else if (cidade.isNotEmpty)
      parts.add(cidade);
    else if (estado.isNotEmpty) parts.add(estado);
    if (cep.isNotEmpty) parts.add('CEP $cep');
    return parts.join(', ');
  }

  void _sairModoIgreja() {
    setState(() {
      _useChurchLocation = false;
      _churchAddressText = null;
      _locationLat = null;
      _locationLng = null;
    });
  }

  Future<void> _usarEnderecoIgreja() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .get();
      final data = snap.data() ?? {};
      final endereco = _buildEnderecoFromTenant(data);
      if (endereco.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Cadastre o endereço da igreja em Cadastro da Igreja primeiro.'),
          );
        }
        return;
      }
      final lat = data['latitude'];
      final lng = data['longitude'];
      if (mounted) {
        setState(() {
          _useChurchLocation = true;
          _churchAddressText = endereco;
          _locationLat = lat is num
              ? lat.toDouble()
              : (lat != null ? double.tryParse(lat.toString()) : null);
          _locationLng = lng is num
              ? lng.toDouble()
              : (lng != null ? double.tryParse(lng.toString()) : null);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Endereço da igreja selecionado. Use “Editar endereço manual” para trocar por CEP.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao carregar igreja: $e'),
            backgroundColor: ThemeCleanPremium.error));
      }
    }
  }

  static String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String _formatCepDisplay(String digits) {
    final d = _onlyDigits(digits);
    if (d.length <= 5) return d;
    return '${d.substring(0, 5)}-${d.substring(5, d.length.clamp(5, 8))}';
  }

  String _montarEnderecoManual() {
    final parts = <String>[];
    final rua = _logradouro.text.trim();
    final nume = _numero.text.trim();
    if (rua.isNotEmpty) {
      parts.add(nume.isNotEmpty ? '$rua, Nº $nume' : rua);
    } else if (nume.isNotEmpty) {
      parts.add('Nº $nume');
    }
    final qd = _quadraLote.text.trim();
    if (qd.isNotEmpty) parts.add('Qd/Lt $qd');
    final bairro = _bairro.text.trim();
    if (bairro.isNotEmpty) parts.add(bairro);
    final cid = _cidade.text.trim();
    final uf = _uf.text.trim();
    if (cid.isNotEmpty && uf.isNotEmpty) {
      parts.add('$cid - $uf');
    } else if (cid.isNotEmpty) {
      parts.add(cid);
    } else if (uf.isNotEmpty) {
      parts.add(uf);
    }
    final cep = _onlyDigits(_cep.text);
    if (cep.length == 8) parts.add('CEP ${_formatCepDisplay(cep)}');
    final ref = _referencia.text.trim();
    if (ref.isNotEmpty) parts.add('Ref.: $ref');
    return parts.join(', ');
  }

  String _localSalvo() {
    if (_useChurchLocation && (_churchAddressText ?? '').trim().isNotEmpty) {
      return _churchAddressText!.trim();
    }
    return _montarEnderecoManual();
  }

  Future<void> _buscarCep() async {
    final cep = _onlyDigits(_cep.text);
    if (cep.length != 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Informe um CEP com 8 dígitos.'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    setState(() => _buscandoCep = true);
    try {
      final uri = Uri.parse('https://viacep.com.br/ws/$cep/json/');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('CEP: erro HTTP ${res.statusCode}'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
        return;
      }
      final j = jsonDecode(res.body);
      if (j is! Map || j['erro'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('CEP não encontrado.'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
        return;
      }
      setState(() {
        _useChurchLocation = false;
        _churchAddressText = null;
        _locationLat = null;
        _locationLng = null;
        _logradouro.text = (j['logradouro'] ?? '').toString();
        _bairro.text = (j['bairro'] ?? '').toString();
        _cidade.text = (j['localidade'] ?? '').toString();
        _uf.text = (j['uf'] ?? '').toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'CEP encontrado. Complete número, quadra/lote e ponto de referência se quiser.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao buscar CEP: $e'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoCep = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _eventDocRef = widget.doc?.reference ?? widget.noticias.doc();
    final data = widget.doc?.data() ?? {};
    _title = TextEditingController(text: (data['title'] ?? '').toString());
    _text = TextEditingController(text: (data['text'] ?? '').toString());
    _videoUrl =
        TextEditingController(text: (data['videoUrl'] ?? '').toString());
    _cep = TextEditingController();
    _logradouro = TextEditingController();
    _numero = TextEditingController();
    _bairro = TextEditingController();
    _cidade = TextEditingController();
    _uf = TextEditingController();
    _quadraLote = TextEditingController();
    _referencia = TextEditingController();

    final locChurch = data['eventLocationSource'] == 'church';
    if (locChurch && (data['location'] ?? '').toString().trim().isNotEmpty) {
      _useChurchLocation = true;
      _churchAddressText = (data['location'] ?? '').toString().trim();
    } else {
      _cep.text = _formatCepDisplay(
          _onlyDigits((data['locationCep'] ?? '').toString()));
      _logradouro.text = (data['locationLogradouro'] ?? '').toString();
      _numero.text = (data['locationNumero'] ?? '').toString();
      _bairro.text = (data['locationBairro'] ?? '').toString();
      _cidade.text = (data['locationCidade'] ?? '').toString();
      _uf.text = (data['locationUf'] ?? '').toString();
      _quadraLote.text = (data['locationQuadraLote'] ?? '').toString();
      _referencia.text = (data['locationReferencia'] ?? '').toString();
      if (_logradouro.text.isEmpty && _cep.text.isEmpty) {
        final legacy = (data['location'] ?? '').toString().trim();
        if (legacy.isNotEmpty) _logradouro.text = legacy;
      }
    }
    final videosRaw = data['videos'];
    if (videosRaw is List && videosRaw.isNotEmpty) {
      for (final e in videosRaw) {
        if (_eventVideos.length >= _maxVideosPerEvent) break;
        if (e is Map) {
          final vUrl =
              (e['videoUrl'] ?? e['video_url'] ?? '').toString().trim();
          if (vUrl.isNotEmpty)
            _eventVideos.add({
              'videoUrl': vUrl,
              'thumbUrl':
                  (e['thumbUrl'] ?? e['thumb_url'] ?? '').toString().trim()
            });
        }
      }
    } else if ((data['videoUrl'] ?? '').toString().trim().isNotEmpty) {
      _eventVideos.add({
        'videoUrl': (data['videoUrl'] ?? '').toString().trim(),
        'thumbUrl': (data['thumbUrl'] ?? '').toString().trim()
      });
    }
    final lat = data['locationLat'];
    final lng = data['locationLng'];
    _locationLat = lat is num
        ? lat.toDouble()
        : (lat != null ? double.tryParse(lat.toString()) : null);
    _locationLng = lng is num
        ? lng.toDouble()
        : (lng != null ? double.tryParse(lng.toString()) : null);
    // Mesma extração do feed/painel: imageUrls (lista ou lista de mapas), imageUrl, defaultImageUrl, fotos, etc.
    final urls = _eventImageUrlsFromData(data);
    _existingUrls.addAll(urls);
    try {
      _date = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    try {
      final v = data['validUntil'];
      if (v is Timestamp) _validUntil = v.toDate();
    } catch (_) {}
    _publicSite = data['publicSite'] != false;
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _videoUrl.dispose();
    _cep.dispose();
    _logradouro.dispose();
    _numero.dispose();
    _bairro.dispose();
    _cidade.dispose();
    _uf.dispose();
    _quadraLote.dispose();
    _referencia.dispose();
    super.dispose();
  }

  /// [allowDeleteSentinels] só pode ser true com `set(..., SetOptions(merge: true))` ou `update`.
  /// `add()` / `set` sem merge rejeitam [FieldValue.delete] — causa [cloud_firestore/invalid-argument].
  Map<String, dynamic> _locationFieldsForSave(
      {required bool allowDeleteSentinels}) {
    final del = FieldValue.delete();
    if (_useChurchLocation) {
      final m = <String, dynamic>{
        'location': _localSalvo(),
        'eventLocationSource': 'church',
      };
      if (allowDeleteSentinels) {
        m.addAll({
          'locationCep': del,
          'locationLogradouro': del,
          'locationNumero': del,
          'locationBairro': del,
          'locationCidade': del,
          'locationUf': del,
          'locationQuadraLote': del,
          'locationReferencia': del,
        });
      }
      if (_locationLat != null && _locationLng != null) {
        m['locationLat'] = _locationLat;
        m['locationLng'] = _locationLng;
      } else if (allowDeleteSentinels) {
        m['locationLat'] = del;
        m['locationLng'] = del;
      }
      return m;
    }
    final manual = <String, dynamic>{
      'location': _localSalvo(),
      'eventLocationSource': 'manual',
      'locationCep': _onlyDigits(_cep.text),
      'locationLogradouro': _logradouro.text.trim(),
      'locationNumero': _numero.text.trim(),
      'locationBairro': _bairro.text.trim(),
      'locationCidade': _cidade.text.trim(),
      'locationUf': _uf.text.trim().toUpperCase(),
      'locationQuadraLote': _quadraLote.text.trim(),
      'locationReferencia': _referencia.text.trim(),
    };
    if (allowDeleteSentinels) {
      manual['locationLat'] = del;
      manual['locationLng'] = del;
    }
    return manual;
  }

  Future<void> _pickImages() async {
    final totalAtual = _existingUrls.length + _newImages.length;
    if (totalAtual >= _maxPhotosPerEvent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Limite de $_maxPhotosPerEvent fotos por evento. Remova alguma para adicionar mais.'),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    final files =
        await MediaHandlerService.instance.pickAndProcessMultipleImages();
    for (final f in files) {
      if (_existingUrls.length + _newImages.length >= _maxPhotosPerEvent) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Apenas as primeiras $_maxPhotosPerEvent fotos foram consideradas.'),
            backgroundColor: ThemeCleanPremium.error,
            behavior: SnackBarBehavior.floating,
          ));
        break;
      }
      final bytes = await f.readAsBytes();
      if (mounted)
        setState(() {
          _newImages.add(bytes);
          _newNames.add(f.name);
        });
    }
  }

  /// Deriva caminhos `igrejas/...` a partir das URLs (só Firebase Storage HTTPS).
  List<String>? _pathsFromImageUrls(List<String> urls) {
    final paths = <String>[];
    for (final u in urls) {
      final s = sanitizeImageUrl(u.trim());
      if (!isValidImageUrl(s)) return null;
      final p = firebaseStorageObjectPathFromHttpUrl(s);
      if (p == null || p.isEmpty) return null;
      paths.add(normalizeFirebaseStorageObjectPath(p));
    }
    return paths;
  }

  Future<MediaUploadResult> _upload(
      Uint8List bytes, String postDocId, int slotIndex) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final storagePath = ChurchStorageLayout.eventPostPhotoPath(
      widget.tenantId,
      postDocId,
      slotIndex,
    );
    return MediaUploadService.uploadBytesDetailed(
      storagePath: storagePath,
      bytes: bytes,
      contentType: 'image/jpeg',
    );
  }

  Widget _videoPlaceholder() => Container(
        width: 100,
        height: 100,
        color: Colors.grey.shade300,
        child: Icon(Icons.play_circle_outline_rounded,
            size: 40, color: Colors.grey.shade600),
      );

  /// Slot 0/1 explícito no path (`_v0.mp4`); legado sem sufixo → `null` (apenas apagar por URL).
  int? _hostedVideoStorageSlotFromUrl(String videoUrl) {
    final u = sanitizeImageUrl(videoUrl.trim());
    if (u.isEmpty || !isFirebaseStorageHttpUrl(u)) return null;
    final path = firebaseStorageObjectPathFromHttpUrl(u);
    if (path == null || path.isEmpty) return null;
    if (!path.contains('/eventos/videos/')) return null;
    final m = RegExp(r'_v(\d+)\.mp4$', caseSensitive: false).firstMatch(path);
    if (m != null) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null) return n.clamp(0, 1);
    }
    return null;
  }

  /// Próximo slot livre (0 ou 1). Vídeos legado em `videos/` sem `_vN` contam pelo índice na lista.
  int _nextHostedVideoStorageSlot() {
    final used = <int>{};
    for (var i = 0; i < _eventVideos.length; i++) {
      final url = (_eventVideos[i]['videoUrl'] ?? '').toString();
      final s = _hostedVideoStorageSlotFromUrl(url);
      if (s != null) {
        used.add(s);
      } else {
        final u = sanitizeImageUrl(url.trim());
        final p = firebaseStorageObjectPathFromHttpUrl(u) ?? '';
        if (u.isNotEmpty &&
            isFirebaseStorageHttpUrl(u) &&
            p.contains('/eventos/videos/')) {
          used.add(i.clamp(0, 1));
        }
      }
    }
    if (!used.contains(0)) return 0;
    if (!used.contains(1)) return 1;
    return -1;
  }

  Future<void> _removeEventVideoAt(int index) async {
    if (index < 0 || index >= _eventVideos.length) return;
    final v = _eventVideos[index];
    final videoUrl = (v['videoUrl'] ?? '').toString();
    final thumbUrl = (v['thumbUrl'] ?? '').toString();
    final slot = _hostedVideoStorageSlotFromUrl(videoUrl);
    if (slot != null) {
      await FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
        tenantId: widget.tenantId,
        postDocId: _eventDocRef.id,
        videoSlot: slot,
      );
    } else {
      await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
          [videoUrl, thumbUrl]);
    }
    if (mounted) setState(() => _eventVideos.removeAt(index));
  }

  Future<void> _pickAndUploadVideo() async {
    if (_uploadingVideo || _eventVideos.length >= _maxVideosPerEvent) {
      if (_eventVideos.length >= _maxVideosPerEvent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Limite atingido: cada evento pode ter no máximo $_maxVideosPerEvent vídeos de até $_maxVideoSeconds segundos.'),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    final snap = await _eventDocRef.get();
    final existing = _eventVideosFromData(snap.data() ?? {});
    if (existing.length >= _maxVideosPerEvent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Este evento já atingiu o limite de 2 vídeos. Remova um para adicionar outro.'),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    final slot = _nextHostedVideoStorageSlot();
    if (slot < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Limite de 2 vídeos no Storage. Remova um vídeo para adicionar outro.'),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() => _uploadingVideo = true);
    try {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Otimizando e enviando vídeo (máx. ${_maxVideoSeconds}s)...'));
      final result = await VideoHandlerService.instance.pickCompressAndUpload(
        tenantId: widget.tenantId,
        eventPostDocId: _eventDocRef.id,
        videoSlotIndex: slot,
        maxDuration: const Duration(seconds: 60),
      );
      if (result == null || !mounted) {
        setState(() => _uploadingVideo = false);
        return;
      }
      setState(() {
        _eventVideos
            .add({'videoUrl': result.videoUrl, 'thumbUrl': result.thumbUrl});
        _uploadingVideo = false;
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Vídeo anexado (máx. ${_maxVideoSeconds}s, até $_maxVideosPerEvent por evento).'));
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingVideo = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao enviar vídeo: $e'),
            backgroundColor: ThemeCleanPremium.error));
      }
    }
  }

  Future<void> _openAddMediaSheet() async {
    final photosFull =
        (_existingUrls.length + _newImages.length) >= _maxPhotosPerEvent;
    final videosFull = _eventVideos.length >= _maxVideosPerEvent;
    if (photosFull && videosFull) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Limite atingido: $_maxPhotosPerEvent fotos e $_maxVideosPerEvent vídeos. Remova itens ou use o link abaixo.',
          ),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Adicionar mídia',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Escolha se deseja enviar foto(s) ou um vídeo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF0FDF4),
                  child: Icon(Icons.photo_library_rounded,
                      color: Colors.green.shade700, size: 24),
                ),
                title: const Text('Foto(s)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  photosFull
                      ? 'Limite de $_maxPhotosPerEvent fotos atingido'
                      : 'Da galeria — Full HD comprimidas',
                  style: TextStyle(
                    fontSize: 12,
                    color: photosFull
                        ? ThemeCleanPremium.error
                        : Colors.grey.shade600,
                  ),
                ),
                enabled: !photosFull,
                onTap: photosFull
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _pickImages();
                      },
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: CircleAvatar(
                  backgroundColor:
                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.videocam_rounded,
                      color: ThemeCleanPremium.primary, size: 24),
                ),
                title: const Text('Vídeo (arquivo)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  _uploadingVideo
                      ? 'Aguarde o envio em andamento…'
                      : videosFull
                          ? 'Máx. $_maxVideosPerEvent vídeos por evento'
                          : 'Até 60 s — envio otimizado',
                  style: TextStyle(
                    fontSize: 12,
                    color: (_uploadingVideo || videosFull)
                        ? Colors.grey.shade500
                        : Colors.grey.shade600,
                  ),
                ),
                enabled: !_uploadingVideo && !videosFull,
                onTap: (_uploadingVideo || videosFull)
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _pickAndUploadVideo();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe o título.')));
      return;
    }
    setState(() => _saving = true);
    final docRef = _eventDocRef;
    final postId = docRef.id;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await Future.delayed(const Duration(milliseconds: 200));
      final allUrls = List<String>.from(_existingUrls);
      for (var i = 0; i < _newImages.length; i++) {
        if (allUrls.length >= _maxPhotosPerEvent) break;
        final slot = allUrls.length;
        final up = await _upload(_newImages[i], postId, slot);
        allUrls.add(up.downloadUrl);
      }
      if (allUrls.length > _maxPhotosPerEvent) {
        allUrls.removeRange(_maxPhotosPerEvent, allUrls.length);
      }
      final allUrlsSafe =
          allUrls.where((u) => !looksLikeHostedVideoFileUrl(u.trim())).toList();
      final firstUrl = allUrlsSafe.isNotEmpty ? allUrlsSafe[0] : '';
      final firstVideoUrl = _eventVideos.isNotEmpty
          ? (_eventVideos.first['videoUrl'] ?? '')
          : _videoUrl.text.trim();
      final firstThumbUrl =
          _eventVideos.isNotEmpty ? (_eventVideos.first['thumbUrl'] ?? '') : '';
      final videosClean = _eventVideos
          .map((e) => <String, dynamic>{
                'videoUrl': (e['videoUrl'] ?? '').toString().trim(),
                'thumbUrl': (e['thumbUrl'] ?? '').toString().trim(),
              })
          .where((m) => (m['videoUrl'] as String).isNotEmpty)
          .toList();
      final derivedPaths = _pathsFromImageUrls(allUrlsSafe);
      final payload = <String, dynamic>{
        'type': 'evento',
        'title': _title.text.trim(),
        'text': _text.text.trim(),
        'imageUrl': firstUrl,
        'imageUrls': allUrlsSafe,
        'defaultImageUrl': firstUrl,
        if (derivedPaths != null && derivedPaths.isNotEmpty) ...{
          'imageStoragePaths': derivedPaths,
          'imageStoragePath': derivedPaths.first,
        },
        'videoUrl': firstVideoUrl,
        'thumbUrl': firstThumbUrl,
        'videos': videosClean,
        'startAt': Timestamp.fromDate(_date),
        'active': true,
        'likes': widget.doc?.data()?['likes'] ?? <String>[],
        'rsvp': widget.doc?.data()?['rsvp'] ?? <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
        'generated': false,
        'publicSite': _publicSite,
        ..._locationFieldsForSave(allowDeleteSentinels: widget.doc != null),
      };
      if (firstUrl.isNotEmpty) {
        payload['imagemUrl'] = firstUrl;
        payload['imagem_url'] = firstUrl;
      } else if (widget.doc != null) {
        payload['imagemUrl'] = FieldValue.delete();
        payload['imagem_url'] = FieldValue.delete();
      }
      // Só em merge/update: remove mapas legados (thumb/card). Em `add()` não usar delete sentinel.
      if (widget.doc != null) {
        payload['imageVariants'] = FieldValue.delete();
      }
      if (_validUntil != null)
        payload['validUntil'] = Timestamp.fromDate(_validUntil!);
      if (widget.doc != null && widget.doc!.data()?['createdAt'] == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      if (widget.doc == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdByUid'] = FirebaseAuth.instance.currentUser?.uid ?? '';
        payload['likesCount'] = 0;
        payload['rsvpCount'] = 0;
        payload['commentsCount'] = 0;
        await docRef.set(payload);
      } else {
        payload['templateId'] = FieldValue.delete();
        await widget.doc!.reference.set(payload, SetOptions(merge: true));
      }
      if (_newImages.isNotEmpty) {
        FirebaseStorageCleanupService.scheduleCleanupAfterEventPostImageUpload(
          tenantId: widget.tenantId,
          postDocId: postId,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(widget.doc == null
                ? 'Evento publicado!'
                : 'Evento atualizado!'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      final msg = e.toString();
      final isAssertionOrPerm = msg.contains('INTERNAL ASSERTION') ||
          msg.contains('permission-denied');
      if (mounted && isAssertionOrPerm) {
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          await Future.delayed(const Duration(milliseconds: 400));
          if (widget.doc == null) {
            final retryUrls = List<String>.from(_existingUrls);
            for (var i = 0;
                i < _newImages.length && retryUrls.length < _maxPhotosPerEvent;
                i++) {
              final slot = retryUrls.length;
              final up = await _upload(_newImages[i], postId, slot);
              retryUrls.add(up.downloadUrl);
            }
            if (retryUrls.length > _maxPhotosPerEvent)
              retryUrls.removeRange(_maxPhotosPerEvent, retryUrls.length);
            final retrySafe = retryUrls
                .where((u) => !looksLikeHostedVideoFileUrl(u.trim()))
                .toList();
            final retryFirst = retrySafe.isNotEmpty ? retrySafe[0] : '';
            final retryDerived = _pathsFromImageUrls(retrySafe);
            final firstVideoUrl = _eventVideos.isNotEmpty
                ? (_eventVideos.first['videoUrl'] ?? '')
                : _videoUrl.text.trim();
            final firstThumbUrl = _eventVideos.isNotEmpty
                ? (_eventVideos.first['thumbUrl'] ?? '')
                : '';
            final vClean = _eventVideos
                .map((e) => <String, dynamic>{
                      'videoUrl': (e['videoUrl'] ?? '').toString().trim(),
                      'thumbUrl': (e['thumbUrl'] ?? '').toString().trim(),
                    })
                .where((m) => (m['videoUrl'] as String).isNotEmpty)
                .toList();
            final payload = <String, dynamic>{
              'type': 'evento',
              'title': _title.text.trim(),
              'text': _text.text.trim(),
              'imageUrl': retryFirst,
              'imageUrls': retrySafe,
              'defaultImageUrl': retryFirst,
              if (retryDerived != null && retryDerived.isNotEmpty) ...{
                'imageStoragePaths': retryDerived,
                'imageStoragePath': retryDerived.first,
              },
              if (retryFirst.isNotEmpty) 'imagemUrl': retryFirst,
              if (retryFirst.isNotEmpty) 'imagem_url': retryFirst,
              'videoUrl': firstVideoUrl,
              'thumbUrl': firstThumbUrl,
              'videos': vClean,
              'startAt': Timestamp.fromDate(_date),
              'active': true,
              'updatedAt': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
              'createdByUid': FirebaseAuth.instance.currentUser?.uid ?? '',
              'generated': false,
              'publicSite': _publicSite,
              'likes': <String>[],
              'rsvp': <String>[],
              'likesCount': 0,
              'rsvpCount': 0,
              'commentsCount': 0,
              ..._locationFieldsForSave(allowDeleteSentinels: false),
            };
            if (_validUntil != null)
              payload['validUntil'] = Timestamp.fromDate(_validUntil!);
            await docRef.set(payload);
            if (_newImages.isNotEmpty) {
              FirebaseStorageCleanupService
                  .scheduleCleanupAfterEventPostImageUpload(
                tenantId: widget.tenantId,
                postDocId: postId,
              );
            }
          } else {
            final retryUrls = List<String>.from(_existingUrls);
            for (var i = 0;
                i < _newImages.length && retryUrls.length < _maxPhotosPerEvent;
                i++) {
              final slot = retryUrls.length;
              final up = await _upload(_newImages[i], postId, slot);
              retryUrls.add(up.downloadUrl);
            }
            if (retryUrls.length > _maxPhotosPerEvent)
              retryUrls.removeRange(_maxPhotosPerEvent, retryUrls.length);
            final mergeSafe = retryUrls
                .where((u) => !looksLikeHostedVideoFileUrl(u.trim()))
                .toList();
            final mergeFirst = mergeSafe.isNotEmpty ? mergeSafe[0] : '';
            final mergeDerived = _pathsFromImageUrls(mergeSafe);
            final firstVideoUrl = _eventVideos.isNotEmpty
                ? (_eventVideos.first['videoUrl'] ?? '')
                : _videoUrl.text.trim();
            final firstThumbUrl = _eventVideos.isNotEmpty
                ? (_eventVideos.first['thumbUrl'] ?? '')
                : '';
            final vClean2 = _eventVideos
                .map((e) => <String, dynamic>{
                      'videoUrl': (e['videoUrl'] ?? '').toString().trim(),
                      'thumbUrl': (e['thumbUrl'] ?? '').toString().trim(),
                    })
                .where((m) => (m['videoUrl'] as String).isNotEmpty)
                .toList();
            final merge = <String, dynamic>{
              'type': 'evento',
              'title': _title.text.trim(),
              'text': _text.text.trim(),
              'imageUrl': mergeFirst,
              'imageUrls': mergeSafe,
              'defaultImageUrl': mergeFirst,
              if (mergeDerived != null && mergeDerived.isNotEmpty) ...{
                'imageStoragePaths': mergeDerived,
                'imageStoragePath': mergeDerived.first,
              },
              if (mergeFirst.isNotEmpty) 'imagemUrl': mergeFirst,
              if (mergeFirst.isNotEmpty) 'imagem_url': mergeFirst,
              'videoUrl': firstVideoUrl,
              'thumbUrl': firstThumbUrl,
              'videos': vClean2,
              'startAt': Timestamp.fromDate(_date),
              'updatedAt': FieldValue.serverTimestamp(),
              'generated': false,
              'publicSite': _publicSite,
              'imageVariants': FieldValue.delete(),
              ..._locationFieldsForSave(allowDeleteSentinels: true),
            };
            if (_validUntil != null)
              merge['validUntil'] = Timestamp.fromDate(_validUntil!);
            if (widget.doc!.data()?['createdAt'] == null) {
              merge['createdAt'] = FieldValue.serverTimestamp();
            }
            merge['templateId'] = FieldValue.delete();
            await widget.doc!.reference.set(merge, SetOptions(merge: true));
            if (_newImages.isNotEmpty) {
              FirebaseStorageCleanupService
                  .scheduleCleanupAfterEventPostImageUpload(
                tenantId: widget.tenantId,
                postDocId: postId,
              );
            }
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.successSnackBar('Evento publicado!'));
            Navigator.pop(context, true);
          }
        } catch (e2) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Erro: $e2'),
                backgroundColor: ThemeCleanPremium.error));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: ThemeCleanPremium.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPreviews = <Widget>[];
    for (var i = 0; i < _existingUrls.length; i++) {
      final idx = i;
      allPreviews.add(Stack(children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SafeNetworkImage(
                imageUrl: _existingUrls[idx],
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                placeholder: Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade200,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))),
                errorWidget: Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image_rounded,
                        color: Colors.grey)))),
        Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
                onTap: () => setState(() => _existingUrls.removeAt(idx)),
                child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white)))),
      ]));
    }
    for (var i = 0; i < _newImages.length; i++) {
      final idx = i;
      allPreviews.add(Stack(children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_newImages[idx],
                width: 100, height: 100, fit: BoxFit.cover)),
        Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
                onTap: () => setState(() {
                      _newImages.removeAt(idx);
                      _newNames.removeAt(idx);
                    }),
                child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white)))),
      ]));
    }

    final padding = ThemeCleanPremium.pagePadding(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final minTouch = ThemeCleanPremium.minTouchTarget;

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        toolbarHeight: 52,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(minimumSize: Size(minTouch, minTouch)),
        ),
        title: Text(widget.doc != null ? 'Editar Evento' : 'Novo Evento',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, color: Colors.white),
            label: Text(_saving ? 'Publicando...' : 'Publicar',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(minimumSize: Size(minTouch, minTouch)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right,
              padding.bottom + bottomInset),
          children: [
            // Fotos + vídeo — um único acionador (escolha no sheet)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.perm_media_rounded,
                            color: ThemeCleanPremium.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Fotos e vídeo',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Colors.grey.shade900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Toque em «Adicionar» para escolher foto(s) ou vídeo. Vídeo em arquivo: até 60 s. Ou cole link YouTube/Vimeo abaixo.',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ...allPreviews,
                      ...List.generate(_eventVideos.length, (i) {
                        final v = _eventVideos[i];
                        final thumbUrl = v['thumbUrl'] ?? '';
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: thumbUrl.isNotEmpty &&
                                      isValidImageUrl(thumbUrl)
                                  ? SafeNetworkImage(
                                      imageUrl: thumbUrl,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      placeholder: Container(
                                        width: 100,
                                        height: 100,
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                      ),
                                      errorWidget: _videoPlaceholder(),
                                    )
                                  : _videoPlaceholder(),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => unawaited(_removeEventVideoAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _uploadingVideo ? null : _openAddMediaSheet,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: _uploadingVideo
                                  ? Colors.grey.withValues(alpha: 0.15)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _uploadingVideo
                                    ? Colors.grey.shade300
                                    : ThemeCleanPremium.primary
                                        .withValues(alpha: 0.35),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _uploadingVideo
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Enviando…',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_rounded,
                                          color: ThemeCleanPremium.primary,
                                          size: 30),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Adicionar',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: ThemeCleanPremium.primary,
                                        ),
                                      ),
                                      Text(
                                        'foto ou vídeo',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _videoUrl,
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Link do vídeo (YouTube / Vimeo)',
                        prefixIcon: Icon(Icons.link_rounded),
                        hintText: 'https://...',
                        helperText:
                            'Opcional, se não usar vídeo em arquivo acima.',
                      ),
                    ),
                  ]),
            ),
            const SizedBox(height: 16),
            // Fields
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow),
              child: Column(children: [
                TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                        labelText: 'Título do evento *',
                        prefixIcon: Icon(Icons.title_rounded))),
                const SizedBox(height: 14),
                TextField(
                    controller: _text,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Descrição / legenda',
                        prefixIcon: Icon(Icons.notes_rounded),
                        alignLabelWithHint: true)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.place_rounded,
                        size: 22,
                        color: ThemeCleanPremium.primary.withOpacity(0.85)),
                    const SizedBox(width: 8),
                    Text('Local do evento (opcional)',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Colors.grey.shade800)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Use o CEP para preencher rua, bairro e cidade; complete número, quadra/lote e ponto de referência. Ou use o endereço cadastrado da igreja.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                if (_useChurchLocation &&
                    (_churchAddressText ?? '').trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.shade200),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Endereço da igreja',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade800,
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(_churchAddressText!.trim(),
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: Colors.grey.shade900)),
                        if (_locationLat != null && _locationLng != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                                'Coordenadas da igreja: link de mapa no compartilhamento.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700)),
                          ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _sairModoIgreja,
                              icon: Icon(Icons.edit_location_alt_rounded,
                                  size: 18, color: Colors.grey.shade800),
                              label: Text('Definir por CEP / manual',
                                  style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: Size(minTouch, minTouch),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12)),
                            ),
                            FilledButton.icon(
                              onPressed: _usarEnderecoIgreja,
                              icon: const Icon(Icons.refresh_rounded,
                                  size: 18, color: Colors.white),
                              label: const Text('Atualizar da igreja',
                                  style: TextStyle(color: Colors.white)),
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  minimumSize: Size(minTouch, minTouch)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cep,
                          keyboardType: TextInputType.number,
                          maxLength: 9,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'CEP',
                            hintText: '00000-000',
                            counterText: '',
                            prefixIcon: const Icon(Icons.pin_drop_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.icon(
                          onPressed: _buscandoCep ? null : _buscarCep,
                          icon: _buscandoCep
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.search_rounded,
                                  size: 20, color: Colors.white),
                          label: Text(
                              _buscandoCep ? 'Buscando...' : 'Buscar CEP',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            minimumSize: Size(minTouch, minTouch),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _logradouro,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Logradouro (rua, avenida…)',
                      prefixIcon: const Icon(Icons.signpost_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _numero,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Número',
                      prefixIcon: const Icon(Icons.numbers_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bairro,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Bairro',
                      prefixIcon: const Icon(Icons.apartment_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _cidade,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Cidade',
                            prefixIcon: const Icon(Icons.location_city_rounded),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _uf,
                          onChanged: (_) => setState(() {}),
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: InputDecoration(
                            labelText: 'UF',
                            counterText: '',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _quadraLote,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Quadra e lote (opcional)',
                      hintText: 'Ex.: Qd 5 Lt 12',
                      prefixIcon: const Icon(Icons.grid_on_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _referencia,
                    onChanged: (_) => setState(() {}),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Ponto de referência (opcional)',
                      hintText: 'Ex.: próximo ao mercado, fundos do salão…',
                      prefixIcon: const Icon(Icons.flag_outlined),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Resumo do local',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Colors.grey.shade700)),
                        const SizedBox(height: 6),
                        Text(
                          _montarEnderecoManual().isEmpty
                              ? '(preencha os campos acima)'
                              : _montarEnderecoManual(),
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: _montarEnderecoManual().isEmpty
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minTouch),
                    child: FilledButton.icon(
                      onPressed: _usarEnderecoIgreja,
                      icon: const Icon(Icons.church_rounded,
                          size: 20, color: Colors.white),
                      label: const Text('Usar endereço da igreja (cadastro)',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        minimumSize: Size(double.infinity, minTouch),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                      locale: const Locale('pt', 'BR'),
                      helpText: 'Selecionar data',
                      cancelText: 'Cancelar',
                      confirmText: 'OK',
                    );
                    if (d != null && mounted) {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(_date),
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        ),
                        helpText: 'Selecionar horário',
                        cancelText: 'Cancelar',
                        confirmText: 'OK',
                      );
                      if (t != null && mounted)
                        setState(() => _date =
                            DateTime(d.year, d.month, d.day, t.hour, t.minute));
                    }
                  },
                  child: AbsorbPointer(
                      child: TextField(
                          decoration: const InputDecoration(
                              labelText: 'Data e horário',
                              prefixIcon: Icon(Icons.calendar_month_rounded)),
                          controller: TextEditingController(
                              text:
                                  '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year} ${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}'))),
                ),
                const SizedBox(height: 14),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Icon(Icons.event_busy_rounded,
                            size: 20, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('Data de validade (opcional)',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700))),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _validUntil ??
                                    DateTime.now()
                                        .add(const Duration(days: 30)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365 * 3)),
                                locale: const Locale('pt', 'BR'),
                                helpText: 'Até quando exibir o evento',
                                cancelText: 'Cancelar',
                                confirmText: 'OK',
                              );
                              if (d != null && mounted)
                                setState(() => _validUntil = d);
                            },
                            icon: const Icon(Icons.calendar_today_rounded,
                                size: 18),
                            label: Text(
                                _validUntil == null
                                    ? 'Permanente'
                                    : '${_validUntil!.day.toString().padLeft(2, '0')}/${_validUntil!.month.toString().padLeft(2, '0')}/${_validUntil!.year}',
                                overflow: TextOverflow.ellipsis),
                            style: OutlinedButton.styleFrom(
                                minimumSize:
                                    Size(0, ThemeCleanPremium.minTouchTarget)),
                          ),
                        ),
                        if (_validUntil != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Remover data de validade',
                            onPressed: () => setState(() => _validUntil = null),
                            icon: const Icon(Icons.close_rounded),
                            style: IconButton.styleFrom(
                                minimumSize: Size(minTouch, minTouch)),
                          ),
                        ],
                      ]),
                    ]),
              ]),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _publicSite,
              onChanged: (v) => setState(() => _publicSite = v),
              title: const Text('Publicar no site público'),
              subtitle: Text(
                _publicSite
                    ? 'Aparece no site gestaoyahweh.com.br/{slug} com interações.'
                    : 'Só no painel e no app.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              secondary:
                  Icon(Icons.public_rounded, color: ThemeCleanPremium.primary),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: max(52, minTouch)),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.publish_rounded),
                label: Text(
                    _saving
                        ? 'Publicando...'
                        : (widget.doc != null
                            ? 'Atualizar Evento'
                            : 'Publicar Evento'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm))),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Aba Eventos Fixos — leitura pontual para evitar INTERNAL ASSERTION FAILED.
// ═══════════════════════════════════════════════════════════════════════════════
class _FixosTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> templates;
  final bool canWrite;
  final void Function({DocumentSnapshot<Map<String, dynamic>>? doc}) onEdit;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onDelete;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onGenerate;
  final VoidCallback onSeed;
  const _FixosTab(
      {super.key,
      required this.templates,
      required this.canWrite,
      required this.onEdit,
      required this.onDelete,
      required this.onGenerate,
      required this.onSeed});

  @override
  State<_FixosTab> createState() => _FixosTabState();
}

/// Retorna URL da foto do evento fixo — extração centralizada.
String _templateImageUrl(Map<String, dynamic> m) => imageUrlFromMap(m);

class _FixosTabState extends State<_FixosTab> {
  static const _wn = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  late Future<QuerySnapshot<Map<String, dynamic>>> _templatesFuture;
  String _fixFilterPeriod = 'all';
  bool _selectMode = false;
  final Set<String> _selectedTemplateIds = <String>{};

  @override
  void initState() {
    super.initState();
    _templatesFuture = _load();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _load() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 100));
    return widget.templates.orderBy('title').get();
  }

  void _refresh() => setState(() => _templatesFuture = _load());

  void _toggleFixSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedTemplateIds.clear();
    });
  }

  bool _isWithinPeriod(DateTime dt, String period) {
    if (period == 'all') return true;
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final startLastMonth = DateTime(now.year, now.month - 1, 1);
    final endLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);
    final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);

    if (period == 'week') return !dt.isBefore(now) && dt.isBefore(endOfWeek);
    if (period == 'month')
      return dt.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
          dt.isBefore(endOfMonth.add(const Duration(days: 1)));
    if (period == 'last_month')
      return !dt.isBefore(startLastMonth) && !dt.isAfter(endLastMonth);
    if (period == 'year') return !dt.isBefore(now) && !dt.isAfter(endOfYear);
    return true;
  }

  Future<void> _deleteTemplateRefs(
      List<DocumentReference<Map<String, dynamic>>> refs) async {
    if (refs.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nada para excluir.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir eventos fixos'),
        content: Text('Deseja excluir ${refs.length} evento(s) fixo(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    const int chunkSize = 400;
    for (var i = 0; i < refs.length; i += chunkSize) {
      final batch = FirebaseFirestore.instance.batch();
      final chunk = refs.sublist(
          i, i + chunkSize > refs.length ? refs.length : i + chunkSize);
      for (final r in chunk) {
        batch.delete(r);
      }
      await batch.commit();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Eventos fixos excluídos.'));
      _selectedTemplateIds.clear();
      _selectMode = false;
      _refresh();
    }
  }

  Future<void> _deleteSelectedTemplates() async {
    final refs =
        _selectedTemplateIds.map((id) => widget.templates.doc(id)).toList();
    await _deleteTemplateRefs(refs);
  }

  Future<void> _deleteTemplatesByPeriod() async {
    final snap = await _load();
    final docs = snap.docs;
    final toDelete = <DocumentReference<Map<String, dynamic>>>[];
    for (final d in docs) {
      final raw = d.data()['createdAt'];
      if (raw is Timestamp) {
        final dt = raw.toDate();
        if (_isWithinPeriod(dt, _fixFilterPeriod)) toDelete.add(d.reference);
      }
    }
    await _deleteTemplateRefs(toDelete);
  }

  void _openEventoFixoDetail(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EventoFixoDetailPage(
        doc: doc,
        canEdit: widget.canWrite,
        onEdit: () {
          Navigator.of(context).pop();
          widget.onEdit(doc: doc);
        },
        onDelete: () {
          Navigator.of(context).pop();
          widget.onDelete(doc);
        },
        onGenerate: () {
          Navigator.of(context).pop();
          widget.onGenerate(doc);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _templatesFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar os eventos fixos',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return ThemeCleanPremium.premiumEmptyState(
            icon: Icons.event_repeat_rounded,
            title: 'Nenhum evento fixo',
            subtitle:
                'Defina cultos semanais e horários recorrentes. Você pode começar pelos modelos sugeridos.',
            action: widget.canWrite
                ? Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.onSeed,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text('Criar padrões'),
                      ),
                      FilledButton.icon(
                        onPressed: () => widget.onEdit(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Novo'),
                      ),
                    ],
                  )
                : null,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
          },
          child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: docs.length + 1,
              itemBuilder: (context, i) {
                if (i == 0)
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Text(
                            '${docs.length} evento(s) fixo(s)',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton.icon(
                              onPressed: widget.onSeed,
                              icon: const Icon(Icons.auto_awesome_rounded,
                                  size: 16),
                              label: const Text('Padrões',
                                  style: TextStyle(fontSize: 12))),
                          TextButton.icon(
                              onPressed: () => widget.onEdit(),
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Novo',
                                  style: TextStyle(fontSize: 12))),
                        ]),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _toggleFixSelectMode,
                              icon: Icon(
                                  _selectMode
                                      ? Icons.close_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 18),
                              label: Text(_selectMode
                                  ? 'Cancelar seleção'
                                  : 'Selecionar'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(
                                    0, ThemeCleanPremium.minTouchTarget),
                                side: BorderSide(
                                    color: ThemeCleanPremium.primary
                                        .withOpacity(0.25)),
                                backgroundColor: Colors.white,
                                foregroundColor: ThemeCleanPremium.primary,
                              ),
                            ),
                            SizedBox(
                              width: 160,
                              child: DropdownButtonFormField<String>(
                                value: _fixFilterPeriod,
                                decoration: const InputDecoration(
                                    labelText: 'Período', isDense: true),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'all', child: Text('Todos')),
                                  DropdownMenuItem(
                                      value: 'week',
                                      child: Text('Esta semana')),
                                  DropdownMenuItem(
                                      value: 'month', child: Text('Este mês')),
                                  DropdownMenuItem(
                                      value: 'last_month',
                                      child: Text('Mês anterior')),
                                  DropdownMenuItem(
                                      value: 'year', child: Text('Este ano')),
                                ],
                                onChanged: (v) => setState(
                                    () => _fixFilterPeriod = v ?? 'all'),
                              ),
                            ),
                            if (_selectMode)
                              FilledButton.icon(
                                onPressed: _selectedTemplateIds.isEmpty
                                    ? null
                                    : _deleteSelectedTemplates,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: Text(
                                    'Excluir (${_selectedTemplateIds.length})'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.error,
                                  minimumSize: const Size(
                                      0, ThemeCleanPremium.minTouchTarget),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                ),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _deleteTemplatesByPeriod,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Excluir por período'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.error,
                                  minimumSize: const Size(
                                      0, ThemeCleanPremium.minTouchTarget),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                final idx = i - 1;
                final d = docs[idx];
                final m = d.data();
                final selected = _selectedTemplateIds.contains(d.id);
                final title = (m['title'] ?? '').toString();
                final weekday = (m['weekday'] ?? 1) as int;
                final time = (m['time'] ?? '').toString();
                final rec = (m['recurrence'] ?? 'weekly').toString();
                final dayName = weekday > 0 && weekday < 8 ? _wn[weekday] : '?';
                final photoUrl = _templateImageUrl(m);
                return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow),
                    child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                            onTap: _selectMode
                                ? null
                                : () => _openEventoFixoDetail(context, d),
                            child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(children: [
                                  if (_selectMode)
                                    SizedBox(
                                      width: ThemeCleanPremium.minTouchTarget,
                                      height: ThemeCleanPremium.minTouchTarget,
                                      child: Checkbox(
                                        value: selected,
                                        onChanged: (_) {
                                          setState(() {
                                            if (selected) {
                                              _selectedTemplateIds.remove(d.id);
                                            } else {
                                              _selectedTemplateIds.add(d.id);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  if (_selectMode) const SizedBox(width: 12),
                                  Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                          color: ThemeCleanPremium.primary
                                              .withOpacity(0.08),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(dayName,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: ThemeCleanPremium
                                                        .primary)),
                                            Text(time,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: ThemeCleanPremium
                                                        .primary
                                                        .withOpacity(0.7)))
                                          ])),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                        Text(
                                            rec == 'weekly'
                                                ? 'Semanal'
                                                : rec == 'biweekly'
                                                    ? 'Quinzenal'
                                                    : 'Mensal',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600))
                                      ])),
                                  SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: photoUrl.isNotEmpty
                                        ? ClipOval(
                                            child: SafeNetworkImage(
                                              imageUrl: photoUrl,
                                              width: 52,
                                              height: 52,
                                              fit: BoxFit.cover,
                                              placeholder: Container(
                                                  color: Colors.grey.shade200,
                                                  child: Icon(
                                                      Icons.event_rounded,
                                                      color: ThemeCleanPremium
                                                          .primary,
                                                      size: 26)),
                                              errorWidget: Container(
                                                  color: ThemeCleanPremium
                                                      .primary
                                                      .withOpacity(0.12),
                                                  child: Icon(
                                                      Icons.event_rounded,
                                                      color: ThemeCleanPremium
                                                          .primary,
                                                      size: 26)),
                                            ),
                                          )
                                        : CircleAvatar(
                                            radius: 26,
                                            backgroundColor: ThemeCleanPremium
                                                .primary
                                                .withOpacity(0.12),
                                            child: Icon(Icons.event_rounded,
                                                color:
                                                    ThemeCleanPremium.primary,
                                                size: 26)),
                                  ),
                                  const SizedBox(width: 8),
                                  if (widget.canWrite && !_selectMode)
                                    PopupMenuButton<String>(
                                      tooltip: 'Ver, editar, excluir',
                                      icon: const Icon(Icons.more_vert_rounded),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'ver':
                                            _openEventoFixoDetail(context, d);
                                            break;
                                          case 'editar':
                                            if (widget.canWrite)
                                              widget.onEdit(doc: d);
                                            break;
                                          case 'excluir':
                                            if (widget.canWrite)
                                              widget.onDelete(d);
                                            break;
                                          case 'gerar':
                                            widget.onGenerate(d);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                            value: 'ver',
                                            child: Row(children: [
                                              Icon(Icons.visibility_rounded,
                                                  size: 20),
                                              SizedBox(width: 10),
                                              Text('Ver')
                                            ])),
                                        if (widget.canWrite)
                                          const PopupMenuItem(
                                              value: 'editar',
                                              child: Row(children: [
                                                Icon(Icons.edit_rounded,
                                                    size: 20),
                                                SizedBox(width: 10),
                                                Text('Editar')
                                              ])),
                                        if (widget.canWrite)
                                          const PopupMenuItem(
                                              value: 'excluir',
                                              child: Row(children: [
                                                Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 20,
                                                    color: Colors.red),
                                                SizedBox(width: 10),
                                                Text('Excluir',
                                                    style: TextStyle(
                                                        color: Colors.red))
                                              ])),
                                        const PopupMenuItem(
                                            value: 'gerar',
                                            child: Row(children: [
                                              Icon(Icons.auto_awesome_rounded,
                                                  size: 20),
                                              SizedBox(width: 10),
                                              Text('Gerar no feed')
                                            ])),
                                      ],
                                    ),
                                ])))));
              }),
        );
      },
    );
  }
}

/// Tela de detalhes do evento fixo: data, local, dados e foto. Editar só para gestores/adm; ao tocar vai ao módulo (abre o editor).
class _EventoFixoDetailPage extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onGenerate;
  const _EventoFixoDetailPage(
      {required this.doc,
      required this.canEdit,
      required this.onEdit,
      this.onDelete,
      required this.onGenerate});

  static const _wn = [
    '',
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo'
  ];

  @override
  Widget build(BuildContext context) {
    final m = doc.data() ?? {};
    final title = (m['title'] ?? '').toString();
    final weekday = (m['weekday'] ?? 7) as int;
    final time = (m['time'] ?? '19:30').toString();
    final location = (m['location'] ?? '').toString();
    final rec = (m['recurrence'] ?? 'weekly').toString();
    final dayName = weekday > 0 && weekday < 8 ? _wn[weekday] : '—';
    final recLabel = rec == 'weekly'
        ? 'Semanal'
        : rec == 'biweekly'
            ? 'Quinzenal'
            : 'Mensal';
    final photoUrl = _templateImageUrl(m);

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        title: Text(title.isNotEmpty ? title : 'Evento fixo'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photoUrl.isNotEmpty) ...[
                Center(
                  child: ClipOval(
                    child: SafeNetworkImage(
                      imageUrl: photoUrl,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      placeholder: Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey.shade200,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: ThemeCleanPremium.primary))),
                      errorWidget: Container(
                          width: 200,
                          height: 200,
                          color: ThemeCleanPremium.primary.withOpacity(0.15),
                          child: Icon(Icons.event_rounded,
                              size: 80, color: ThemeCleanPremium.primary)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ] else
                Center(
                  child: CircleAvatar(
                      radius: 60,
                      backgroundColor:
                          ThemeCleanPremium.primary.withOpacity(0.12),
                      child: Icon(Icons.event_rounded,
                          size: 64, color: ThemeCleanPremium.primary)),
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    boxShadow: ThemeCleanPremium.softUiCardShadow),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 16),
                      _detailRow(Icons.calendar_today_rounded, 'Data',
                          '$dayName às $time'),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _detailRow(
                            Icons.location_on_outlined, 'Local', location)
                      ],
                      const SizedBox(height: 12),
                      _detailRow(Icons.repeat_rounded, 'Recorrência', recLabel),
                    ]),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text('Voltar'))),
                if (canEdit) ...[
                  const SizedBox(width: 12),
                  Expanded(
                      child: FilledButton.icon(
                          onPressed: () => onEdit(),
                          icon: const Icon(Icons.edit_rounded, size: 20),
                          label: const Text('Editar'),
                          style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary))),
                ],
              ]),
              if (canEdit && onDelete != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        onPressed: () => onDelete!(),
                        icon:
                            const Icon(Icons.delete_outline_rounded, size: 20),
                        label: const Text('Excluir'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.error))),
              ],
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                      onPressed: () => onGenerate(),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                      label: const Text('Gerar no feed'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: ThemeCleanPremium.primary),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))
      ])),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Dashboard Eventos — gráficos de confirmações, curtidas e comentários por evento
// ═══════════════════════════════════════════════════════════════════════════════
class _DashboardEventosTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> noticias;
  final bool canWrite;

  const _DashboardEventosTab({required this.noticias, this.canWrite = false});

  @override
  State<_DashboardEventosTab> createState() => _DashboardEventosTabState();
}

class _DashboardEventosTabState extends State<_DashboardEventosTab> {
  static const int _maxEvents = 20;
  List<_EventStats> _stats = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await Future.delayed(const Duration(milliseconds: 100));
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await widget.noticias
            .orderBy('startAt', descending: true)
            .limit(100)
            .get();
      } catch (_) {
        // Fallback sem orderBy (evita exigir índice no Firestore).
        snap = await widget.noticias.limit(150).get();
      }
      var eventDocs = snap.docs.where(noticiaDocEhEventoSpecialFeed).toList();
      if (eventDocs.length > 1 &&
          snap.docs.isNotEmpty &&
          snap.docs.first.data().containsKey('startAt')) {
        eventDocs.sort((a, b) {
          final ta = a.data()['startAt'];
          final tb = b.data()['startAt'];
          if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
          return 0;
        });
      }
      eventDocs = eventDocs.take(_maxEvents).toList();
      final list = <_EventStats>[];
      for (final d in eventDocs) {
        final data = d.data();
        final title = (data['title'] ?? 'Evento').toString();
        final rsvp = (data['rsvp'] as List?)?.length ?? 0;
        final likes = (data['likes'] as List?)?.length ?? 0;
        int comments = 0;
        try {
          final countSnap =
              await d.reference.collection('comentarios').count().get();
          comments = countSnap.count ?? 0;
        } catch (_) {}
        list.add(_EventStats(
            title: title,
            rsvp: rsvp,
            likes: likes,
            comments: comments,
            eventRef: d.reference));
      }
      if (mounted)
        setState(() {
          _stats = list;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _stats.isEmpty) {
      return const ChurchPanelLoadingBody();
    }
    if (_error != null) {
      return ChurchPanelErrorBody(
        title: 'Não foi possível carregar as estatísticas dos eventos',
        error: _error,
        onRetry: _load,
      );
    }
    if (_stats.isEmpty) {
      return ThemeCleanPremium.premiumEmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'Nenhum evento para exibir',
        subtitle:
            'Publique eventos no Feed para ver estatísticas de RSVP, curtidas e comentários aqui.',
      );
    }
    final padding = ThemeCleanPremium.pagePadding(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding:
            EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 80),
        children: [
          const SizedBox(height: 8),
          _ChartCard(
            title: 'Confirmações de presença (RSVP) por evento',
            icon: Icons.check_circle_rounded,
            color: ThemeCleanPremium.success,
            onTap: () => _showNamesSheet(context, 'rsvp'),
            child: SizedBox(
              height: 280,
              child: BarChart(
                _barChartData(_stats, (e) => e.rsvp.toDouble(),
                    ThemeCleanPremium.success),
              ),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _ChartCard(
            title: 'Curtidas por evento',
            icon: Icons.favorite_rounded,
            color: Colors.red.shade400,
            onTap: () => _showNamesSheet(context, 'likes'),
            child: SizedBox(
              height: 280,
              child: BarChart(
                _barChartData(
                    _stats, (e) => e.likes.toDouble(), Colors.red.shade400),
              ),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _ChartCard(
            title: 'Comentários por evento',
            icon: Icons.comment_rounded,
            color: const Color(0xFF0EA5E9),
            onTap: () => _showNamesSheet(context, 'comments'),
            child: SizedBox(
              height: 280,
              child: BarChart(
                _barChartData(_stats, (e) => e.comments.toDouble(),
                    const Color(0xFF0EA5E9)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showNamesSheet(BuildContext context, String type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _EventNamesSheet(
          stats: _stats, type: type, canDeleteComments: widget.canWrite),
    );
  }

  BarChartData _barChartData(List<_EventStats> stats,
      double Function(_EventStats) valueOf, Color color) {
    final maxY = stats.isEmpty
        ? 5.0
        : stats.map((e) => valueOf(e)).reduce((a, b) => a > b ? a : b);
    final top = (maxY + 2).clamp(5.0, 100.0).toDouble();
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: top,
      barGroups: stats.asMap().entries.map((e) {
        final v = valueOf(e.value);
        return BarChartGroupData(
          x: e.key,
          barRods: [
            BarChartRodData(
              toY: v,
              color: color,
              width: 14,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ],
          showingTooltipIndicators: [0],
        );
      }).toList(),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i >= 0 && i < stats.length) {
                final t = stats[i].title;
                final label = t.length > 12 ? '${t.substring(0, 12)}…' : t;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(label,
                      style:
                          TextStyle(fontSize: 9, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                );
              }
              return const SizedBox();
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final i = group.x;
            if (i >= 0 && i < stats.length) {
              return BarTooltipItem(
                '${stats[i].title}\n${rod.toY.toInt()}',
                TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              );
            }
            return null;
          },
        ),
      ),
    );
  }
}

class _EventStats {
  final String title;
  final int rsvp;
  final int likes;
  final int comments;
  final DocumentReference<Map<String, dynamic>> eventRef;
  _EventStats(
      {required this.title,
      required this.rsvp,
      required this.likes,
      required this.comments,
      required this.eventRef});
}

/// Sheet: selecionar evento e ver nomes (RSVP, curtidas) ou lista de comentários com opção de excluir.
class _EventNamesSheet extends StatefulWidget {
  final List<_EventStats> stats;
  final String type;
  final bool canDeleteComments;

  const _EventNamesSheet(
      {required this.stats,
      required this.type,
      this.canDeleteComments = false});

  @override
  State<_EventNamesSheet> createState() => _EventNamesSheetState();
}

class _EventNamesSheetState extends State<_EventNamesSheet> {
  int _selectedIndex = 0;
  List<String> _names = [];
  bool _loading = false;
  String? _error;
  int _commentsStreamKey = 0;

  _EventStats get _selected =>
      widget.stats[_selectedIndex.clamp(0, widget.stats.length - 1)];

  Future<void> _loadNames() async {
    if (widget.stats.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _names = [];
    });
    try {
      final ref = _selected.eventRef;
      final snap = await ref.get();
      final data = snap.data() ?? {};
      if (widget.type == 'rsvp') {
        final uids = (data['rsvp'] as List?)
                ?.map((e) => e?.toString().trim())
                .where((s) => s != null && s!.isNotEmpty)
                .cast<String>()
                .toList() ??
            [];
        final list = <String>[];
        for (final uid in uids) {
          try {
            final u = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            final n = (u.data()?['nome'] ??
                    u.data()?['name'] ??
                    u.data()?['displayName'] ??
                    'Membro')
                .toString();
            list.add(n.isNotEmpty ? n : uid);
          } catch (_) {
            list.add(uid);
          }
        }
        if (mounted)
          setState(() {
            _names = list;
            _loading = false;
          });
      } else if (widget.type == 'likes') {
        final uids = (data['likes'] as List?)
                ?.map((e) => e?.toString().trim())
                .where((s) => s != null && s!.isNotEmpty)
                .cast<String>()
                .toList() ??
            [];
        final list = <String>[];
        for (final uid in uids) {
          try {
            final u = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            final n = (u.data()?['nome'] ??
                    u.data()?['name'] ??
                    u.data()?['displayName'] ??
                    'Membro')
                .toString();
            list.add(n.isNotEmpty ? n : uid);
          } catch (_) {
            list.add(uid);
          }
        }
        if (mounted)
          setState(() {
            _names = list;
            _loading = false;
          });
      } else {
        if (mounted)
          setState(() {
            _loading = false;
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.type != 'comments') _loadNames();
  }

  @override
  void didUpdateWidget(covariant _EventNamesSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats ||
        _selectedIndex >= widget.stats.length) _selectedIndex = 0;
  }

  String get _titleLabel {
    switch (widget.type) {
      case 'rsvp':
        return 'Confirmações de presença';
      case 'likes':
        return 'Curtidas';
      case 'comments':
        return 'Comentários';
      default:
        return 'Lista';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stats.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nenhum evento disponível.')));
    }
    final canDelete = widget.type == 'comments' && widget.canDeleteComments;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 8),
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_titleLabel,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<int>(
              value: _selectedIndex.clamp(0, widget.stats.length - 1),
              decoration: InputDecoration(
                  labelText: 'Evento',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12))),
              items: List.generate(
                  widget.stats.length,
                  (i) => DropdownMenuItem(
                      value: i,
                      child: Text(widget.stats[i].title,
                          overflow: TextOverflow.ellipsis))),
              onChanged: (v) {
                if (v != null)
                  setState(() {
                    _selectedIndex = v;
                  });
                if (widget.type != 'comments') _loadNames();
              },
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade200),
          Expanded(
            child: widget.type == 'comments'
                ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey('com_sheet_$_commentsStreamKey'),
                    stream: _selected.eventRef
                        .collection('comentarios')
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return ChurchPanelErrorBody(
                          title: 'Não foi possível carregar os comentários',
                          error: snap.error,
                          onRetry: () =>
                              setState(() => _commentsStreamKey++),
                        );
                      }
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return const ChurchPanelLoadingBody();
                      }
                      var docs = snap.data?.docs ?? [];
                      docs = List.from(docs);
                      docs.sort((a, b) {
                        final ta = a.data()['createdAt'];
                        final tb = b.data()['createdAt'];
                        if (ta is Timestamp && tb is Timestamp)
                          return ta.compareTo(tb);
                        return 0;
                      });
                      if (docs.isEmpty)
                        return Center(
                            child: Text('Nenhum comentário neste evento.',
                                style: TextStyle(color: Colors.grey.shade600)));
                      return ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final c = docs[i].data();
                          final name = (c['authorName'] ?? 'Membro').toString();
                          final text =
                              (c['text'] ?? c['texto'] ?? '').toString();
                          final ts = c['createdAt'];
                          String timeAgo = '';
                          if (ts is Timestamp) {
                            final d = DateTime.now().difference(ts.toDate());
                            if (d.inDays > 0)
                              timeAgo = '${d.inDays}d';
                            else if (d.inHours > 0)
                              timeAgo = '${d.inHours}h';
                            else if (d.inMinutes > 0)
                              timeAgo = '${d.inMinutes}min';
                            else
                              timeAgo = 'agora';
                          }
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(text),
                                    const SizedBox(height: 4),
                                    Text(timeAgo,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500))
                                  ]),
                              trailing: canDelete
                                  ? IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.red),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                                  title: const Text(
                                                      'Excluir comentário'),
                                                  content: const Text(
                                                      'Deseja excluir este comentário?'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, false),
                                                        child: const Text(
                                                            'Cancelar')),
                                                    FilledButton(
                                                        style: FilledButton
                                                            .styleFrom(
                                                                backgroundColor:
                                                                    ThemeCleanPremium
                                                                        .error),
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, true),
                                                        child: const Text(
                                                            'Excluir'))
                                                  ],
                                                ));
                                        if (ok == true)
                                          await docs[i].reference.delete();
                                      },
                                      tooltip: 'Excluir comentário')
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                  )
                : _loading
                    ? const ChurchPanelLoadingBody()
                    : _error != null
                        ? ChurchPanelErrorBody(
                            title: 'Não foi possível carregar a lista',
                            error: _error,
                            onRetry: _loadNames,
                          )
                        : _names.isEmpty
                            ? Center(
                                child: Text('Nenhum registro.',
                                    style:
                                        TextStyle(color: Colors.grey.shade600)))
                            : ListView.builder(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: _names.length,
                                itemBuilder: (_, i) => ListTile(
                                    leading: CircleAvatar(
                                        backgroundColor: ThemeCleanPremium
                                            .primary
                                            .withOpacity(0.12),
                                        child: Text(
                                            _names[i].isNotEmpty
                                                ? _names[i][0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700))),
                                    title: Text(_names[i])),
                              ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  const _ChartCard(
      {required this.title,
      required this.icon,
      required this.color,
      required this.child,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.onSurface))),
                  if (onTap != null)
                    Icon(Icons.visibility_rounded,
                        size: 18, color: Colors.grey.shade500),
                ],
              ),
              if (onTap != null)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Toque para ver nomes',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600))),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
