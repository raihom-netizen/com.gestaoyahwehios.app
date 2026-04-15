import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Imagem estável: resolve path/gs/https via [AppStorageImageService] e exibe com [ResilientNetworkImage].
class StableStorageImage extends StatefulWidget {
  const StableStorageImage({
    super.key,
    this.storagePath,
    this.imageUrl,
    this.gsUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
    this.onLoadError,
    /// `false` = renovar token Storage na web antes dos bytes (painel avisos/eventos com URL antiga).
    this.skipFreshDisplayUrl = true,
  });

  final String? storagePath;
  final String? imageUrl;
  final String? gsUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? memCacheWidth;
  final int? memCacheHeight;
  /// Diagnóstico (ex.: mural): falha ao resolver URL ou carregar bytes.
  final void Function(String url, Object? error)? onLoadError;
  final bool skipFreshDisplayUrl;

  @override
  State<StableStorageImage> createState() => _StableStorageImageState();
}

class _StableStorageImageState extends State<StableStorageImage> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant StableStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (AppStorageImageService.cacheKey(
          storagePath: oldWidget.storagePath,
          imageUrl: oldWidget.imageUrl,
          gsUrl: oldWidget.gsUrl,
        ) !=
        AppStorageImageService.cacheKey(
          storagePath: widget.storagePath,
          imageUrl: widget.imageUrl,
          gsUrl: widget.gsUrl,
        ) ||
        oldWidget.skipFreshDisplayUrl != widget.skipFreshDisplayUrl) {
      _future = _load();
    }
  }

  Future<String?> _load() => AppStorageImageService.instance.resolveImageUrl(
        storagePath: widget.storagePath,
        imageUrl: widget.imageUrl,
        gsUrl: widget.gsUrl,
      );

  @override
  Widget build(BuildContext context) {
    final ph = widget.placeholder ??
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
    final err = widget.errorWidget ??
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: 36),
        );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FutureBuilder<String?>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            widget.onLoadError?.call(
                widget.imageUrl ?? widget.storagePath ?? widget.gsUrl ?? '',
                snap.error!);
            return err;
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return ph;
          }
          final u = snap.data;
          final clean = u != null ? sanitizeImageUrl(u) : '';
          final canDisplay = clean.isNotEmpty &&
              (isValidImageUrl(clean) ||
                  clean.toLowerCase().startsWith('gs://') ||
                  firebaseStorageMediaUrlLooksLike(clean));
          if (!canDisplay) {
            widget.onLoadError?.call(
                widget.imageUrl ?? widget.storagePath ?? widget.gsUrl ?? '',
                StateError('resolveImageUrl vazio ou inválido: ${u ?? "null"}'));
            return err;
          }
          // [ResilientNetworkImage]: renova token Storage antes do decode (igual carteirinha, mural).
          Widget img = ResilientNetworkImage(
            key: ValueKey<String>('stable_$clean'),
            imageUrl: clean,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            memCacheWidth: widget.memCacheWidth,
            memCacheHeight: widget.memCacheHeight,
            placeholder: ph,
            errorWidget: err,
            onLoadError: widget.onLoadError,
          );
          if (widget.borderRadius != null) {
            img = ClipRRect(borderRadius: widget.borderRadius!, child: img);
          }
          return img;
        },
      ),
    );
  }
}

/// Logo da igreja — cantos 16px, contain, ícone se vazio/erro.
/// Com [tenantId], tenta também caminhos padrão no Storage (ex.: `branding/logo_igreja.jpg`) quando o Firestore não tem URL.
class StableChurchLogo extends StatefulWidget {
  const StableChurchLogo({
    super.key,
    this.storagePath,
    this.imageUrl,
    this.gsUrl,
    this.tenantId,
    this.tenantData,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    this.memCacheWidth,
    this.memCacheHeight,
    /// Ex.: spinner no tom do cabeçalho escuro (site público).
    this.loadingPlaceholder,
  });

  final String? storagePath;
  final String? imageUrl;
  final String? gsUrl;
  final String? tenantId;
  final Map<String, dynamic>? tenantData;
  final double width;
  final double height;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget? loadingPlaceholder;

  @override
  State<StableChurchLogo> createState() => _StableChurchLogoState();
}

