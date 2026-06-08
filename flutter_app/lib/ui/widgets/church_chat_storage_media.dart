import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_media_resolver.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Exibe mídia do chat via [storagePath] — timeout 15s, erro com retry, sem spinner infinito.
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

enum _MediaLoadPhase { loading, ready, error }

class _ChurchChatStorageMediaImageState extends State<ChurchChatStorageMediaImage> {
  _MediaLoadPhase _phase = _MediaLoadPhase.loading;
  String? _resolvedUrl;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChurchChatStorageMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = ChurchChatMessageFields.storagePath(oldWidget.data);
    final newPath = ChurchChatMessageFields.storagePath(widget.data);
    if (oldPath != newPath) {
      _attempt = 0;
      unawaited(_load());
    }
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _phase = _MediaLoadPhase.loading;
      _resolvedUrl = null;
    });

    final path = ChurchChatMessageFields.storagePath(widget.data);
    final legacyUrl = ChurchChatMessageFields.mediaUrl(widget.data);

    try {
      String? url;
      if (path.isNotEmpty) {
        url = await ChurchChatMediaResolver.resolveDownloadUrl(
          storagePath: path,
          tenantId: widget.tenantId,
          messageId: widget.messageId,
          forceRefresh: force,
        );
      }
      url ??= legacyUrl.isNotEmpty ? legacyUrl : null;

      if (!mounted) return;
      if (url == null || url.trim().isEmpty) {
        setState(() => _phase = _MediaLoadPhase.error);
        return;
      }
      setState(() {
        _resolvedUrl = url;
        _phase = _MediaLoadPhase.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _MediaLoadPhase.error);
    }
  }

  Widget _errorBody() {
    return Container(
      width: widget.width,
      height: widget.height ?? 120,
      color: const Color(0xFFF1F5F9),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.grey.shade600, size: 32),
          const SizedBox(height: 6),
          Text(
            'Falha ao carregar mídia',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              _attempt++;
              ChurchChatMediaResolver.forgetPath(
                ChurchChatMessageFields.storagePath(widget.data),
              );
              unawaited(_load(force: true));
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar novamente'),
            style: TextButton.styleFrom(
              foregroundColor: ThemeCleanPremium.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingBody() {
    return Container(
      width: widget.width,
      height: widget.height ?? 120,
      color: const Color(0xFFE2E8F0),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Carregando...',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (_phase) {
      case _MediaLoadPhase.loading:
        child = _loadingBody();
      case _MediaLoadPhase.error:
        child = _errorBody();
      case _MediaLoadPhase.ready:
        child = SafeNetworkImage(
          imageUrl: _resolvedUrl!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          memCacheWidth: widget.memCacheWidth,
          memCacheHeight: widget.memCacheHeight,
          skipFreshDisplayUrl: true,
        );
    }

    child = ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: child,
    );

    if (widget.onTap != null && _phase == _MediaLoadPhase.ready) {
      return GestureDetector(onTap: widget.onTap, child: child);
    }
    return child;
  }
}
