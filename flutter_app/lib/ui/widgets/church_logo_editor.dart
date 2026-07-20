import 'dart:async' show unawaited;
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_ct_module_upload.dart';
import 'package:gestao_yahweh/services/church_logo_update_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_image_crop_dialog.dart';
import 'package:gestao_yahweh/ui/widgets/default_church_logo_asset.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:image_picker/image_picker.dart';

/// Estado local — publicação strict no «Salvar igreja».
class ChurchLogoEditorSnapshot {
  const ChurchLogoEditorSnapshot({
    this.pendingBytes,
    this.removeExisting = false,
  });

  final Uint8List? pendingBytes;
  final bool removeExisting;

  bool get hasPending => pendingBytes != null;
  bool get hasLogoMutation => hasPending || removeExisting;
}

/// Editor da logo institucional — pré-visualização 4K, adicionar/trocar/remover.
class ChurchLogoEditor extends StatefulWidget {
  const ChurchLogoEditor({
    super.key,
    required this.churchIdHint,
    required this.canAdd,
    required this.canChange,
    required this.canRemove,
    this.existingLogoUrl,
    this.existingStoragePath,
    this.tenantData,
    this.churchNameForInitials,
    this.onChanged,
  });

  final String churchIdHint;
  final bool canAdd;
  final bool canChange;
  final bool canRemove;
  final String? existingLogoUrl;
  final String? existingStoragePath;
  final Map<String, dynamic>? tenantData;
  final String? churchNameForInitials;
  final ValueChanged<ChurchLogoEditorSnapshot>? onChanged;

  @override
  State<ChurchLogoEditor> createState() => ChurchLogoEditorState();
}

class ChurchLogoEditorState extends State<ChurchLogoEditor> {
  Uint8List? _pending;
  Uint8List? _existingBytes;
  bool _removeExisting = false;
  bool _loadingExisting = false;

  ChurchLogoEditorSnapshot get snapshot => ChurchLogoEditorSnapshot(
        pendingBytes: _pending,
        removeExisting: _removeExisting,
      );

  bool get _hasExistingReady {
    if (_removeExisting) return false;
    if (_pending != null) return true;
    if (_existingBytes != null && _existingBytes!.isNotEmpty) return true;
    final url = sanitizeImageUrl((widget.existingLogoUrl ?? '').trim());
    return url.isNotEmpty && isValidImageUrl(url);
  }

