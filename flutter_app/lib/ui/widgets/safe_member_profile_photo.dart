import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show ResilientNetworkImage, isValidImageUrl, sanitizeImageUrl;

/// Para [ValueKey] e atualização visual após troca de foto ([fotoUrlCacheRevision] ou timestamps).
int? memberPhotoDisplayCacheRevision(Map<String, dynamic> data) {
  final r = data['fotoUrlCacheRevision'];
  if (r is int) return r;
  if (r is num) return r.toInt();
  final t = data['ATUALIZADO_EM'];
  if (t is Timestamp) return t.millisecondsSinceEpoch;
  final c = data['CRIADO_EM'];
  if (c is Timestamp) return c.millisecondsSinceEpoch;
  return null;
}

/// Foto do membro com fallback para `igrejas/{tenant}/membros/{id}.jpg` (mesmo padrão da lista de membros).
///
/// Renova URL do Storage com [StorageMediaService.freshPlayableMediaUrl] e exibe com [ResilientNetworkImage]
/// (tokens expirados / host `*.firebasestorage.app` — mesmo padrão do patrimônio).
class SafeMemberProfilePhoto extends StatefulWidget {
  final String? imageUrl;
  final String? tenantId;
  final String? memberId;
  final String? cpfDigits;
  /// Foto salva com UID do Firebase quando o doc do membro usa outro id (ex.: CPF).
  final String? authUid;
  /// [NOME_COMPLETO] para localizar pasta `PrimeiroNome_uid` no Storage.
  final String? nomeCompleto;
  final double width;
  final double height;
  final bool circular;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorChild;
  final bool enableStorageFallback;
  final int? memCacheWidth;
  final int? memCacheHeight;
  /// Muda após upload (ex.: [memberPhotoDisplayCacheRevision]) para forçar novo decode/cache.
  final int? imageCacheRevision;
  /// Dados do doc Firestore: extrai pasta `membros/{id}/` de URLs salvas (token expirado / id ≠ doc).
  final Map<String, dynamic>? memberFirestoreHint;

  const SafeMemberProfilePhoto({
    super.key,
    this.imageUrl,
    this.tenantId,
    this.memberId,
    this.cpfDigits,
    this.authUid,
    this.nomeCompleto,
    this.memberFirestoreHint,
    required this.width,
    required this.height,
    this.circular = true,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorChild,
    this.enableStorageFallback = true,
    this.memCacheWidth,
    this.memCacheHeight,
    this.imageCacheRevision,
  });

  @override
  State<SafeMemberProfilePhoto> createState() => _SafeMemberProfilePhotoState();
}

class _SafeMemberProfilePhotoState extends State<SafeMemberProfilePhoto> {
  String? _displayUrl;
  bool _resolving = false;

  int _defaultCacheDim(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final edge = (widget.width > widget.height ? widget.width : widget.height) * dpr;
    return edge.round().clamp(96, 640);
  }

  @override
  void initState() {
    super.initState();
    _resolveDisplayUrl();
  }

  @override
  void didUpdateWidget(covariant SafeMemberProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlChanged =
        sanitizeImageUrl(oldWidget.imageUrl) != sanitizeImageUrl(widget.imageUrl);
    final idsChanged = oldWidget.tenantId != widget.tenantId ||
        oldWidget.memberId != widget.memberId ||
        (oldWidget.cpfDigits ?? '') != (widget.cpfDigits ?? '') ||
        (oldWidget.authUid ?? '') != (widget.authUid ?? '') ||
        (oldWidget.nomeCompleto ?? '') != (widget.nomeCompleto ?? '') ||
        oldWidget.enableStorageFallback != widget.enableStorageFallback ||
        oldWidget.imageCacheRevision != widget.imageCacheRevision ||
        !identical(
            oldWidget.memberFirestoreHint, widget.memberFirestoreHint);
    if (urlChanged || idsChanged) {
      _resolveDisplayUrl();
    }
  }

