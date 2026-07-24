import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/church_ct_module_upload.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/patrimonio_pending_photos_cache.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/services/patrimonio_photos_update_service.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_service.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_patrimonio_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show
        formatFirebaseErrorForUser,
        formatUploadErrorForUser,
        kFeedPublishQueuedUserMessage;
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:image_picker/image_picker.dart';

/// Estado das fotos de um bem — slots fixos `foto01`…`foto05`.
class PatrimonioItemPhotosSnapshot {
  const PatrimonioItemPhotosSnapshot({
    required this.slotUrls,
    required this.slotPaths,
    required this.uploadsBySlot,
  });

  final List<String> slotUrls;
  final List<String> slotPaths;
  final Map<int, Uint8List> uploadsBySlot;

  int get occupiedCount {
    var n = 0;
    for (var i = 0; i < slotUrls.length; i++) {
      final hasUrl = slotUrls[i].trim().isNotEmpty;
      final hasPath =
          i < slotPaths.length && slotPaths[i].trim().isNotEmpty;
      if (hasUrl || hasPath || uploadsBySlot.containsKey(i)) n++;
    }
    return n;
  }

  bool get hasPendingUploads => uploadsBySlot.isNotEmpty;
}

/// Editor de fotos do património — até [kMaxPatrimonioPhotosPerItem] por bem.
class PatrimonioItemPhotosEditor extends StatefulWidget {
  const PatrimonioItemPhotosEditor({
    super.key,
    required this.churchId,
    required this.itemId,
    required this.initialData,
    this.docRef,
    required this.canChangePhotos,
    required this.canRemovePhotos,
    this.accentColor,
    this.onChanged,
  });

  final String churchId;
  final String itemId;
  final Map<String, dynamic> initialData;
  final DocumentReference<Map<String, dynamic>>? docRef;
  final bool canChangePhotos;
  final bool canRemovePhotos;
  final Color? accentColor;
  final VoidCallback? onChanged;

  static const int maxPhotos = kMaxPatrimonioPhotosPerItem;

  @override
  State<PatrimonioItemPhotosEditor> createState() =>
      PatrimonioItemPhotosEditorState();
}

class PatrimonioItemPhotosEditorState extends State<PatrimonioItemPhotosEditor> {
  late final List<String> _slotUrls;
  late final List<String> _slotPaths;
  late final List<Uint8List?> _slotPending;
  late final List<String> _slotPendingNames;
  late final PageController _carouselController;
  late final ScrollController _thumbScrollController;
  late final List<GlobalKey> _thumbKeys;
  int _carouselIndex = 0;
  bool _mediaPicking = false;
  int _preparingPhotoCount = 0;

  bool get isBusy => _mediaPicking;
  int get preparingPhotoCount => _preparingPhotoCount;

