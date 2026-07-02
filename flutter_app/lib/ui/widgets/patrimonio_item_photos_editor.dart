import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/church_canonical_media_delete_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/services/patrimonio_photos_update_service.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_patrimonio_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatFirebaseErrorForUser;
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
      if (slotUrls[i].isNotEmpty || uploadsBySlot.containsKey(i)) n++;
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
  bool _mediaPicking = false;
  int _preparingPhotoCount = 0;

  bool get isBusy => _mediaPicking;
  int get preparingPhotoCount => _preparingPhotoCount;

  @override
  void initState() {
    super.initState();
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
      DirectStorageUrlPublish.ensureReady(requireAuth: false).catchError((_) {}),
    );
    unawaited(
      FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false),
    );
  }

  void _hydrateFromData(Map<String, dynamic> data) {
    final urls = PatrimonioPhotoFields.urlsFromData(data);
    final paths = PatrimonioPhotoFields.pathsFromData(data);
    for (var i = 0; i < PatrimonioItemPhotosEditor.maxPhotos; i++) {
      _slotUrls[i] = i < urls.length ? sanitizeImageUrl(urls[i]) : '';
      _slotPaths[i] = i < paths.length ? paths[i].trim() : '';
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
      if (_slotUrls[i].isEmpty && _slotPending[i] == null) return i;
    }
    return null;
  }

  void _notifyChanged() {
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _maybeRepairStuckPhotos(Map<String, dynamic> data) async {
    if (_slotUrls.any((u) => u.isNotEmpty)) return;
    final state = (data['photoUploadState'] ?? '').toString().trim();
    if (state != 'uploading' && state != 'pending_sync') return;
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
      final repairedUrls =
          PatrimonioPhotoFields.urlsFromData(snap.data() ?? {});
      final repairedPaths =
          PatrimonioPhotoFields.pathsFromData(snap.data() ?? {});
      if (repairedUrls.isEmpty || !mounted) return;
      setState(() {
        for (var i = 0; i < PatrimonioItemPhotosEditor.maxPhotos; i++) {
          _slotUrls[i] = i < repairedUrls.length
              ? sanitizeImageUrl(repairedUrls[i])
              : '';
          _slotPaths[i] =
              i < repairedPaths.length ? repairedPaths[i].trim() : '';
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

  void clearPhotoSlot(int idx) {
    if (!widget.canRemovePhotos) {
      _showSemPermissaoSnack();
      return;
    }
    if (idx < 0 || idx >= PatrimonioItemPhotosEditor.maxPhotos) return;
    final tenantId = widget.churchId.trim();
    if (tenantId.isNotEmpty) {
      ChurchCanonicalMediaDeleteService.schedulePatrimonioSlotCleared(
        tenantId: tenantId,
        itemId: widget.itemId,
        slot: idx,
        existingData: widget.initialData,
        docRef: widget.docRef,
      );
    }
    setState(() {
      _slotUrls[idx] = '';
      _slotPaths[idx] = '';
      _slotPending[idx] = null;
      _slotPendingNames[idx] = '';
    });
    widget.onChanged?.call();
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
    try {
      final List<XFile> list;
      if (vagas == 1) {
        final single =
            await MediaHandlerService.instance.pickAndProcessFromGallery(
          module: YahwehMediaModule.patrimonio,
          context: context,
        );
        list = single != null ? [single] : [];
      } else {
        final picked =
            await MediaHandlerService.instance.pickAndProcessMultipleImages(
          module: YahwehMediaModule.patrimonio,
          context: context,
        );
        list = picked.length > vagas ? picked.sublist(0, vagas) : picked;
      }
      if (list.isEmpty || !mounted) return;
      final novosBytes = <Uint8List>[];
      final novosNomes = <String>[];
      for (var i = 0; i < list.length; i++) {
        if (_fotoCountAtual + novosBytes.length >=
            PatrimonioItemPhotosEditor.maxPhotos) {
          break;
        }
        if (mounted) setState(() => _preparingPhotoCount = i + 1);
        try {
          final bytes = await SafeImageBytes.patrimonioFromPicker(list[i])
              .timeout(const Duration(seconds: 25));
          novosBytes.add(bytes);
          novosNomes.add(
            list[i].name.isNotEmpty
                ? list[i].name
                : 'foto_${novosBytes.length}.jpg',
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Foto ignorada: $e')),
            );
          }
        }
      }
      if (novosBytes.isEmpty || !mounted) return;
      setState(() {
        for (var i = 0; i < novosBytes.length; i++) {
          final slot = _firstEmptyPhotoSlot();
          if (slot == null) break;
          _slotPending[slot] = novosBytes[i];
          _slotPendingNames[slot] = i < novosNomes.length
              ? novosNomes[i]
              : 'foto_${slot + 1}.jpg';
        }
      });
      if (mounted) {
        ImmediateMediaAttachFeedback.showArquivoAnexado(
          context,
          novosNomes.length == 1
              ? novosNomes.first
              : '${novosNomes.length} fotos',
        );
      }
      if (list.length > novosBytes.length) _showLimiteFotosSnack();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível abrir a galeria: '
              '${formatFirebaseErrorForUser(e)}',
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
        ImmediateMediaAttachFeedback.showArquivoAnexado(
          context,
          file.name.isNotEmpty ? file.name : 'camera.webp',
        );
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível abrir a câmera: '
              '${formatFirebaseErrorForUser(e)}',
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

  Future<void> cleanupUnusedSlots(List<String> activePaths) async {
    final tenantId = widget.churchId.trim();
    final itemDocId = widget.itemId.trim();
    if (tenantId.isEmpty || itemDocId.isEmpty) return;
    final pathSet =
        activePaths.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    await Future.wait([
      for (var s = 0; s < PatrimonioItemPhotosEditor.maxPhotos; s++)
        if (!pathSet.contains(
          ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemDocId, s),
        ))
          FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
            tenantId: tenantId,
            itemDocId: itemDocId,
            slot: s,
          ),
    ]);
  }

  static String _formatBytes(int n) {
    if (n < 1000) return '$n bytes';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cor = widget.accentColor ?? ThemeCleanPremium.primary;
    final dprForm = MediaQuery.devicePixelRatioOf(context);
    final memThumb = (52 * dprForm).round().clamp(88, 280);
    final canChange = widget.canChangePhotos;
    final canRemove = widget.canRemovePhotos;
    final max = PatrimonioItemPhotosEditor.maxPhotos;

    Widget rowTile({
      required Widget thumb,
      required String title,
      required String subtitle,
      required int slot,
      required bool hasContent,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            thumb,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (canChange && hasContent)
              IconButton(
                tooltip: 'Trocar foto',
                onPressed: _mediaPicking ? null : () => replacePhotoAtSlot(slot),
                icon: Icon(
                  Icons.swap_horiz_rounded,
                  color: ThemeCleanPremium.primary,
                ),
              ),
            if (canRemove && hasContent)
              IconButton(
                tooltip: 'Remover',
                onPressed: () => clearPhotoSlot(slot),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                ),
              ),
          ],
        ),
      );
    }

    final linhas = <Widget>[];
    for (var slot = 0; slot < max; slot++) {
      final pending = _slotPending[slot];
      if (pending != null) {
        final nome = _slotPendingNames[slot].isNotEmpty
            ? _slotPendingNames[slot]
            : 'Nova imagem ${slot + 1}';
        linhas.add(
          rowTile(
            slot: slot,
            hasContent: true,
            thumb: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Image.memory(
                  pending,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
            title: nome,
            subtitle:
                '${_formatBytes(pending.length)} · será enviado ao salvar',
          ),
        );
        continue;
      }
      if (_slotUrls[slot].isEmpty) continue;
      linhas.add(
        rowTile(
          slot: slot,
          hasContent: true,
          thumb: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: FotoPatrimonioWidget(
                key: ValueKey('pat_editor_$slot${_slotUrls[slot]}'),
                storagePath: _slotPaths[slot].isNotEmpty
                    ? _slotPaths[slot]
                    : ChurchStorageLayout.patrimonioPhotoPath(
                        widget.churchId,
                        widget.itemId,
                        slot,
                      ),
                candidateUrls: [_slotUrls[slot]],
                fit: BoxFit.cover,
                width: 52,
                height: 52,
                memCacheWidth: memThumb,
                memCacheHeight: memThumb,
                placeholder: Container(
                  color: cor.withValues(alpha: 0.12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cor,
                      ),
                    ),
                  ),
                ),
                errorWidget: Container(
                  color: cor.withValues(alpha: 0.1),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: cor.withValues(alpha: 0.5),
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
          title: 'Foto ${slot + 1}',
          subtitle: 'image/jpeg · inventário',
        ),
      );
    }

    final hasPhotos = _fotoCountAtual > 0;
    final atLimit = _atingiuLimiteFotos;

    Widget actionButtons({required bool narrow}) {
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 420;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        color: ThemeCleanPremium.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Arquivos ($_fotoCountAtual/$max)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Até $max fotos por bem. Storage: '
                              'igrejas/{igreja}/patrimonio/{item}/foto_N.jpg',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  actionButtons(narrow: narrow),
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
              );
            },
          ),
        ),
        if (linhas.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...linhas,
        ] else if (!canChange) ...[
          const SizedBox(height: 8),
          Text(
            hasPhotos ? '' : 'Nenhuma foto neste bem.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            'Nenhuma foto ainda — use Galeria ou Câmera.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
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
      await editor.cleanupUnusedSlots(
        snap.slotPaths.where((p) => p.trim().isNotEmpty).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Fotos do bem actualizadas.'),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          formatFirebaseErrorForUser(e),
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
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surface,
      appBar: AppBar(
        title: Text('Fotos — $nome'),
        actions: [
          if (widget.canChangePhotos || widget.canRemovePhotos)
            TextButton(
              onPressed: (_saving || _editorKey.currentState?.isBusy == true)
                  ? null
                  : _save,
              child: const Text('Guardar'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            if (_phaseLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(
                  color: ThemeCleanPremium.primary,
                ),
              ),
            PatrimonioItemPhotosEditor(
              key: _editorKey,
              churchId: widget.churchId,
              itemId: widget.itemId,
              initialData: widget.itemData,
              docRef: widget.docRef,
              canChangePhotos: widget.canChangePhotos,
              canRemovePhotos: widget.canRemovePhotos,
            ),
          ],
        ),
      ),
    );
  }
}