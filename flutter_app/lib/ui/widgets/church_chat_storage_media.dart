import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_media_resolver.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_video_message_bubble.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_save_media.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show FreshFirebaseStorageImage, firebaseStorageMediaUrlLooksLike,
        isValidImageUrl, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart' show showPdfActions;

/// Cache RAM curto para miniaturas do chat (evita re-download ao scroll).
final Map<String, Uint8List> _chatThumbRamCache = <String, Uint8List>{};
const int _kChatThumbRamMaxEntries = 120;

void _chatThumbRamPut(String key, Uint8List bytes) {
  if (key.isEmpty || bytes.length < 32) return;
  if (_chatThumbRamCache.length >= _kChatThumbRamMaxEntries) {
    _chatThumbRamCache.remove(_chatThumbRamCache.keys.first);
  }
  _chatThumbRamCache[key] = bytes;
}

/// Miniatura / imagem do chat — `storagePath` directo (getData), URL legado como fallback.
class ChurchChatStorageMediaImage extends StatefulWidget {
  const ChurchChatStorageMediaImage({
    super.key,
    required this.data,
    this.tenantId,
    this.messageId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
    this.borderRadius,
    this.onTap,
  });

  final Map<String, dynamic> data;
  final String? tenantId;
  final String? messageId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  State<ChurchChatStorageMediaImage> createState() =>
      _ChurchChatStorageMediaImageState();
}

class _ChurchChatStorageMediaImageState extends State<ChurchChatStorageMediaImage> {
  Uint8List? _bytes;
  String? _networkUrl;
  bool _loading = true;
  bool _failed = false;

  String _pickDisplayPath() {
    final thumb = ChurchChatMessageFields.thumbStoragePath(widget.data);
    if (thumb.isNotEmpty) return thumb;
    return ChurchChatMessageFields.storagePath(widget.data);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChurchChatStorageMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = _pathKey(oldWidget.data);
    final newPath = _pathKey(widget.data);
    if (oldPath != newPath) {
      unawaited(_load());
    }
  }

  String _pathKey(Map<String, dynamic> d) {
    final thumb = ChurchChatMessageFields.thumbStoragePath(d);
    if (thumb.isNotEmpty) return thumb;
    return ChurchChatMessageFields.storagePath(d);
  }

