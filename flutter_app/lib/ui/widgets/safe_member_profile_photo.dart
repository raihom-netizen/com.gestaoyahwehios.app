import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        MemberProfilePhotoBytesCache,
        ResilientNetworkImage,
        firebaseStorageMediaUrlLooksLike,
        isValidImageUrl,
        sanitizeImageUrl;

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
  final bool preferListThumbnail;

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
    this.preferListThumbnail = false,
  });

  @override
  State<SafeMemberProfilePhoto> createState() => _SafeMemberProfilePhotoState();
}

class _SafeMemberProfilePhotoState extends State<SafeMemberProfilePhoto> {
  String? _displayUrl;
  String? _variantFallbackUrl;
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
        oldWidget.preferListThumbnail != widget.preferListThumbnail ||
        !identical(
            oldWidget.memberFirestoreHint, widget.memberFirestoreHint);
    if (urlChanged || idsChanged) {
      _resolveDisplayUrl();
    }
  }

  Future<String?> _storagePathToDisplayUrl(String rawPath) async {
    final p = StorageMediaService.normalizeFirestoreStoragePath(rawPath);
    if (p == null || p.isEmpty) return null;
    try {
      final u = await StorageMediaService.downloadUrlFromPathOrUrl(p);
      final clean = sanitizeImageUrl(u ?? '');
      if (clean.isNotEmpty && isValidImageUrl(clean)) return clean;
    } catch (_) {}
    return null;
  }

  bool _looksLikeMemberStoragePath(String raw) {
    final t = raw.trim().replaceAll('\\', '/');
    if (t.isEmpty) return false;
    if (t.toLowerCase().startsWith('gs://')) return true;
    if (t.contains('://')) return false;
    return firebaseStorageMediaUrlLooksLike(t) || t.contains('membros/');
  }

  bool _isRenderableMediaRef(String raw) {
    final s = sanitizeImageUrl(raw);
    if (s.isEmpty) return false;
    if (isValidImageUrl(s)) return true;
    return _looksLikeMemberStoragePath(s) || firebaseStorageMediaUrlLooksLike(s);
  }

  String? _peekInstantUrl() {
    final tid = widget.tenantId?.trim() ?? '';
    final mid = widget.memberId?.trim() ?? '';
    if (tid.isEmpty || mid.isEmpty) return null;
    final peek = FirebaseStorageService.peekMemberProfilePhotoDownloadUrl(
      tenantId: tid,
      memberId: mid,
      cpfDigits: widget.cpfDigits,
      authUid: widget.authUid,
      nomeCompleto: widget.nomeCompleto,
      memberFirestoreHint: widget.memberFirestoreHint,
      preferListThumbnail: widget.preferListThumbnail,
    );
    if (peek != null && peek.trim().isNotEmpty && _isRenderableMediaRef(peek)) {
      return peek.trim();
    }
    return null;
  }

  String? _effectiveDisplayUrl() {
    final resolved = (_displayUrl ?? '').trim();
    if (resolved.isNotEmpty && _isRenderableMediaRef(resolved)) return resolved;

    final peek = _peekInstantUrl();
    if (peek != null) return peek;

    final raw = (widget.imageUrl ?? '').trim();
    if (raw.isNotEmpty && _isRenderableMediaRef(raw)) return raw;

    final norm = sanitizeImageUrl(widget.imageUrl);
    if (isValidImageUrl(norm)) return norm;
    return null;
  }

  Future<void> _resolveDisplayUrl() async {
    final hint = widget.memberFirestoreHint;
    final primary = sanitizeImageUrl(widget.imageUrl);

    final fullRef = MemberProfilePhotoResolver.displayRef(hint, preferThumb: false);
    final listRef = MemberProfilePhotoResolver.displayRef(hint, preferThumb: true);

    String? pickRaw;
    String? variantAlt;
    if (widget.preferListThumbnail) {
      final list = (listRef ?? '').trim();
      final full = (fullRef ?? '').trim();
      pickRaw = list.isNotEmpty ? listRef : fullRef;
      if (list.isNotEmpty && full.isNotEmpty && list != full) {
        variantAlt = full;
      }
    } else {
      pickRaw = (fullRef ?? '').trim().isNotEmpty
          ? fullRef
          : ((primary.isNotEmpty) ? widget.imageUrl : null);
      final list = sanitizeImageUrl(listRef ?? '');
      if (isValidImageUrl(list) &&
          pickRaw != null &&
          sanitizeImageUrl(pickRaw) != list) {
        variantAlt = listRef;
      }
    }
    _variantFallbackUrl = variantAlt;

    if ((pickRaw ?? '').trim().isEmpty && isValidImageUrl(primary)) {
      pickRaw = widget.imageUrl;
    }

    final raw = (pickRaw ?? '').trim();
    if (raw.isEmpty && !isValidImageUrl(primary)) {
      if (mounted) {
        setState(() {
          _displayUrl = null;
          _variantFallbackUrl = null;
        });
      }
      return;
    }

    if (_looksLikeMemberStoragePath(raw)) {
      final peek = _peekInstantUrl();
      final instant = (peek != null && isValidImageUrl(sanitizeImageUrl(peek)))
          ? peek
          : raw;
      if (mounted) {
        setState(() {
          _displayUrl = instant;
          _resolving = false;
        });
      }
      // Renova URL em background (cache RAM/disco) — não bloqueia o 1.º frame.
      unawaited(() async {
        final fromPath = await _storagePathToDisplayUrl(raw);
        if (!mounted || fromPath == null) return;
        if (sanitizeImageUrl(fromPath) != sanitizeImageUrl(instant)) {
          setState(() => _displayUrl = fromPath);
        }
      }());
      return;
    }

    final norm = isValidImageUrl(sanitizeImageUrl(raw))
        ? sanitizeImageUrl(raw)
        : (isValidImageUrl(primary) ? primary : '');
    if (!isValidImageUrl(norm)) {
      if (mounted) {
        setState(() {
          _displayUrl = null;
          _variantFallbackUrl = null;
          _resolving = false;
        });
      }
      return;
    }
    final needsFresh = StorageMediaService.isFirebaseStorageMediaUrl(norm);
    // Mostrar já a URL conhecida; renovar token em background (lista abre mais rápido).
    if (mounted) {
      setState(() {
        _displayUrl = norm;
        _resolving = false;
      });
    }
    if (!needsFresh) return;
    unawaited(() async {
      String out = norm;
      try {
        out = sanitizeImageUrl(
            await StorageMediaService.freshPlayableMediaUrl(norm));
      } catch (_) {
        out = norm;
      }
      if (!mounted) return;
      if (isValidImageUrl(out) && sanitizeImageUrl(out) != sanitizeImageUrl(norm)) {
        setState(() => _displayUrl = out);
      }
    }());
    return;
  }

  Widget _buildLoadErrorFallback({
    required String currentUrl,
    required bool canStorage,
    required String tid,
    required String mid,
    required int mcW,
    required int mcH,
    required Widget err,
  }) {
    final alt = _variantFallbackUrl;
    if (alt != null &&
        sanitizeImageUrl(alt) != sanitizeImageUrl(currentUrl) &&
        (isValidImageUrl(alt) ||
            _looksLikeMemberStoragePath(alt) ||
            firebaseStorageMediaUrlLooksLike(alt))) {
      return ResilientNetworkImage(
        key: ValueKey<String>('smp_alt_${alt}_${tid}_$mid'),
        imageUrl: alt,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: mcW,
        memCacheHeight: mcH,
        skipFreshDisplayUrl: true,
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
                preferListThumbnail: widget.preferListThumbnail,
                width: widget.width,
                height: widget.height,
                memCacheW: mcW,
                memCacheH: mcH,
                fit: widget.fit,
                placeholder: widget.placeholder,
                errorChild: err,
              )
            : err,
      );
    }
    if (canStorage) {
      return _MemberPhotoStorageFallback(
        tenantId: tid,
        memberId: mid,
        cpfDigits: widget.cpfDigits,
        authUid: widget.authUid,
        nomeCompleto: widget.nomeCompleto,
        memberFirestoreHint: widget.memberFirestoreHint,
        sourceImageUrl: widget.imageUrl,
        imageCacheRevision: widget.imageCacheRevision,
        preferListThumbnail: widget.preferListThumbnail,
        width: widget.width,
        height: widget.height,
        memCacheW: mcW,
        memCacheH: mcH,
        fit: widget.fit,
        placeholder: widget.placeholder,
        errorChild: err,
      );
    }
    return err;
  }

  @override
  Widget build(BuildContext context) {
    final tid = widget.tenantId?.trim() ?? '';
    final mid = widget.memberId?.trim() ?? '';
    final canStorage = widget.enableStorageFallback && tid.isNotEmpty && mid.isNotEmpty;
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

    final rev = widget.imageCacheRevision ?? 0;

    if (_resolving && _displayUrl == null) {
      return core(widget.placeholder ?? err);
    }

    final effective = _effectiveDisplayUrl();
    if (effective == null || !_isRenderableMediaRef(effective)) {
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
          preferListThumbnail: widget.preferListThumbnail,
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

    final cachedBytes = MemberProfilePhotoBytesCache.get(effective);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      return core(
        Image.memory(
          cachedBytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
      );
    }

    final bustedUrl = rev > 0 && isValidImageUrl(effective)
        ? YahwehMediaCacheBust.apply(effective, rev)
        : effective;

    return core(
      ResilientNetworkImage(
        key: ValueKey<String>('smp_${bustedUrl}_${tid}_${mid}_$rev'),
        imageUrl: bustedUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: mcW,
        memCacheHeight: mcH,
        skipFreshDisplayUrl: true,
        storageCacheRevision: rev,
        placeholder: widget.placeholder ?? err,
        errorWidget: _buildLoadErrorFallback(
          currentUrl: bustedUrl,
          canStorage: canStorage,
          tid: tid,
          mid: mid,
          mcW: mcW,
          mcH: mcH,
          err: err,
        ),
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
  final bool preferListThumbnail;

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
    this.preferListThumbnail = false,
  });

  @override
  State<_MemberPhotoStorageFallback> createState() => _MemberPhotoStorageFallbackState();
}

class _MemberPhotoStorageFallbackState extends State<_MemberPhotoStorageFallback> {
  late Future<String?> _future;
  String? _instantUrl;

  @override
  void initState() {
    super.initState();
    _instantUrl = _peekCachedUrl();
    _future = _resolveFallbackUrl();
  }

  String? _peekCachedUrl() {
    final raw = (widget.sourceImageUrl ?? '').trim();
    if (raw.isNotEmpty) {
      final s = sanitizeImageUrl(raw);
      if (isValidImageUrl(s)) return s;
      if (firebaseStorageMediaUrlLooksLike(raw) || raw.contains('membros/')) {
        return raw;
      }
    }
    final hint = widget.memberFirestoreHint;
    if (hint != null && hint.isNotEmpty) {
      final fromDoc = MemberProfilePhotoResolver.displayRef(
        hint,
        preferThumb: widget.preferListThumbnail,
      );
      if (fromDoc != null && fromDoc.trim().isNotEmpty) {
        final s = sanitizeImageUrl(fromDoc);
        if (isValidImageUrl(s)) return s;
        if (firebaseStorageMediaUrlLooksLike(fromDoc) ||
            fromDoc.contains('membros/')) {
          return fromDoc.trim();
        }
      }
    }
    return FirebaseStorageService.peekMemberProfilePhotoDownloadUrl(
      tenantId: widget.tenantId,
      memberId: widget.memberId,
      cpfDigits: widget.cpfDigits,
      authUid: widget.authUid,
      nomeCompleto: widget.nomeCompleto,
      memberFirestoreHint: widget.memberFirestoreHint,
      preferListThumbnail: widget.preferListThumbnail,
    );
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
        oldWidget.preferListThumbnail != widget.preferListThumbnail ||
        !identical(
            oldWidget.memberFirestoreHint, widget.memberFirestoreHint);
    if (sourceChanged || idChanged) {
      _instantUrl = _peekCachedUrl();
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
          if (!kIsWeb &&
              isValidImageUrl(s) &&
              StorageMediaService.isFirebaseStorageMediaUrl(s)) {
            return s;
          }
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
      preferListThumbnail: widget.preferListThumbnail,
    ).then((url) async {
      if (url != null && url.isNotEmpty) return url;
      if (!widget.preferListThumbnail) return null;
      return FirebaseStorageService.getMemberProfilePhotoDownloadUrl(
        tenantId: widget.tenantId,
        memberId: widget.memberId,
        cpfDigits: widget.cpfDigits,
        authUid: widget.authUid,
        nomeCompleto: widget.nomeCompleto,
        memberFirestoreHint: widget.memberFirestoreHint,
        preferListThumbnail: false,
      );
    });
    }

    try {
      return await inner().timeout(const Duration(seconds: 8),
          onTimeout: () => _instantUrl);
    } catch (_) {
      return _instantUrl;
    }
  }

  Widget _photoFromUrl(String clean) {
    final rev = widget.imageCacheRevision ?? 0;
    final cached = MemberProfilePhotoBytesCache.get(clean);
    if (cached != null && cached.isNotEmpty) {
      return Image.memory(
        cached,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }
    return ResilientNetworkImage(
      key: ValueKey<String>('mfs_${clean}_$rev'),
      imageUrl: clean,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: widget.memCacheW,
      memCacheHeight: widget.memCacheH,
      skipFreshDisplayUrl: true,
      storageCacheRevision: rev,
      placeholder: widget.placeholder,
      errorWidget: widget.errorChild,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawInstant = (_instantUrl ?? '').trim();
    if (rawInstant.isNotEmpty) {
      final cached = MemberProfilePhotoBytesCache.get(rawInstant);
      if (cached != null && cached.isNotEmpty) {
        return Image.memory(
          cached,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        );
      }
      final instant = sanitizeImageUrl(rawInstant);
      if (instant.isNotEmpty &&
          (isValidImageUrl(instant) ||
              firebaseStorageMediaUrlLooksLike(rawInstant) ||
              rawInstant.contains('membros/'))) {
        return _photoFromUrl(rawInstant);
      }
    }

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
          return _photoFromUrl(clean);
        }
        return widget.errorChild;
      },
    );
  }
}
