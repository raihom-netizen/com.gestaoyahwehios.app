import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_media_resolver.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show FirebaseStorageMemoryImage, firebaseStorageMediaUrlLooksLike;
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart' show showPdfActions;

/// Miniatura / imagem do chat — lê directo do [storagePath] (sem getMetadata bloqueante).
class ChurchChatStorageMediaImage extends StatelessWidget {
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

  String _pickDisplayPath() {
    final thumb = ChurchChatMessageFields.thumbStoragePath(data);
    if (thumb.isNotEmpty) return thumb;
    return ChurchChatMessageFields.storagePath(data);
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height ?? 120,
      color: const Color(0xFFE2E8F0),
      alignment: Alignment.center,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _errorBody() {
    return Container(
      width: width,
      height: height ?? 120,
      color: const Color(0xFFF1F5F9),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.grey.shade600, size: 32),
          const SizedBox(height: 6),
          Text(
            'Falha ao carregar',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = _pickDisplayPath();
    final legacyUrl = ChurchChatMessageFields.mediaUrl(data);
    final displayKey =
        path.isNotEmpty ? path : (legacyUrl.isNotEmpty ? legacyUrl : '');

    if (displayKey.isEmpty) {
      return ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: _errorBody(),
      );
    }

    Widget child = FirebaseStorageMemoryImage(
      key: ValueKey<String>('chat_img_$displayKey'),
      imageUrl: displayKey,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      skipFreshDisplayUrl: true,
      placeholder: _placeholder(),
      errorWidget: _errorBody(),
    );

    child = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
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