  Future<void> _load() async {
    final path = _pickDisplayPath();
    final legacyUrl = ChurchChatMessageFields.mediaUrl(widget.data);
    final cacheKey = path.isNotEmpty ? path : legacyUrl.trim();

    if (cacheKey.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }

    final ramHit = _chatThumbRamCache[cacheKey];
    if (ramHit != null && ramHit.length > 32) {
      if (mounted) {
        setState(() {
          _bytes = ramHit;
          _loading = false;
          _failed = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _bytes = null;
        _networkUrl = null;
      });
    }

    Uint8List? data;
    if (path.isNotEmpty) {
      data = await ChurchChatMediaResolver.downloadBytes(
        storagePath: path,
        maxBytes: 4 * 1024 * 1024,
      ).timeout(
        const Duration(seconds: 14),
        onTimeout: () => null,
      );
    }

    if ((data == null || data.length < 32) && legacyUrl.isNotEmpty) {
      final url = sanitizeImageUrl(legacyUrl);
      if (isValidImageUrl(url) || firebaseStorageMediaUrlLooksLike(legacyUrl)) {
        data = await ChurchChatMediaResolver.downloadBytes(
          storagePath: legacyUrl,
          maxBytes: 4 * 1024 * 1024,
        ).timeout(
          const Duration(seconds: 14),
          onTimeout: () => null,
        );
      }
    }

    String? resolvedUrl;
    if (data == null || data.length < 32) {
      resolvedUrl = await ChurchChatMediaResolver.resolveDownloadUrl(
        storagePath: path.isNotEmpty ? path : legacyUrl,
        tenantId: widget.tenantId,
        messageId: widget.messageId,
        fastPreview: true,
      );
      if ((resolvedUrl == null || resolvedUrl.isEmpty) && legacyUrl.isNotEmpty) {
        resolvedUrl = sanitizeImageUrl(legacyUrl);
      }
    }

    if (!mounted) return;
    if (data != null && data.length > 32) {
      _chatThumbRamPut(cacheKey, data);
      setState(() {
        _bytes = data;
        _networkUrl = null;
        _loading = false;
        _failed = false;
      });
      return;
    }

    if (resolvedUrl != null &&
        resolvedUrl.isNotEmpty &&
        (isValidImageUrl(resolvedUrl) ||
            firebaseStorageMediaUrlLooksLike(resolvedUrl))) {
      setState(() {
        _bytes = null;
        _networkUrl = resolvedUrl;
        _loading = false;
        _failed = false;
      });
      return;
    }

    setState(() {
      _bytes = null;
      _networkUrl = null;
      _loading = false;
      _failed = true;
    });
  }

  Widget _placeholder() {
    return Container(
      width: widget.width,
      height: widget.height ?? 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFE8F5E9),
            const Color(0xFF128C7E).withValues(alpha: 0.12),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: const Color(0xFF128C7E).withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _errorBody() {
    return Material(
      color: const Color(0xFFF1F5F9),
      child: InkWell(
        onTap: () => unawaited(_load()),
        child: Container(
          width: widget.width,
          height: widget.height ?? 120,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: Colors.grey.shade600, size: 28),
              const SizedBox(height: 6),
              Text(
                'Toque para recarregar',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: widget.memCacheWidth,
        cacheHeight: widget.memCacheHeight,
      );
    } else if (_networkUrl != null && _networkUrl!.isNotEmpty) {
      child = FreshFirebaseStorageImage(
        imageUrl: _networkUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: widget.memCacheWidth,
        memCacheHeight: widget.memCacheHeight,
        placeholder: _placeholder(),
        errorWidget: _errorBody(),
      );
    } else if (_failed) {
      child = _errorBody();
    } else if (_loading) {
      child = _placeholder();
    } else {
      child = _errorBody();
    }

    child = ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: child,
    );

    if (widget.onTap != null) {
      return GestureDetector(onTap: widget.onTap, child: child);
    }
    return child;
  }
}

/// Documento PDF/DOC — card com preview e botão «Visualizar».
class ChurchChatDocumentBubble extends StatefulWidget {
  const ChurchChatDocumentBubble({
    super.key,
    required this.data,
    required this.type,
    required this.tenantId,
    required this.messageId,
    this.onOpenExternally,
  });

  final Map<String, dynamic> data;
  final String type;
  final String tenantId;
  final String messageId;
  final Future<void> Function(String url)? onOpenExternally;

  @override
  State<ChurchChatDocumentBubble> createState() =>
      _ChurchChatDocumentBubbleState();
}

class _ChurchChatDocumentBubbleState extends State<ChurchChatDocumentBubble> {
  bool _opening = false;

  String get _displayName {
    final name = ChurchChatMessageFields.fileName(widget.data);
    return name.isEmpty ? 'Documento' : name;
  }

  IconData get _icon {
    switch (widget.type) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
        return Icons.description_rounded;
      case 'xls':
        return Icons.table_chart_rounded;
      case 'zip':
        return Icons.folder_zip_rounded;
      default:
        final lower = _displayName.toLowerCase();
        if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
        if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
          return Icons.description_rounded;
        }
        if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
          return Icons.table_chart_rounded;
        }
        if (lower.endsWith('.zip')) return Icons.folder_zip_rounded;
        return Icons.insert_drive_file_rounded;
    }
  }

  bool get _isPdf =>
      widget.type == 'pdf' || _displayName.toLowerCase().endsWith('.pdf');

  Future<void> _openPreview() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final sp = ChurchChatMessageFields.storagePath(widget.data);
      if (_isPdf) {
        final bytes = await ChurchChatMediaResolver.downloadBytes(
          storagePath: sp,
        );
        if (!mounted) return;
        if (bytes != null && bytes.isNotEmpty) {
          await showPdfActions(
            context,
            bytes: bytes,
            filename: _displayName.endsWith('.pdf')
                ? _displayName
                : '$_displayName.pdf',
          );
          return;
        }
      }
      final url = await ChurchChatMediaResolver.resolveDownloadUrl(
        storagePath: sp,
        tenantId: widget.tenantId,
        messageId: widget.messageId,
      );
      final openUrl = url ?? ChurchChatMessageFields.mediaUrl(widget.data);
      if (openUrl.isNotEmpty && widget.onOpenExternally != null) {
        await widget.onOpenExternally!.call(openUrl);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Não foi possível abrir o ficheiro.'),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = ChurchChatMessageFields.fileSize(widget.data);
    final sp = ChurchChatMessageFields.storagePath(widget.data);
    final hasPath = sp.isNotEmpty && firebaseStorageMediaUrlLooksLike(sp);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _opening ? null : _openPreview,
        child: Container(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                ThemeCleanPremium.primary.withValues(alpha: 0.04),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF128C7E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_icon, color: const Color(0xFF128C7E), size: 28),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (size != null && size > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            ChurchChatAttachmentUtils.formatFileSize(size),
                            style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _opening ? null : _openPreview,
                icon: _opening
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isPdf
                            ? Icons.visibility_rounded
                            : Icons.open_in_new_rounded,
                        size: 18,
                      ),
                label: Text(
                  _isPdf ? 'Visualizar' : 'Abrir',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      ThemeCleanPremium.primary.withValues(alpha: 0.1),
                  foregroundColor: ThemeCleanPremium.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (hasPath)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Toque para ${_isPdf ? 'pré-visualizar' : 'abrir'} o ficheiro',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
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

/// Vídeo recebido — resolve URL do Storage e abre teatro ao toque.
class ChurchChatStorageVideoBubble extends StatefulWidget {
  const ChurchChatStorageVideoBubble({
    super.key,
    required this.data,
    this.tenantId,
    this.messageId,
    this.mine = false,
  });

  final Map<String, dynamic> data;
  final String? tenantId;
  final String? messageId;
  final bool mine;

  @override
  State<ChurchChatStorageVideoBubble> createState() =>
      _ChurchChatStorageVideoBubbleState();
}

class _ChurchChatStorageVideoBubbleState
    extends State<ChurchChatStorageVideoBubble> {
  String? _videoUrl;
  String? _thumbUrl;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChurchChatStorageVideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ChurchChatMessageFields.storagePath(oldWidget.data) !=
            ChurchChatMessageFields.storagePath(widget.data) ||
        ChurchChatMessageFields.mediaUrl(oldWidget.data) !=
            ChurchChatMessageFields.mediaUrl(widget.data)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _videoUrl = null;
        _thumbUrl = null;
      });
    }
    final sp = ChurchChatMessageFields.storagePath(widget.data);
    final legacy = ChurchChatMessageFields.mediaUrl(widget.data);
    final thumbSp = ChurchChatMessageFields.thumbStoragePath(widget.data);
    final thumbLegacy = ChurchChatMessageFields.thumbnailUrl(widget.data);

    final videoUrl = await ChurchChatMediaResolver.resolveDownloadUrl(
          storagePath: sp.isNotEmpty ? sp : legacy,
          tenantId: widget.tenantId,
          messageId: widget.messageId,
        ) ??
        (legacy.isNotEmpty ? legacy : null);
    String? thumbUrl;
    if (thumbSp.isNotEmpty || thumbLegacy.isNotEmpty) {
      thumbUrl = await ChurchChatMediaResolver.resolveDownloadUrl(
            storagePath: thumbSp.isNotEmpty ? thumbSp : thumbLegacy,
            tenantId: widget.tenantId,
            messageId: widget.messageId,
            fastPreview: true,
          ) ??
          (thumbLegacy.isNotEmpty ? thumbLegacy : null);
    }

    if (!mounted) return;
    if (videoUrl == null || videoUrl.trim().isEmpty) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    setState(() {
      _videoUrl = videoUrl.trim();
      _thumbUrl = thumbUrl?.trim();
      _loading = false;
      _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: 260,
        height: 146,
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
            ),
          ),
        ),
      );
    }
    if (_failed || _videoUrl == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.6),
          child: InkWell(
            onTap: () => unawaited(_load()),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Toque para carregar o vídeo'),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ChurchChatVideoMessageBubble(
      videoUrl: _videoUrl!,
      thumbnailUrl: _thumbUrl,
      fileName: ChurchChatMessageFields.fileName(widget.data),
      mine: widget.mine,
      onDownload: (url, {String fileName = ''}) => churchChatShareDownloadVideo(
        context,
        url,
        fileName: fileName,
      ),
    );
  }
}