  @override
  void initState() {
    super.initState();
    _carouselController = PageController();
    _thumbScrollController = ScrollController();
    _thumbKeys = List<GlobalKey>.generate(
      PatrimonioItemPhotosEditor.maxPhotos,
      (_) => GlobalKey(),
    );
    _slotUrls = List<String>.filled(PatrimonioItemPhotosEditor.maxPhotos, '');
    _slotPaths = List<String>.filled(PatrimonioItemPhotosEditor.maxPhotos, '');
    _slotPending = List<Uint8List?>.filled(
      PatrimonioItemPhotosEditor.maxPhotos,
      null,
    );
    _slotPendingNames = List<String>.filled(
      PatrimonioItemPhotosEditor.maxPhotos,
      '',
    );
    _hydrateFromData(widget.initialData);
    unawaited(_maybeRepairStuckPhotos(widget.initialData));
    unawaited(ImmediateMediaWarm.warmPatrimonio());
    unawaited(
      ChurchMediaUploadFacade.ensureReady(requireAuth: false).catchError((_) {}),
    );
    unawaited(
      FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false),
    );
    final cached = PatrimonioPendingPhotosCache.peek(
      widget.churchId,
      widget.itemId,
    );
    if (cached != null) {
      for (final e in cached.entries) {
        if (e.key >= 0 && e.key < PatrimonioItemPhotosEditor.maxPhotos) {
          _slotPending[e.key] = e.value;
          _slotPendingNames[e.key] = 'foto_${e.key + 1}.jpg';
        }
      }
    }
  }

  @override
  void dispose() {
    _carouselController.dispose();
    _thumbScrollController.dispose();
    super.dispose();
  }

  void _onCarouselPageChanged(int index) {
    setState(() => _carouselIndex = index);
    _scrollThumbIntoView(index);
  }

  void _goToCarouselPage(int slot) {
    if (slot < 0 || slot >= PatrimonioItemPhotosEditor.maxPhotos) return;
    unawaited(
      _carouselController.animateToPage(
        slot,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
    _scrollThumbIntoView(slot);
  }

  void _scrollThumbIntoView(int index) {
    if (index < 0 || index >= _thumbKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _thumbKeys[index].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.45,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _syncPendingCache() {
    final uploads = <int, Uint8List>{};
    for (var i = 0; i < PatrimonioItemPhotosEditor.maxPhotos; i++) {
      final p = _slotPending[i];
      if (p != null && p.isNotEmpty) uploads[i] = p;
    }
    PatrimonioPendingPhotosCache.set(
      widget.churchId,
      widget.itemId,
      uploads,
    );
  }

  void _hydrateFromData(Map<String, dynamic> data) {
    for (var i = 0; i < PatrimonioItemPhotosEditor.maxPhotos; i++) {
      _slotUrls[i] = '';
      _slotPaths[i] = '';
    }
    // Preservar o índice real do slot (foto01 → slot 1): lista compactada
    // deslocava fotos quando havia slot vazio no meio.
    final refs = ChurchCanonicalMediaContract.resolvePatrimonioPhotos(data);
    for (final r in refs) {
      final i = r.slotIndex ?? -1;
      if (i < 0 || i >= PatrimonioItemPhotosEditor.maxPhotos) continue;
      final raw = r.downloadUrl.isNotEmpty ? r.downloadUrl : '';
      _slotUrls[i] = sanitizeImageUrl(
        YahwehMediaCacheBust.applyFromDocRevision(raw, data),
      );
      _slotPaths[i] = r.storagePath.trim();
    }
  }

  PatrimonioItemPhotosSnapshot get snapshot {
    final uploads = <int, Uint8List>{};
    for (var i = 0; i < PatrimonioItemPhotosEditor.maxPhotos; i++) {
      final pending = _slotPending[i];
      if (pending != null && pending.isNotEmpty) uploads[i] = pending;
    }
    return PatrimonioItemPhotosSnapshot(
      slotUrls: List<String>.from(_slotUrls),
      slotPaths: List<String>.from(_slotPaths),
      uploadsBySlot: uploads,
    );
  }

  int get _fotoCountAtual => snapshot.occupiedCount;

  bool get _atingiuLimiteFotos =>
      _fotoCountAtual >= PatrimonioItemPhotosEditor.maxPhotos;

  int? _firstEmptyPhotoSlot() {
    for (var i = 0; i < PatrimonioItemPhotosEditor.maxPhotos; i++) {
      if (_slotUrls[i].isEmpty &&
          _slotPaths[i].isEmpty &&
          _slotPending[i] == null) {
        return i;
      }
    }
    return null;
  }

  void _notifyChanged() {
    _syncPendingCache();
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _maybeRepairStuckPhotos(Map<String, dynamic> data) async {
    // Web: reparo + get() no initState conflita com listeners → INTERNAL ASSERTION.
    if (kIsWeb) return;
    final hasUrl = _slotUrls.any((u) => u.trim().isNotEmpty);
    final hasPath = _slotPaths.any((p) => p.trim().isNotEmpty);
    if (hasUrl) return;
    final state = (data['photoUploadState'] ?? '').toString().trim();
    // Repara: uploading preso OU doc sem refs mas com ficheiros no Storage.
    final shouldProbe = !hasPath ||
        state == 'uploading' ||
        state == 'pending_sync';
    if (!shouldProbe) return;
    try {
      await PatrimonioPublishService.repairFromStorage(
        churchId: widget.churchId,
        itemId: widget.itemId,
        corePayload: data,
      );
      if (!mounted) return;
      final ref = widget.docRef;
      if (ref == null) return;
      final snap = await ref.get();
      final repaired = snap.data() ?? {};
      final repairedUrls = PatrimonioPhotoFields.urlsFromData(repaired);
      final repairedPaths = PatrimonioPhotoFields.pathsFromData(repaired);
      if ((repairedUrls.isEmpty && repairedPaths.isEmpty) || !mounted) {
        return;
      }
      setState(() {
        _hydrateFromData(repaired);
        for (var i = 0; i < PatrimonioItemPhotosEditor.maxPhotos; i++) {
          _slotPending[i] = null;
          _slotPendingNames[i] = '';
        }
      });
    } catch (_) {}
  }

  void _showLimiteFotosSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Limite de ${PatrimonioItemPhotosEditor.maxPhotos} fotos por bem. '
          'Remova uma para adicionar outra.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSemPermissaoSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Sem permissão para alterar fotos deste bem.',
      ),
    );
  }

  Future<void> clearPhotoSlot(int idx) async {
    if (!widget.canRemovePhotos) {
      _showSemPermissaoSnack();
      return;
    }
    if (idx < 0 || idx >= PatrimonioItemPhotosEditor.maxPhotos) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover foto'),
        content: Text('Quer remover a foto ${idx + 1}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _slotUrls[idx] = '';
      _slotPaths[idx] = '';
      _slotPending[idx] = null;
      _slotPendingNames[idx] = '';
    });
    _notifyChanged();
    // Controle Total: remoção só persiste ao Guardar/Salvar (evita write Firestore
    // imediato na web com listeners activos → INTERNAL ASSERTION).
  }

  Future<void> _showFotoAnexadaSnack(String fileName, Uint8List bytes) async {
    if (!mounted) return;
    final resolution =
        await ImmediateMediaAttachFeedback.readResolution(bytes);
    if (!mounted) return;
    ImmediateMediaAttachFeedback.showFotoAdicionadaSucesso(
      context,
      fileName: fileName,
      sizeBytes: bytes.length,
      resolution: resolution,
    );
  }

  Future<void> pickForSlot(int slot) async {
    if (!widget.canChangePhotos) {
      _showSemPermissaoSnack();
      return;
    }
    if (_mediaPicking) return;
    if (slot < 0 || slot >= PatrimonioItemPhotosEditor.maxPhotos) return;
    setState(() => _mediaPicking = true);
    try {
      // Padrão CT: pick → bytes (uma compressão) → pending slot.
      final picked = await ChurchCtModuleUpload.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1920,
      ).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException(
          'Seleção de foto demorou demais.',
        ),
      );
      if (picked == null || !mounted) return;
      final bytes = picked.bytes;
      if (bytes.isEmpty || !mounted) return;
      setState(() {
        _slotUrls[slot] = '';
        _slotPaths[slot] = '';
        _slotPending[slot] = bytes;
        _slotPendingNames[slot] =
            picked.fileName.isNotEmpty ? picked.fileName : 'foto_${slot + 1}.jpg';
      });
      _notifyChanged();
      if (mounted) {
        unawaited(_showFotoAnexadaSnack(_slotPendingNames[slot], bytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatUploadErrorForUser(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaPicking = false);
    }
  }

  Future<void> pickFromGallery() async {
    if (!widget.canChangePhotos) {
      _showSemPermissaoSnack();
      return;
    }
    if (_mediaPicking) return;
    if (_atingiuLimiteFotos) {
      _showLimiteFotosSnack();
      return;
    }
    final vagas = PatrimonioItemPhotosEditor.maxPhotos - _fotoCountAtual;
    if (vagas <= 0) {
      _showLimiteFotosSnack();
      return;
    }
    setState(() {
      _mediaPicking = true;
      _preparingPhotoCount = 0;
    });
    _notifyChanged();
    try {
      final List<XFile> list;
      if (vagas == 1) {
        final single = await MediaHandlerService.instance
            .pickAndProcessFromGallery(
              module: YahwehMediaModule.patrimonio,
              context: context,
            )
            .timeout(
              const Duration(seconds: 90),
              onTimeout: () => throw TimeoutException(
                'Seleção de foto demorou demais.',
              ),
            );
        list = single != null ? [single] : [];
      } else {
        final picked = await MediaHandlerService.instance
            .pickAndProcessMultipleImages(
              module: YahwehMediaModule.patrimonio,
              context: context,
            )
            .timeout(
              const Duration(seconds: 90),
              onTimeout: () => throw TimeoutException(
                'Seleção de fotos demorou demais.',
              ),
            );
        list = picked.length > vagas ? picked.sublist(0, vagas) : picked;
      }
      if (list.isEmpty || !mounted) return;
      var anexadas = 0;
      String? ultimoNome;
      for (var i = 0; i < list.length; i++) {
        if (_atingiuLimiteFotos) break;
        if (mounted) setState(() => _preparingPhotoCount = i + 1);
        try {
          final bytes = await SafeImageBytes.patrimonioFromPicker(list[i])
              .timeout(const Duration(seconds: 25));
          if (!mounted) return;
          final slot = _firstEmptyPhotoSlot();
          if (slot == null) break;
          final nome = list[i].name.isNotEmpty
              ? list[i].name
              : 'foto_${slot + 1}.jpg';
          setState(() {
            _slotPending[slot] = bytes;
            _slotPendingNames[slot] = nome;
            _preparingPhotoCount = 0;
          });
          ultimoNome = nome;
          anexadas++;
          if (kIsWeb) {
            await Future<void>.delayed(const Duration(milliseconds: 16));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Foto ignorada: ${formatFirebaseErrorForUser(e)}',
                ),
              ),
            );
          }
        }
      }
      if (anexadas == 0 || !mounted) return;
      if (mounted) {
        Uint8List? lastBytes;
        for (var i = _slotPending.length - 1; i >= 0; i--) {
          final b = _slotPending[i];
          if (b != null && b.isNotEmpty) {
            lastBytes = b;
            break;
          }
        }
        if (lastBytes != null) {
          unawaited(_showFotoAnexadaSnack(
            anexadas == 1 ? (ultimoNome ?? 'foto') : '$anexadas fotos',
            lastBytes,
          ));
        } else {
          ImmediateMediaAttachFeedback.showFotoAdicionadaSucesso(
            context,
            fileName:
                anexadas == 1 ? (ultimoNome ?? 'foto') : '$anexadas fotos',
          );
        }
      }
      if (list.length > anexadas) _showLimiteFotosSnack();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível abrir a galeria: '
              '${formatUploadErrorForUser(e)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _mediaPicking = false;
          _preparingPhotoCount = 0;
        });
      }
    }
  }

  Future<void> pickFromCamera() async {
    if (!widget.canChangePhotos) {
      _showSemPermissaoSnack();
      return;
    }
    if (_mediaPicking || kIsWeb) return;
    if (_atingiuLimiteFotos) {
      _showLimiteFotosSnack();
      return;
    }
    setState(() => _mediaPicking = true);
    try {
      final file = await MediaHandlerService.instance.pickAndProcessFromCamera(
        module: YahwehMediaModule.patrimonio,
        context: context,
      );
      if (file == null || !mounted) return;
      final bytes = await SafeImageBytes.patrimonioFromPicker(file)
          .timeout(const Duration(seconds: 25));
      setState(() {
        final slot = _firstEmptyPhotoSlot();
        if (slot != null) {
          _slotPending[slot] = bytes;
          _slotPendingNames[slot] =
              file.name.isNotEmpty ? file.name : 'camera.jpg';
        }
      });
      if (mounted) {
        final name = file.name.isNotEmpty ? file.name : 'camera.webp';
        unawaited(_showFotoAnexadaSnack(name, bytes));
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível abrir a câmera: '
              '${formatUploadErrorForUser(e)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaPicking = false);
    }
  }

  Future<void> replacePhotoAtSlot(int slot) async {
    if (!widget.canChangePhotos) {
      _showSemPermissaoSnack();
      return;
    }
    if (_mediaPicking) return;
    if (slot < 0 || slot >= PatrimonioItemPhotosEditor.maxPhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Trocar foto ${slot + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeria'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Câmera'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;
    setState(() => _mediaPicking = true);
    try {
      XFile? picked;
      if (source == ImageSource.camera) {
        picked = await MediaHandlerService.instance.pickAndProcessFromCamera(
          module: YahwehMediaModule.patrimonio,
          context: context,
        );
      } else {
        picked = await MediaHandlerService.instance.pickAndProcessFromGallery(
          module: YahwehMediaModule.patrimonio,
          context: context,
        );
      }
      if (picked == null || !mounted) return;
      final bytes = await SafeImageBytes.patrimonioFromPicker(picked)
          .timeout(const Duration(seconds: 25));
      if (bytes.isEmpty || !mounted) return;
      setState(() {
        _slotUrls[slot] = '';
        _slotPaths[slot] = '';
        _slotPending[slot] = bytes;
        _slotPendingNames[slot] =
            picked!.name.isNotEmpty ? picked.name : 'foto_${slot + 1}.jpg';
      });
      ImmediateMediaAttachFeedback.showArquivoAnexado(
        context,
        _slotPendingNames[slot],
      );
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatFirebaseErrorForUser(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaPicking = false);
    }
  }

  /// Apaga Storage só de slots realmente vazios após Salvar.
  /// Slot com upload novo (bytes pendentes) ainda não tem `slotPath` — se a
  /// limpeza olhasse só para paths antigos, apagava a foto acabada de enviar.
  Future<void> cleanupUnusedSlots(PatrimonioItemPhotosSnapshot snap) async {
    final tenantId = widget.churchId.trim();
    final itemDocId = widget.itemId.trim();
    if (tenantId.isEmpty || itemDocId.isEmpty) return;
    await Future.wait([
      for (var s = 0; s < PatrimonioItemPhotosEditor.maxPhotos; s++)
        if (!snap.uploadsBySlot.containsKey(s) &&
            snap.slotUrls[s].trim().isEmpty &&
            snap.slotPaths[s].trim().isEmpty)
          FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
            tenantId: tenantId,
            itemDocId: itemDocId,
            slot: s,
          ),
    ]);
  }

  bool _slotHasContent(int slot) =>
      (_slotPending[slot]?.isNotEmpty ?? false) ||
      _slotUrls[slot].isNotEmpty ||
      _slotPaths[slot].isNotEmpty;

  Future<void> _openSlot(int slot) async {
    if (_slotHasContent(slot)) {
      await replacePhotoAtSlot(slot);
    } else if (widget.canChangePhotos &&
        !_mediaPicking &&
        !_atingiuLimiteFotos) {
      await pickForSlot(slot);
      if (mounted) {
        await _carouselController.animateToPage(
          slot,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  Widget _buildSlotPreview(int slot, Color cor, int memCarousel) {
    final pending = _slotPending[slot];
    if (pending != null && pending.isNotEmpty) {
      return Image.memory(
        pending,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: memCarousel.clamp(64, 800),
        cacheHeight: memCarousel.clamp(64, 800),
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    if (_slotUrls[slot].isNotEmpty) {
      return FotoPatrimonioWidget(
        key: ValueKey('pat_carousel_${slot}_${_slotUrls[slot]}'),
        storagePath: _slotPaths[slot].isNotEmpty
            ? _slotPaths[slot]
            : ChurchStorageLayout.patrimonioPhotoPath(
                widget.churchId,
                widget.itemId,
                slot,
              ),
        candidateUrls: [_slotUrls[slot]],
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: memCarousel,
        memCacheHeight: memCarousel,
        placeholder: Container(
          color: cor.withValues(alpha: 0.1),
          alignment: Alignment.center,
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: cor),
          ),
        ),
        errorWidget: Container(
          color: cor.withValues(alpha: 0.08),
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_outlined,
              color: cor.withValues(alpha: 0.45), size: 40),
        ),
      );
    }
    return Container(
      color: cor.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 42, color: cor.withValues(alpha: 0.45)),
          const SizedBox(height: 8),
          Text(
            'Slot ${slot + 1}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cor = widget.accentColor ?? ThemeCleanPremium.primary;
    final dprForm = MediaQuery.devicePixelRatioOf(context);
    final memThumb = (56 * dprForm).round().clamp(96, 220);
    final memCarousel = (160 * dprForm).round().clamp(200, 480);
    final canChange = widget.canChangePhotos;
    final canRemove = widget.canRemovePhotos;
    final max = PatrimonioItemPhotosEditor.maxPhotos;
    final atLimit = _atingiuLimiteFotos;

    Widget actionButtons() {
      if (!canChange) {
        return Text(
          'Sem permissão para adicionar ou alterar fotos.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: (atLimit || _mediaPicking) ? null : pickFromGallery,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
            label: const Text('Galeria'),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          if (!kIsWeb)
            OutlinedButton.icon(
              onPressed: (atLimit || _mediaPicking) ? null : pickFromCamera,
              icon: const Icon(Icons.photo_camera_outlined, size: 20),
              label: const Text('Câmera'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeCleanPremium.primary,
                side: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.55),
                  width: 1.5,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_library_rounded,
                      color: ThemeCleanPremium.primary, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Galeria ($_fotoCountAtual/$max)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          '5 slots fixos — deslize ou toque na miniatura.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              actionButtons(),
              if (_preparingPhotoCount > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'A preparar foto $_preparingPhotoCount…',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFE8EEF4)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Preview compacto — web/mobile (não “gigante”).
              LayoutBuilder(
                builder: (context, c) {
                  final maxH = c.maxWidth > 720 ? 200.0 : 220.0;
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: ColoredBox(
                        color: const Color(0xFF0F172A),
                        child: PageView.builder(
                  controller: _carouselController,
                  itemCount: max,
                  onPageChanged: _onCarouselPageChanged,
                  itemBuilder: (_, slot) => GestureDetector(
                    onTap: canChange && !_mediaPicking
                        ? () => unawaited(_openSlot(slot))
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildSlotPreview(slot, cor, memCarousel),
                        if (_slotPending[slot] != null)
                          Positioned(
                            left: 10,
                            top: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(
                                  'Pendente',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (canRemove && _slotHasContent(slot))
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: () => unawaited(clearPhotoSlot(slot)),
                                borderRadius: BorderRadius.circular(24),
                                child: const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 26,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
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
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Anterior',
                      onPressed: _carouselIndex > 0
                          ? () => _goToCarouselPage(_carouselIndex - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _thumbScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var slot = 0; slot < max; slot++)
                              Padding(
                                key: _thumbKeys[slot],
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: GestureDetector(
                                  onTap: () => _goToCarouselPage(slot),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _carouselIndex == slot
                                            ? cor
                                            : const Color(0xFFE2E8F0),
                                        width: _carouselIndex == slot ? 2.5 : 1,
                                      ),
                                      boxShadow: _carouselIndex == slot
                                          ? [
                                              BoxShadow(
                                                color:
                                                    cor.withValues(alpha: 0.25),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _buildSlotPreview(
                                        slot, cor, memThumb),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Seguinte',
                      onPressed: _carouselIndex < max - 1
                          ? () => _goToCarouselPage(_carouselIndex + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _slotPending.any((b) => b != null && b.isNotEmpty)
              ? 'Fotos novas sobem ao tocar em Salvar (padrão Controle Total). A miniatura acompanha a foto principal.'
              : 'Deslize a foto ou toque nas miniaturas — a faixa de baixo acompanha a navegação.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

/// Folha fullscreen para gerir fotos de um bem já cadastrado (gravação strict).
Future<bool?> showPatrimonioItemPhotosEditorSheet(
  BuildContext context, {
  required String churchId,
  required String itemId,
  required Map<String, dynamic> itemData,
  required Map<String, dynamic> corePayload,
  required bool canChangePhotos,
  required bool canRemovePhotos,
  required DocumentReference<Map<String, dynamic>> docRef,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PatrimonioItemPhotosEditorPage(
        churchId: churchId,
        itemId: itemId,
        itemData: itemData,
        corePayload: corePayload,
        canChangePhotos: canChangePhotos,
        canRemovePhotos: canRemovePhotos,
        docRef: docRef,
      ),
    ),
  );
}

class _PatrimonioItemPhotosEditorPage extends StatefulWidget {
  const _PatrimonioItemPhotosEditorPage({
    required this.churchId,
    required this.itemId,
    required this.itemData,
    required this.corePayload,
    required this.canChangePhotos,
    required this.canRemovePhotos,
    required this.docRef,
  });

  final String churchId;
  final String itemId;
  final Map<String, dynamic> itemData;
  final Map<String, dynamic> corePayload;
  final bool canChangePhotos;
  final bool canRemovePhotos;
  final DocumentReference<Map<String, dynamic>> docRef;

  @override
  State<_PatrimonioItemPhotosEditorPage> createState() =>
      _PatrimonioItemPhotosEditorPageState();
}

class _PatrimonioItemPhotosEditorPageState
    extends State<_PatrimonioItemPhotosEditorPage> {
  final _editorKey = GlobalKey<PatrimonioItemPhotosEditorState>();
  bool _saving = false;
  String _phaseLabel = '';

  Future<void> _save() async {
    final editor = _editorKey.currentState;
    if (editor == null || editor.isBusy || _saving) return;
    final snap = editor.snapshot;
    setState(() {
      _saving = true;
      _phaseLabel = 'A enviar fotos…';
    });
    try {
      await PatrimonioPhotosUpdateService.publishPhotosStrict(
        churchIdHint: widget.churchId,
        itemId: widget.itemId,
        corePayload: widget.corePayload,
        isNewDoc: false,
        indexedSlotUrls: snap.slotUrls,
        indexedSlotPaths: snap.slotPaths,
        uploadsBySlot: snap.uploadsBySlot,
        onProgress: (p, label) {
          if (mounted) setState(() => _phaseLabel = label);
        },
      );
      await editor.cleanupUnusedSlots(snap);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Fotos do bem actualizadas.'),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (EcoFireResilientPublish.isQueuedSuccess(e) ||
          EcoFireResilientPublish.treatAsSilentSuccess(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(kFeedPublishQueuedUserMessage),
        );
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          formatUploadErrorForUser(e),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _phaseLabel = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = (widget.itemData['nome'] ?? 'Bem').toString();
    final busy = _saving || _editorKey.currentState?.isBusy == true;
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surface,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: busy ? null : () => Navigator.maybePop(context, false),
        ),
        title: Text(
          'Fotos — $nome',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            if (_phaseLabel.isNotEmpty) ...[
              Text(
                _phaseLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(height: 12),
            ],
            PatrimonioItemPhotosEditor(
              key: _editorKey,
              churchId: widget.churchId,
              itemId: widget.itemId,
              initialData: widget.itemData,
              docRef: widget.docRef,
              canChangePhotos: widget.canChangePhotos,
              canRemovePhotos: widget.canRemovePhotos,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        busy ? null : () => Navigator.maybePop(context, false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: ThemeCleanPremium.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: (busy ||
                            !(widget.canChangePhotos ||
                                widget.canRemovePhotos))
                        ? null
                        : _save,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Salvando…' : 'Salvar'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: ThemeCleanPremium.primary,
                      foregroundColor: Colors.white,
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
}