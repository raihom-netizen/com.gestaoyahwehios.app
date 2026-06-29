import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Miniatura lateral para cultos/eventos fixos — painel, site e módulo eventos.
class PainelProgramacaoEventLeading extends StatelessWidget {
  const PainelProgramacaoEventLeading({
    super.key,
    required this.churchId,
    required this.data,
    this.size = 48,
    this.memCacheSize,
  });

  final String churchId;
  final Map<String, dynamic> data;
  final double size;
  final int? memCacheSize;

  Widget _placeholder() => ColoredBox(
        color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
        child: Icon(
          Icons.event_rounded,
          color: ThemeCleanPremium.primary,
          size: size * 0.46,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cover = resolveProgramacaoEventCover(
      churchId: churchId,
      data: data,
    );
    if (!cover.hasMedia) return _placeholder();

    final cache = memCacheSize ?? (size * 2).round();
    return StableStorageImage(
      storagePath:
          cover.photoStoragePath.isNotEmpty ? cover.photoStoragePath : null,
      imageUrl: cover.imageUrl.isNotEmpty ? cover.imageUrl : null,
      fallbackStoragePaths: cover.fallbackStoragePaths,
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: cache,
      memCacheHeight: cache,
      placeholder: _placeholder(),
      errorWidget: _placeholder(),
    );
  }
}