class _StableChurchLogoState extends State<StableChurchLogo> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant StableChurchLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_propsChanged(oldWidget)) {
      _future = _load();
    }
  }

  bool _propsChanged(StableChurchLogo o) {
    return o.storagePath != widget.storagePath ||
        o.imageUrl != widget.imageUrl ||
        o.gsUrl != widget.gsUrl ||
        o.tenantId != widget.tenantId ||
        o.fit != widget.fit ||
        o.width != widget.width ||
        o.height != widget.height ||
        o.memCacheWidth != widget.memCacheWidth ||
        o.memCacheHeight != widget.memCacheHeight ||
        o.loadingPlaceholder != widget.loadingPlaceholder ||
        _tenantSig(o.tenantData) != _tenantSig(widget.tenantData);
  }

  String _tenantSig(Map<String, dynamic>? m) {
    if (m == null) return '';
    final u = m['updatedAt'] ?? m['updated_at'];
    var uStr = '';
    if (u is Timestamp) {
      uStr = '${u.seconds}';
    } else if (u != null) {
      uStr = u.toString();
    }
    return '${churchTenantLogoUrl(m)}|${ChurchImageFields.logoStoragePath(m) ?? ''}|$uStr';
  }

  Future<String?> _load() {
    final tid = widget.tenantId?.trim() ?? '';
    if (tid.isNotEmpty) {
      return AppStorageImageService.instance.resolveChurchTenantLogoUrl(
        tenantId: tid,
        tenantData: widget.tenantData,
        preferImageUrl: widget.imageUrl,
        preferStoragePath: widget.storagePath,
        preferGsUrl: widget.gsUrl,
      );
    }
    return AppStorageImageService.instance.resolveImageUrl(
      storagePath: widget.storagePath,
      imageUrl: widget.imageUrl,
      gsUrl: widget.gsUrl,
    );
  }

  Widget _fallback() {
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      child: Icon(
        Icons.church_rounded,
        size: (widget.width < widget.height ? widget.width : widget.height) * 0.35,
        color: Colors.grey.shade400,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = widget.loadingPlaceholder ??
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade500),
            ),
          ),
        );
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FutureBuilder<String?>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return _fallback();
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return ph;
          }
          final u = snap.data;
          final clean = u != null ? sanitizeImageUrl(u) : '';
          final canDisplay = clean.isNotEmpty &&
              (isValidImageUrl(clean) ||
                  clean.toLowerCase().startsWith('gs://') ||
                  firebaseStorageMediaUrlLooksLike(clean));
          if (!canDisplay) {
            return _fallback();
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ResilientNetworkImage(
              key: ValueKey<String>('church_logo_$clean'),
              imageUrl: clean,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              memCacheWidth: widget.memCacheWidth,
              memCacheHeight: widget.memCacheHeight,
              placeholder: ph,
              errorWidget: _fallback(),
            ),
          );
        },
      ),
    );
  }
}

/// Miniatura circular da logo (mural, feed) — resolve URL + fallback no Storage.
class ChurchTenantLogoCircleAvatar extends StatefulWidget {
  const ChurchTenantLogoCircleAvatar({
    super.key,
    required this.tenantId,
    this.tenantData,
    this.preferImageUrl,
    this.radius = 16,
    this.fallbackIcon = Icons.church_rounded,
    this.fallbackColor,
    this.backgroundColor,
    this.memCacheSize,
  });

  final String tenantId;
  final Map<String, dynamic>? tenantData;
  final String? preferImageUrl;
  final double radius;
  final IconData fallbackIcon;
  final Color? fallbackColor;
  final Color? backgroundColor;
  final int? memCacheSize;

  @override
  State<ChurchTenantLogoCircleAvatar> createState() => _ChurchTenantLogoCircleAvatarState();
}

class _ChurchTenantLogoCircleAvatarState extends State<ChurchTenantLogoCircleAvatar> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ChurchTenantLogoCircleAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.preferImageUrl != widget.preferImageUrl ||
        _sig(oldWidget.tenantData) != _sig(widget.tenantData)) {
      _future = _load();
    }
  }

  String _sig(Map<String, dynamic>? m) {
    if (m == null) return '';
    return '${churchTenantLogoUrl(m)}|${ChurchImageFields.logoStoragePath(m) ?? ''}';
  }

  Future<String?> _load() {
    return AppStorageImageService.instance.resolveChurchTenantLogoUrl(
      tenantId: widget.tenantId,
      tenantData: widget.tenantData,
      preferImageUrl: widget.preferImageUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? Colors.grey.shade200;
    final iconColor = widget.fallbackColor ?? Colors.grey.shade600;
    final fallback = CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      child: Icon(widget.fallbackIcon, size: widget.radius * 1.1, color: iconColor),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = widget.memCacheSize ??
        memCacheExtentForLogicalSize(
          widget.radius * 2,
          dpr,
          maxPx: 640,
        );
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return fallback;
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return CircleAvatar(
            radius: widget.radius,
            backgroundColor: bg,
            child: SizedBox(
              width: widget.radius,
              height: widget.radius,
              child: CircularProgressIndicator(strokeWidth: 2, color: iconColor.withOpacity(0.7)),
            ),
          );
        }
        final u = snap.data;
        final clean = u != null ? sanitizeImageUrl(u) : '';
        final canDisplay = clean.isNotEmpty &&
            (isValidImageUrl(clean) ||
                clean.toLowerCase().startsWith('gs://') ||
                firebaseStorageMediaUrlLooksLike(clean));
        if (!canDisplay) {
          return fallback;
        }
        return ClipOval(
          child: SizedBox(
            width: widget.radius * 2,
            height: widget.radius * 2,
            child: ResilientNetworkImage(
              key: ValueKey<String>('church_circle_$clean'),
              imageUrl: clean,
              fit: BoxFit.cover,
              width: widget.radius * 2,
              height: widget.radius * 2,
              memCacheWidth: cacheSize,
              memCacheHeight: cacheSize,
              placeholder: fallback,
              errorWidget: fallback,
            ),
          ),
        );
      },
    );
  }
}

/// Avatar de membro — delega a [FotoMembroWidget] (Storage + URL + fallback estável em listas).
class StableMemberAvatar extends StatelessWidget {
  const StableMemberAvatar({
    super.key,
    required this.imageUrl,
    required this.tenantId,
    required this.memberId,
    this.cpfDigits,
    this.authUid,
    this.memberData,
    this.size = 44,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String? imageUrl;
  final String tenantId;
  final String memberId;
  final String? cpfDigits;
  final String? authUid;
  /// Dados do documento Firestore — necessário para resolver path/`gs://` sem URL https na UI.
  final Map<String, dynamic>? memberData;
  final double size;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    return FotoMembroWidget(
      key: ValueKey<String>('stable_av_${tenantId}_$memberId'),
      imageUrl: imageUrl,
      size: size,
      tenantId: tenantId,
      memberId: memberId,
      cpfDigits: cpfDigits,
      authUid: authUid,
      memberData: memberData,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
    );
  }
}