  Future<void> _resolveDisplayUrl() async {
    final norm = sanitizeImageUrl(widget.imageUrl);
    if (!isValidImageUrl(norm)) {
      if (mounted) setState(() => _displayUrl = null);
      return;
    }
    final needsFresh = StorageMediaService.isFirebaseStorageMediaUrl(norm);
    // Mostrar já a URL conhecida; renovar token em background (lista/detalhe abre mais rápido).
    if (mounted) {
      setState(() {
        _displayUrl = norm;
        _resolving = needsFresh;
      });
    }
    if (!needsFresh) return;
    String out = norm;
    try {
      out = sanitizeImageUrl(
          await StorageMediaService.freshPlayableMediaUrl(norm));
    } catch (_) {
      out = norm;
    }
    if (!mounted) return;
    setState(() {
      _displayUrl = isValidImageUrl(out) ? out : norm;
      _resolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tid = widget.tenantId?.trim() ?? '';
    final mid = widget.memberId?.trim() ?? '';
    final canStorage = widget.enableStorageFallback && tid.isNotEmpty && mid.isNotEmpty;
    final norm = sanitizeImageUrl(widget.imageUrl);
    final valid = isValidImageUrl(norm);
    final fallbackMc = _defaultCacheDim(context);
    final mcW = widget.memCacheWidth ?? widget.memCacheHeight ?? fallbackMc;
    final mcH = widget.memCacheHeight ?? widget.memCacheWidth ?? fallbackMc;
    final err = widget.errorChild ??
        Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: Icon(Icons.person_rounded, size: widget.width * 0.45, color: Colors.grey.shade500),
        );

    Widget core(Widget child) {
      if (widget.circular) {
        return ClipOval(child: SizedBox(width: widget.width, height: widget.height, child: child));
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(width: widget.width, height: widget.height, child: child),
      );
    }

    if (!valid) {
      if (canStorage) {
        return core(_MemberPhotoStorageFallback(
          tenantId: tid,
          memberId: mid,
          cpfDigits: widget.cpfDigits,
          authUid: widget.authUid,
          nomeCompleto: widget.nomeCompleto,
          memberFirestoreHint: widget.memberFirestoreHint,
          sourceImageUrl: widget.imageUrl,
          imageCacheRevision: widget.imageCacheRevision,
          width: widget.width,
          height: widget.height,
          memCacheW: mcW,
          memCacheH: mcH,
          fit: widget.fit,
          placeholder: widget.placeholder,
          errorChild: err,
        ));
      }
      return core(err);
    }

    final rev = widget.imageCacheRevision ?? 0;

    if (_resolving && _displayUrl == null) {
      return core(widget.placeholder ?? err);
    }

    final url = _displayUrl ?? norm;
    if (!isValidImageUrl(url)) {
      if (canStorage) {
        return core(_MemberPhotoStorageFallback(
          tenantId: tid,
          memberId: mid,
          cpfDigits: widget.cpfDigits,
          authUid: widget.authUid,
          nomeCompleto: widget.nomeCompleto,
          memberFirestoreHint: widget.memberFirestoreHint,
          sourceImageUrl: widget.imageUrl,
          imageCacheRevision: widget.imageCacheRevision,
          width: widget.width,
          height: widget.height,
          memCacheW: mcW,
          memCacheH: mcH,
          fit: widget.fit,
          placeholder: widget.placeholder,
          errorChild: err,
        ));
      }
      return core(err);
    }

    return core(
      ResilientNetworkImage(
        key: ValueKey<String>('smp_${url}_${tid}_${mid}_$rev'),
        imageUrl: url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: mcW,
        memCacheHeight: mcH,
        placeholder: widget.placeholder ?? err,
        errorWidget: canStorage
            ? _MemberPhotoStorageFallback(
                tenantId: tid,
                memberId: mid,
                cpfDigits: widget.cpfDigits,
                authUid: widget.authUid,
                nomeCompleto: widget.nomeCompleto,
                memberFirestoreHint: widget.memberFirestoreHint,
                sourceImageUrl: widget.imageUrl,
                imageCacheRevision: widget.imageCacheRevision,
                width: widget.width,
                height: widget.height,
                memCacheW: mcW,
                memCacheH: mcH,
                fit: widget.fit,
                placeholder: widget.placeholder,
                errorChild: err,
              )
            : err,
      ),
    );
  }
}

/// Avatar circular — atalho para lista / seletores.
class SafeMemberCircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? tenantId;
  final String? memberId;
  final String? cpfDigits;
  final String? authUid;
  final String? nomeCompleto;
  final Map<String, dynamic>? memberFirestoreHint;
  final double radius;
  final Color? backgroundColor;
  final IconData fallbackIcon;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? imageCacheRevision;