  String get _storagePathHint =>
      ChurchLogoUpdateService.storagePathHint(widget.churchIdHint);

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateExistingBytes());
  }

  @override
  void didUpdateWidget(covariant ChurchLogoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.existingLogoUrl != widget.existingLogoUrl ||
        oldWidget.existingStoragePath != widget.existingStoragePath ||
        oldWidget.churchIdHint != widget.churchIdHint) {
      unawaited(_hydrateExistingBytes());
    }
  }

  Future<void> _hydrateExistingBytes() async {
    final cid = ChurchLogoUpdateService.resolveChurchId(widget.churchIdHint);
    if (cid.isEmpty) return;
    final url = sanitizeImageUrl((widget.existingLogoUrl ?? '').trim());
    if (url.isEmpty && (widget.existingStoragePath ?? '').trim().isEmpty) {
      return;
    }
    if (!mounted) return;
    setState(() => _loadingExisting = true);
    try {
      final bytes = await ChurchBrandService.getLogoBytes(
        churchId: cid,
        tenantData: widget.tenantData,
      );
      if (!mounted) return;
      setState(() {
        _existingBytes = bytes;
        _loadingExisting = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  void _notify() => widget.onChanged?.call(snapshot);

  /// Limpa estado local após gravação strict bem-sucedida.
  void resetAfterSave() {
    setState(() {
      _pending = null;
      _removeExisting = false;
    });
    unawaited(_hydrateExistingBytes());
    _notify();
  }

  void _showSemPermissao() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Sem permissão para alterar a logo da igreja.',
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    if (!widget.canAdd && !widget.canChange) {
      _showSemPermissao();
      return;
    }
    try {
      final picked = await ChurchCtModuleUpload.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 3840,
      );
      if (picked == null || !mounted) return;
      final bytes = picked.bytes;
      if (!mounted || bytes.isEmpty) return;
      setState(() {
        _pending = bytes;
        _removeExisting = false;
      });
      _notify();
      final resolution =
          await ImmediateMediaAttachFeedback.readResolution(bytes);
      if (!mounted) return;
      ImmediateMediaAttachFeedback.showFotoAdicionadaSucesso(
        context,
        fileName: picked.fileName.trim().isNotEmpty
            ? picked.fileName
            : 'logo.webp',
        sizeBytes: bytes.length,
        resolution: resolution,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Erro ao selecionar logo: ${ChurchCtModuleUpload.mensagemAmigavel(e)}',
        ),
      );
    }
  }

  Future<void> _pickFromCamera() async {
    if (!widget.canAdd && !widget.canChange) {
      _showSemPermissao();
      return;
    }
    try {
      final picked = await ChurchCtModuleUpload.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
        maxWidth: 3840,
      );
      if (picked == null || !mounted) return;
      final bytes = picked.bytes;
      if (!mounted || bytes.isEmpty) return;
      setState(() {
        _pending = bytes;
        _removeExisting = false;
      });
      _notify();
      final resolution =
          await ImmediateMediaAttachFeedback.readResolution(bytes);
      if (!mounted) return;
      ImmediateMediaAttachFeedback.showFotoAdicionadaSucesso(
        context,
        fileName: picked.fileName.trim().isNotEmpty
            ? picked.fileName
            : 'logo_camera.webp',
        sizeBytes: bytes.length,
        resolution: resolution,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Erro na câmera: ${ChurchCtModuleUpload.mensagemAmigavel(e)}',
        ),
      );
    }
  }

  Future<void> _cropPending() async {
    final b = _pending;
    if (b == null || !mounted) return;
    if (!widget.canChange && !widget.canAdd) {
      _showSemPermissao();
      return;
    }
    final cropped = await showChurchPhotoCropDialog(
      context,
      imageBytes: b,
      title: 'Cortar logo',
      circleUi: false,
      aspectRatio: 1,
    );
    if (cropped != null && mounted) {
      setState(() => _pending = cropped);
      _notify();
    }
  }

  Future<void> _confirmRemove() async {
    if (!widget.canRemove || !_hasExistingReady) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Remover logo'),
        content: const Text(
          'A logo será removida do cadastro e apagada do Storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.error,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _pending = null;
      _removeExisting = true;
    });
    _notify();
  }

  void _clearPending() {
    setState(() => _pending = null);
    _notify();
  }

  Widget _previewImage({
    required double width,
    required double height,
    required Uint8List bytes,
  }) {
    return InteractiveViewer(
      minScale: 0.6,
      maxScale: 5,
      panEnabled: true,
      child: Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        gaplessPlayback: true,
      ),
    );
  }

  Widget _buildPreviewContent({
    required double width,
    required double height,
    required String churchId,
  }) {
    if (_pending != null) {
      return _previewImage(width: width, height: height, bytes: _pending!);
    }
    if (_removeExisting) {
      return _placeholder(width: width, height: height, showHint: false);
    }
    if (_existingBytes != null && _existingBytes!.isNotEmpty) {
      return _previewImage(
        width: width,
        height: height,
        bytes: _existingBytes!,
      );
    }
    if (_loadingExisting) {
      return Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: ThemeCleanPremium.primary,
          ),
        ),
      );
    }
    final url = sanitizeImageUrl((widget.existingLogoUrl ?? '').trim());
    if (url.isNotEmpty && churchId.isNotEmpty) {
      return StableChurchLogo(
        storagePath: widget.existingStoragePath,
        imageUrl: url,
        tenantId: churchId,
        tenantData: widget.tenantData,
        width: width,
        height: height,
        fit: BoxFit.contain,
        memCacheWidth: ChurchLogoUpdateService.kLogoMaxSidePx,
        memCacheHeight: ChurchLogoUpdateService.kLogoMaxSidePx,
      );
    }
    return _placeholder(width: width, height: height);
  }

  Widget _placeholder({
    required double width,
    required double height,
    bool showHint = true,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultChurchLogoAsset(
            width: width,
            height: height * 0.72,
            fractionOfBox: 0.92,
          ),
          if (showHint && (widget.canAdd || widget.canChange)) ...[
            const SizedBox(height: 8),
            Text(
              'Toque em «Adicionar logo» para escolher em 4K',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _ringGradient = LinearGradient(
    colors: [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  Widget _outerFrame({
    required double width,
    required double height,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: _ringGradient,
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final churchId = ChurchLogoUpdateService.resolveChurchId(
      widget.churchIdHint,
    );
    final canPick = widget.canAdd || widget.canChange;
    final hasPending = _pending != null;
    final hasExisting = _hasExistingReady && !_removeExisting;
    final initials = (widget.churchNameForInitials ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.07),
            const Color(0xFFF8FAFC),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.photo_library_rounded,
                  color: ThemeCleanPremium.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logo da igreja',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alta resolução (até 4K). Pinça para ampliar a pré-visualização.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Storage: $_storagePathHint',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxUsable = constraints.maxWidth.isFinite &&
                      constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : 320.0;
              const kMaxPreviewW = 320.0;
              final previewW = min(maxUsable, kMaxPreviewW);
              final boxH = (previewW * 9 / 16).clamp(120.0, 200.0);
              return Center(
                child: _outerFrame(
                  width: previewW,
                  height: boxH,
                  child: _buildPreviewContent(
                    width: previewW,
                    height: boxH,
                    churchId: churchId,
                  ),
                ),
              );
            },
          ),
          if (_removeExisting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Logo marcada para remoção ao salvar.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ThemeCleanPremium.error,
                ),
              ),
            ),
          if (hasPending) ...[
            const SizedBox(height: 8),
            Text(
              'Nova logo pronta — salve o cadastro para publicar.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ThemeCleanPremium.success,
              ),
            ),
            TextButton.icon(
              onPressed: _clearPending,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancelar nova logo'),
              style: TextButton.styleFrom(
                foregroundColor: ThemeCleanPremium.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (canPick)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: Text(hasExisting ? 'Trocar logo' : 'Adicionar logo'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickFromCamera,
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: const Text('Câmera'),
                ),
                if (hasPending)
                  TextButton.icon(
                    onPressed: _cropPending,
                    icon: const Icon(Icons.crop_rounded, size: 18),
                    label: const Text('Cortar'),
                  ),
                if (hasExisting && widget.canRemove)
                  TextButton.icon(
                    onPressed: _confirmRemove,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remover'),
                    style: TextButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.error,
                    ),
                  ),
              ],
            )
          else
            Text(
              'Sem permissão para alterar a logo.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          if (initials.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.text_fields_rounded,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'Iniciais: $initials',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