  const SafeMemberCircleAvatar({
    super.key,
    this.imageUrl,
    this.tenantId,
    this.memberId,
    this.cpfDigits,
    this.authUid,
    this.nomeCompleto,
    this.memberFirestoreHint,
    this.radius = 22,
    this.backgroundColor,
    this.fallbackIcon = Icons.person_rounded,
    this.memCacheWidth,
    this.memCacheHeight,
    this.imageCacheRevision,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? ThemeCleanPremium.primary.withOpacity(0.15);
    return SafeMemberProfilePhoto(
      imageUrl: imageUrl,
      tenantId: tenantId,
      memberId: memberId,
      cpfDigits: cpfDigits,
      authUid: authUid,
      nomeCompleto: nomeCompleto,
      memberFirestoreHint: memberFirestoreHint,
      width: radius * 2,
      height: radius * 2,
      circular: true,
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      imageCacheRevision: imageCacheRevision,
      errorChild: CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Icon(fallbackIcon, size: radius * 1.05, color: ThemeCleanPremium.primary),
      ),
    );
  }
}

class _MemberPhotoStorageFallback extends StatefulWidget {
  final String tenantId;
  final String memberId;
  final String? cpfDigits;
  final String? authUid;
  final String? nomeCompleto;
  final Map<String, dynamic>? memberFirestoreHint;
  final String? sourceImageUrl;
  final double width;
  final double height;
  final int memCacheW;
  final int memCacheH;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget errorChild;
  final int? imageCacheRevision;

  const _MemberPhotoStorageFallback({
    required this.tenantId,
    required this.memberId,
    this.cpfDigits,
    this.authUid,
    this.nomeCompleto,
    this.memberFirestoreHint,
    this.sourceImageUrl,
    this.imageCacheRevision,
    required this.width,
    required this.height,
    required this.memCacheW,
    required this.memCacheH,
    required this.fit,
    this.placeholder,
    required this.errorChild,
  });

  @override
  State<_MemberPhotoStorageFallback> createState() => _MemberPhotoStorageFallbackState();
}

class _MemberPhotoStorageFallbackState extends State<_MemberPhotoStorageFallback> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolveFallbackUrl();
  }

  @override
  void didUpdateWidget(covariant _MemberPhotoStorageFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = sanitizeImageUrl(oldWidget.sourceImageUrl) !=
        sanitizeImageUrl(widget.sourceImageUrl);
    final idChanged = oldWidget.tenantId != widget.tenantId ||
        oldWidget.memberId != widget.memberId ||
        (oldWidget.cpfDigits ?? '') != (widget.cpfDigits ?? '') ||
        (oldWidget.authUid ?? '') != (widget.authUid ?? '') ||
        (oldWidget.nomeCompleto ?? '') != (widget.nomeCompleto ?? '') ||
        oldWidget.imageCacheRevision != widget.imageCacheRevision ||
        !identical(
            oldWidget.memberFirestoreHint, widget.memberFirestoreHint);
    if (sourceChanged || idChanged) {
      _future = _resolveFallbackUrl();
    }
  }

  Future<String?> _resolveFallbackUrl() async {
    Future<String?> inner() async {
    final raw = (widget.sourceImageUrl ?? '').trim();
    if (raw.isNotEmpty) {
      final s = sanitizeImageUrl(raw);
      if (s.isNotEmpty) {
        if (isValidImageUrl(s)) {
          try {
            final fresh = await StorageMediaService.freshPlayableMediaUrl(s);
            final out = sanitizeImageUrl(fresh);
            if (isValidImageUrl(out)) return out;
          } catch (_) {}
        }
        final bySource = await StorageMediaService.downloadUrlFromPathOrUrl(raw);
        final cleanSource = sanitizeImageUrl(bySource ?? raw);
        if (cleanSource.isNotEmpty && isValidImageUrl(cleanSource)) {
          return cleanSource;
        }
      }
    }
    return FirebaseStorageService.getMemberProfilePhotoDownloadUrl(
      tenantId: widget.tenantId,
      memberId: widget.memberId,
      cpfDigits: widget.cpfDigits,
      authUid: widget.authUid,
      nomeCompleto: widget.nomeCompleto,
      memberFirestoreHint: widget.memberFirestoreHint,
    );
    }

    try {
      return await inner().timeout(const Duration(seconds: 22),
          onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return widget.errorChild;
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return widget.placeholder ?? widget.errorChild;
        }
        final u = snap.data;
        final clean = u != null ? sanitizeImageUrl(u) : '';
        if (clean.isNotEmpty && isValidImageUrl(clean)) {
          final rev = widget.imageCacheRevision ?? 0;
          return ResilientNetworkImage(
            key: ValueKey<String>('mfs_${clean}_$rev'),
            imageUrl: clean,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            memCacheWidth: widget.memCacheW,
            memCacheHeight: widget.memCacheH,
            placeholder: widget.placeholder,
            errorWidget: widget.errorChild,
          );
        }
        return widget.errorChild;
      },
    );
  }
}
