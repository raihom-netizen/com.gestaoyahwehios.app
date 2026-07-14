import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/constants/utilitarios_module_icons.dart';
import 'package:gestao_yahweh/services/utilitarios_daily_quota_service.dart';
import 'package:gestao_yahweh/services/utilitarios_local_service.dart';
import 'package:gestao_yahweh/services/utilitarios_video_compress_service.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';
import 'package:gestao_yahweh/utils/home_shell_layout.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_pdf_tools_flow.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_photo_text_extract_flow.dart';

/// Módulo Utilitários — conversões, compressores e editores locais (sem servidor).
class UtilitariosScreen extends StatefulWidget {
  final String uid;
  final bool isAdmin;
  final void Function(int index)? onNavigateTo;
  final ScrollController? shellScrollController;

  const UtilitariosScreen({
    super.key,
    required this.uid,
    this.isAdmin = false,
    this.onNavigateTo,
    this.shellScrollController,
  });

  @override
  State<UtilitariosScreen> createState() => _UtilitariosScreenState();
}

class _UtilitariosScreenState extends State<UtilitariosScreen> {
  bool _busy = false;
  String? _busyLabel;
  bool _cancelBusy = false;
  int _heavyUsed = 0;
  int _lightUsed = 0;
  DateTime? _lightUnlockAt;
  DateTime? _heavyUnlockAt;

  String get _quotaUid => widget.uid.trim();
  bool get _isAdmin => widget.isAdmin;
  bool get _lightLocked =>
      !_isAdmin &&
      _lightUsed >= UtilitariosDailyQuotaService.kLightLimitPerDay;
  bool get _heavyLocked =>
      !_isAdmin &&
      _heavyUsed >= UtilitariosDailyQuotaService.kHeavyLimitPerDay;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshQuota());
  }

  Future<void> _refreshQuota() async {
    final heavy = await UtilitariosDailyQuotaService.heavyStatus(
      _quotaUid,
      isAdmin: _isAdmin,
    );
    final light = await UtilitariosDailyQuotaService.lightStatus(
      _quotaUid,
      isAdmin: _isAdmin,
    );
    if (!mounted) return;
    setState(() {
      _heavyUsed = heavy.used;
      _lightUsed = light.used;
      _heavyUnlockAt = heavy.unlockAt;
      _lightUnlockAt = light.unlockAt;
    });
  }

  Future<void> _runBusy(String label, Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = label;
      _cancelBusy = false;
    });
    try {
      await job();
      if (_cancelBusy) return;
      await _refreshQuota();
    } catch (e) {
      if (!mounted || _cancelBusy) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(utilitariosFormatPickError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  /// Garante cota antes de abrir picker (evita escolher arquivo e falhar depois).
  Future<bool> _ensureLightQuota() async {
    final err = await UtilitariosDailyQuotaService.checkLight(
      _quotaUid,
      isAdmin: _isAdmin,
    );
    if (err == null) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
    }
    return false;
  }

  Future<bool> _ensureHeavyQuota() async {
    final err = await UtilitariosDailyQuotaService.checkHeavy(
      _quotaUid,
      isAdmin: _isAdmin,
    );
    if (err == null) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
    }
    return false;
  }

  static bool _isVideoFileName(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.mp4') ||
        n.endsWith('.mov') ||
        n.endsWith('.m4v') ||
        n.endsWith('.avi') ||
        n.endsWith('.mkv') ||
        n.endsWith('.webm');
  }

  Future<void> _afterResult({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String okMessage,
    bool preferShareFirst = false,
    String shareButtonLabel = 'Compartilhar (WhatsApp e outros)',
  }) async {
    if (!mounted || _cancelBusy) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 22),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pronto',
                style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                okMessage,
                style: ModernModuleUI.moduleSubtitleStyle(ctx),
              ),
              const SizedBox(height: 16),
              if (preferShareFirst) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'share'),
                  icon: const Icon(Icons.share_rounded),
                  label: Text(shareButtonLabel),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Baixar local'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'share'),
                  icon: const Icon(Icons.share_rounded),
                  label: Text(shareButtonLabel),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Baixar local'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    final ok = await utilitariosSaveOrShareBytes(
      context: context,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      preferShare: action == 'share',
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'share'
                ? 'Arquivo pronto — escolha WhatsApp, e-mail ou outro app.'
                : 'Download iniciado — arquivo no aparelho.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (action == 'share') {
      // Web: se share falhar, ofereceere baixar (arquivo já está pronto).
      final retry = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Container(
            decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 22),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Compartilhar neste navegador',
                  style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  'O Chrome às vezes bloqueia WhatsApp com Excel/PowerPoint. '
                  'Baixe o arquivo e abra no WhatsApp, ou tente de novo.',
                  style: ModernModuleUI.moduleSubtitleStyle(ctx),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Baixar e abrir no WhatsApp'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'share'),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Tentar compartilhar de novo'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          );
        },
      );
      if (!mounted || retry == null) return;
      final ok2 = await utilitariosSaveOrShareBytes(
        context: context,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        preferShare: retry == 'share',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok2
                ? (retry == 'share'
                    ? 'Arquivo pronto — escolha WhatsApp ou outro app.'
                    : 'Download iniciado — abra o arquivo no WhatsApp.')
                : 'Não foi possível concluir. Tente Baixar local.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pdfToWord() async {
    if (!await _ensureLightQuota()) return;
    await _runBusy('Convertendo PDF → Word…', () async {
      final picked = await utilitariosPickSingleFileBytes(
        allowedExtensions: const ['pdf'],
      );
      if (picked == null) return;
      final out = await UtilitariosLocalService.pdfToDocx(picked.bytes);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      final base =
          picked.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      await _afterResult(
        bytes: out,
        fileName: '${base.isEmpty ? 'documento' : base}.docx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        okMessage:
            'Word gerado com parágrafos, títulos e tabelas do PDF original.',
      );
    });
  }

  Future<void> _pdfToJpeg() async {
    if (!await _ensureLightQuota()) return;
    await _runBusy('Convertendo PDF → JPEG…', () async {
      final picked = await utilitariosPickSingleFileBytes(
        allowedExtensions: const ['pdf'],
      );
      if (picked == null) return;
      final pages = await UtilitariosLocalService.pdfToJpegs(picked.bytes);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      final base =
          picked.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final stem = base.isEmpty ? 'pagina' : base;
      if (pages.length == 1) {
        await _afterResult(
          bytes: pages.first,
          fileName: '$stem.jpg',
          mimeType: 'image/jpeg',
          okMessage: 'JPEG gerado no seu aparelho.',
        );
        return;
      }
      final zipBytes = await UtilitariosLocalService.zipImages(
        pages,
        stem,
        extension: 'jpg',
      );
      await _afterResult(
        bytes: zipBytes,
        fileName: '${stem}_paginas.zip',
        mimeType: 'application/zip',
        okMessage: '${pages.length} páginas em JPEG (ZIP) geradas localmente.',
      );
    });
  }

  Future<void> _pdfToPng() async {
    if (!await _ensureLightQuota()) return;
    await _runBusy('Convertendo PDF → PNG…', () async {
      final picked = await utilitariosPickSingleFileBytes(
        allowedExtensions: const ['pdf'],
      );
      if (picked == null) return;
      final pages = await UtilitariosLocalService.pdfToPngs(picked.bytes);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      final base =
          picked.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final stem = base.isEmpty ? 'pagina' : base;
      if (pages.length == 1) {
        await _afterResult(
          bytes: pages.first,
          fileName: '$stem.png',
          mimeType: 'image/png',
          okMessage: 'PNG gerado no seu aparelho.',
        );
        return;
      }
      final zipBytes = await UtilitariosLocalService.zipImages(
        pages,
        stem,
        extension: 'png',
      );
      await _afterResult(
        bytes: zipBytes,
        fileName: '${stem}_paginas.zip',
        mimeType: 'application/zip',
        okMessage: '${pages.length} páginas em PNG (ZIP) geradas localmente.',
      );
    });
  }

  Future<void> _imagesToPdf({required bool pngOnly}) async {
    if (!await _ensureLightQuota()) return;
    await _runBusy(pngOnly ? 'PNG → PDF…' : 'JPEG/PNG → PDF…', () async {
      final picked = await utilitariosPickMultipleFileBytes(
        allowedExtensions:
            pngOnly ? const ['png'] : const ['jpg', 'jpeg', 'png', 'webp'],
        preferBytes: true,
      );
      final images = <Uint8List>[];
      for (final f in picked) {
        UtilitariosLocalService.ensureWithinSize(f.bytes, label: 'Imagem');
        images.add(f.bytes);
        if (images.length >= UtilitariosLocalService.kMaxImagesPerPdf) break;
      }
      if (images.isEmpty) {
        throw StateError('Nenhuma imagem válida selecionada.');
      }
      final out = await UtilitariosLocalService.imagesToPdf(images);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      await _afterResult(
        bytes: out,
        fileName: pngOnly
            ? 'png_controle_total.pdf'
            : 'imagens_controle_total.pdf',
        mimeType: 'application/pdf',
        okMessage:
            'PDF criado localmente com ${images.length} imagem(ns)${pngOnly ? ' PNG' : ''}.',
        preferShareFirst: true,
        shareButtonLabel: 'Compartilhar PDF (WhatsApp)',
      );
    });
  }

  Future<void> _jpegToPdf() => _imagesToPdf(pngOnly: false);

  Future<void> _pngToPdf() => _imagesToPdf(pngOnly: true);

  Future<void> _wordToPdf() async {
    if (!await _ensureLightQuota()) return;
    await _runBusy('Convertendo Word → PDF…', () async {
      final picked = await utilitariosPickSingleFileBytes(
        allowedExtensions: const ['docx', 'txt', 'rtf'],
      );
      if (picked == null) return;
      final out =
          await UtilitariosLocalService.documentToPdf(picked.bytes, picked.name);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      final base = picked.name
          .replaceAll(RegExp(r'\.(docx|txt|rtf)$', caseSensitive: false), '');
      await _afterResult(
        bytes: out,
        fileName: '${base.isEmpty ? 'documento' : base}.pdf',
        mimeType: 'application/pdf',
        okMessage: 'PDF gerado a partir do texto do documento (local).',
      );
    });
  }

  Future<void> _pdfToExcel() async {
    if (!await _ensureLightQuota()) return;
    await _runBusy('Convertendo PDF → Excel…', () async {
      final picked = await utilitariosPickSingleFileBytes(
        allowedExtensions: const ['pdf'],
      );
      if (picked == null) return;
      final out = await UtilitariosLocalService.pdfToXlsx(picked.bytes);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      final base =
          picked.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      await _afterResult(
        bytes: out,
        fileName: '${base.isEmpty ? 'planilha' : base}.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        okMessage:
            'Excel gerado com linhas, colunas e tabelas alinhadas ao documento.',
        preferShareFirst: true,
        shareButtonLabel: 'Compartilhar (WhatsApp e outros)',
      );
    });
  }

  Future<void> _excelToPdf() async {
    if (!await _ensureLightQuota()) return;
    await _runBusy('Convertendo Excel → PDF…', () async {
      final picked = await utilitariosPickSingleFileBytes(
        allowedExtensions: const ['xlsx', 'csv'],
      );
      if (picked == null) return;
      final out =
          await UtilitariosLocalService.excelToPdf(picked.bytes, picked.name);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      final base = picked.name
          .replaceAll(RegExp(r'\.(xlsx|csv)$', caseSensitive: false), '');
      await _afterResult(
        bytes: out,
        fileName: '${base.isEmpty ? 'planilha' : base}.pdf',
        mimeType: 'application/pdf',
        okMessage: 'PDF gerado a partir da planilha (local).',
        preferShareFirst: true,
        shareButtonLabel: 'Compartilhar PDF (WhatsApp)',
      );
    });
  }

  Future<void> _pdfToPowerPoint() async {
    if (!await _ensureLightQuota()) return;
    await _runBusy('Convertendo PDF → PowerPoint…', () async {
      final picked = await utilitariosPickSingleFileBytes(
        allowedExtensions: const ['pdf'],
      );
      if (picked == null) return;
      final out = await UtilitariosLocalService.pdfToPptx(picked.bytes);
      await UtilitariosDailyQuotaService.consumeLight(_quotaUid, isAdmin: _isAdmin);
      final base =
          picked.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      await _afterResult(
        bytes: out,
        fileName: '${base.isEmpty ? 'apresentacao' : base}.pptx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        okMessage:
            'PowerPoint gerado localmente (1 slide por página do PDF).',
        preferShareFirst: true,
        shareButtonLabel: 'Compartilhar (WhatsApp e outros)',
      );
    });
  }

  static const _videoPickerExtensions = [
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    'webm',
    '3gp',
  ];

  Future<PlatformFile?> _pickVideoFile() async {
    final files = await utilitariosPickPlatformFiles(
      allowedExtensions: _videoPickerExtensions,
      forceStream: true,
    );
    if (files.isEmpty) return null;
    final f = files.first;
    try {
      await utilitariosResolvePlatformFilePath(f);
    } catch (e) {
      throw StateError(utilitariosFormatPickError(e));
    }
    return f;
  }

  Future<UtilitariosVideoConvertOptions?> _pickVideoConvertOptions() async {
    var resolution = UtilitariosVideoExportResolution.fullHd;
    var compressAlso = false;
    var compressLevel = UtilitariosCompressLevel.media;

    return showModalBottomSheet<UtilitariosVideoConvertOptions>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final maxH = MediaQuery.sizeOf(ctx).height * 0.88;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                constraints: BoxConstraints(maxHeight: maxH),
                decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 22),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Text(
                    'Vídeo → MP4',
                    style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Escolha a resolução. Opcional: comprimir para arquivo menor.',
                    style: ModernModuleUI.moduleSubtitleStyle(ctx),
                  ),
                  const SizedBox(height: 14),
                  for (final res in UtilitariosVideoExportResolution.values) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setModal(() => resolution = res),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: resolution == res
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFF64748B).withValues(alpha: 0.25),
                              width: resolution == res ? 2 : 1,
                            ),
                            color: resolution == res
                                ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
                                : Theme.of(ctx)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                resolution == res
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: resolution == res
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      res.label,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: Theme.of(ctx).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      res.subtitle,
                                      style: ModernModuleUI.moduleSubtitleStyle(
                                        ctx,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Comprimir também',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Reduz tamanho após converter',
                      style: ModernModuleUI.moduleSubtitleStyle(ctx, fontSize: 12),
                    ),
                    value: compressAlso,
                    onChanged: (v) => setModal(() => compressAlso = v),
                  ),
                  if (compressAlso) ...[
                    const SizedBox(height: 4),
                    for (final level in UtilitariosCompressLevel.values) ...[
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setModal(() => compressLevel = level),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  compressLevel == level
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  size: 20,
                                  color: compressLevel == level
                                      ? const Color(0xFF7C3AED)
                                      : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${level.label} · ${level.reductionBadge}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: Theme.of(ctx).colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        level.subtitle,
                                        style: ModernModuleUI.moduleSubtitleStyle(
                                          ctx,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      ctx,
                      UtilitariosVideoConvertOptions(
                        resolution: resolution,
                        compressAlso: compressAlso,
                        compressLevel: compressLevel,
                      ),
                    ),
                    icon: const Icon(Icons.movie_creation_rounded),
                    label: Text(
                      compressAlso
                          ? 'Converter · ${resolution.label} · ${compressLevel.label}'
                          : 'Converter · ${resolution.label}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<UtilitariosAudioExtractFormat?> _pickAudioExtractFormat() async {
    var selected = UtilitariosAudioExtractFormat.m4a;
    return showModalBottomSheet<UtilitariosAudioExtractFormat>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Container(
              decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 22),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Extrair áudio',
                    style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Somente o áudio do vídeo — 100% local no aparelho.',
                    style: ModernModuleUI.moduleSubtitleStyle(ctx),
                  ),
                  const SizedBox(height: 14),
                  for (final fmt in UtilitariosAudioExtractFormat.values) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setModal(() => selected = fmt),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected == fmt
                                  ? const Color(0xFFDB2777)
                                  : const Color(0xFF64748B).withValues(alpha: 0.25),
                              width: selected == fmt ? 2 : 1,
                            ),
                            color: selected == fmt
                                ? const Color(0xFFDB2777).withValues(alpha: 0.10)
                                : Theme.of(ctx)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected == fmt
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: selected == fmt
                                    ? const Color(0xFFDB2777)
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fmt.label,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: Theme.of(ctx).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      fmt.subtitle,
                                      style: ModernModuleUI.moduleSubtitleStyle(
                                        ctx,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, selected),
                    icon: const Icon(Icons.audio_file_rounded),
                    label: Text('Extrair ${selected.label}'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _videoToMp4() async {
    if (!await _ensureHeavyQuota()) return;
    if (!utilitariosVideoToolsSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversão de vídeo disponível no app Android e iPhone.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final options = await _pickVideoConvertOptions();
    if (options == null || !mounted) return;

    await _runBusy('Convertendo para MP4…', () async {
      final f = await _pickVideoFile();
      if (f == null) return;
      final inputPath = await utilitariosResolvePlatformFilePath(f);
      final before = await utilitariosFileSizeAtPath(inputPath);
      final converted = await utilitariosConvertVideoToMp4(
        inputPath: inputPath,
        options: options,
      );
      await UtilitariosDailyQuotaService.consumeHeavy(
        _quotaUid,
        isAdmin: _isAdmin,
      );
      final base = f.name.replaceAll(
        RegExp(r'\.(mp4|mov|m4v|avi|mkv|webm|3gp)$', caseSensitive: false),
        '',
      );
      final suffix = options.compressAlso
          ? '_${options.resolution == UtilitariosVideoExportResolution.fourK ? '4k' : '1080p'}_${options.compressLevel.fileSuffix}'
          : '_${options.resolution == UtilitariosVideoExportResolution.fourK ? '4k' : '1080p'}';
      final fileName = '${base.isEmpty ? 'video' : base}$suffix.mp4';
      if (!mounted) return;
      await _showCompressResultPreview(
        bytes: converted.bytes,
        fileName: fileName,
        mimeType: 'video/mp4',
        level: options.compressAlso
            ? options.compressLevel
            : UtilitariosCompressLevel.baixa,
        originalBytes: before,
        compressedBytes: converted.bytes.lengthInBytes,
        title: 'Conversão concluída',
        subtitle:
            '${options.resolution.label}${options.compressAlso ? ' · ${options.compressLevel.label}' : ''} · MP4',
      );
    });
  }

  Future<void> _extractVideoAudio() async {
    if (!await _ensureHeavyQuota()) return;
    if (!utilitariosVideoToolsSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Extração de áudio disponível no app Android e iPhone.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final format = await _pickAudioExtractFormat();
    if (format == null || !mounted) return;

    await _runBusy('Extraindo áudio…', () async {
      final f = await _pickVideoFile();
      if (f == null) return;
      final inputPath = await utilitariosResolvePlatformFilePath(f);
      final before = await utilitariosFileSizeAtPath(inputPath);
      final extracted = await utilitariosExtractAudioFromVideo(
        inputPath: inputPath,
        format: format,
      );
      await UtilitariosDailyQuotaService.consumeHeavy(
        _quotaUid,
        isAdmin: _isAdmin,
      );
      final outExt = extracted.outputPath.toLowerCase().endsWith('.mp3')
          ? 'mp3'
          : format.extension;
      final outMime = outExt == 'mp3' ? 'audio/mpeg' : 'audio/mp4';
      final base = f.name.replaceAll(
        RegExp(r'\.(mp4|mov|m4v|avi|mkv|webm|3gp)$', caseSensitive: false),
        '',
      );
      final fileName = '${base.isEmpty ? 'audio' : base}.$outExt';
      if (!mounted) return;
      await _afterResult(
        bytes: extracted.bytes,
        fileName: fileName,
        mimeType: outMime,
        okMessage: extracted.note ??
            'Áudio extraído localmente (${format.label}). Tamanho original do vídeo: ${_humanSize(before)}.',
        preferShareFirst: true,
        shareButtonLabel: 'Compartilhar áudio',
      );
    });
  }

  Color _compressLevelAccent(UtilitariosCompressLevel level) {
    return switch (level) {
      UtilitariosCompressLevel.baixa => const Color(0xFF059669),
      UtilitariosCompressLevel.media => const Color(0xFF4F46E5),
      UtilitariosCompressLevel.alta => const Color(0xFF7C3AED),
    };
  }

  IconData _compressLevelIcon(UtilitariosCompressLevel level) {
    return switch (level) {
      UtilitariosCompressLevel.baixa => Icons.tune_rounded,
      UtilitariosCompressLevel.media => Icons.auto_fix_high_rounded,
      UtilitariosCompressLevel.alta => Icons.bolt_rounded,
    };
  }

  Future<UtilitariosCompressLevel?> _pickCompressLevel() async {
    var selected = UtilitariosCompressLevel.media;
    return showModalBottomSheet<UtilitariosCompressLevel>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final maxH = MediaQuery.sizeOf(ctx).height * 0.88;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                constraints: BoxConstraints(maxHeight: maxH),
                decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 22),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.compress_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Compress Pro',
                              style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 18),
                            ),
                            Text(
                              '100% no aparelho · imagem, PDF e vídeo',
                              style: ModernModuleUI.moduleSubtitleStyle(ctx, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final level in UtilitariosCompressLevel.values) ...[
                    Builder(
                      builder: (ctx) {
                        final accent = _compressLevelAccent(level);
                        final isSelected = selected == level;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setModal(() => selected = level),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? accent
                                      : const Color(0xFF64748B).withValues(alpha: 0.25),
                                  width: isSelected ? 2 : 1,
                                ),
                                color: isSelected
                                    ? accent.withValues(alpha: 0.10)
                                    : Theme.of(ctx)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.35),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _compressLevelIcon(level),
                                      color: accent,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              level.label,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15,
                                                color: Theme.of(ctx).colorScheme.onSurface,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: accent.withValues(alpha: 0.18),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                level.reductionBadge,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w900,
                                                  color: accent,
                                                ),
                                              ),
                                            ),
                                            if (level == UtilitariosCompressLevel.media)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF4F46E5)
                                                      .withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'Padrão',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF4F46E5),
                                                  ),
                                                ),
                                              ),
                                            if (level == UtilitariosCompressLevel.alta)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF7C3AED)
                                                      .withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'Máxima redução',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF7C3AED),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          level.subtitle,
                                          style: ModernModuleUI.moduleSubtitleStyle(
                                            ctx,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          level.techSummary,
                                          style: ModernModuleUI.moduleSubtitleStyle(
                                            ctx,
                                            fontSize: 11,
                                          ).copyWith(
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: isSelected ? accent : const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, selected),
                    icon: const Icon(Icons.compress_rounded),
                    label: Text(
                      'Comprimir · ${selected.reductionBadge} (${selected.label})',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: _compressLevelAccent(selected),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _compress() async {
    if (!await _ensureHeavyQuota()) return;
    final level = await _pickCompressLevel();
    if (level == null || !mounted) return;

    await _runBusy('Comprimindo (${level.label})…', () async {
      final files = await utilitariosPickPlatformFiles(
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'pdf',
          'mp4',
          'mov',
          'm4v',
          'avi',
          'mkv',
          'webm',
        ],
        forceStream: true,
      );
      if (files.isEmpty) return;
      final f = files.first;
      final name = f.name.toLowerCase();
      late final Uint8List out;
      late final String fileName;
      late final String mimeType;
      late final int before;

      if (_isVideoFileName(name)) {
        if (!utilitariosVideoCompressSupported) {
          throw StateError(
            'Compressão de vídeo disponível no app Android e iPhone.',
          );
        }
        final inputPath = await utilitariosResolvePlatformFilePath(f);
        before = await utilitariosFileSizeAtPath(inputPath);
        final compressed = await utilitariosCompressVideoFile(
          inputPath: inputPath,
          level: level,
        );
        out = compressed.bytes;
        final base = f.name.replaceAll(
          RegExp(r'\.(mp4|mov|m4v|avi|mkv|webm)$', caseSensitive: false),
          '',
        );
        fileName =
            '${base.isEmpty ? 'video' : base}_compacto_${level.fileSuffix}.mp4';
        mimeType = 'video/mp4';
      } else {
        final bytes = await utilitariosReadPlatformFileBytes(f);
        before = bytes.lengthInBytes;
        if (name.endsWith('.pdf')) {
          out = await UtilitariosLocalService.compressPdf(
            bytes,
            level: level,
          );
          final base =
              f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
          fileName =
              '${base.isEmpty ? 'documento' : base}_compacto_${level.fileSuffix}.pdf';
          mimeType = 'application/pdf';
        } else {
          out = await UtilitariosLocalService.compressImage(
            bytes,
            level: level,
          );
          final base = f.name.replaceAll(
              RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false), '');
          fileName =
              '${base.isEmpty ? 'imagem' : base}_compacta_${level.fileSuffix}.jpg';
          mimeType = 'image/jpeg';
        }
      }
      await UtilitariosDailyQuotaService.consumeHeavy(
        _quotaUid,
        isAdmin: _isAdmin,
      );
      final after = out.lengthInBytes;
      if (!mounted) return;
      await _showCompressResultPreview(
        bytes: out,
        fileName: fileName,
        mimeType: mimeType,
        level: level,
        originalBytes: before,
        compressedBytes: after,
      );
    });
  }

  /// Preview moderno pós-compressão: tamanhos + % + Compartilhar / Baixar / Cancelar.
  Future<void> _showCompressResultPreview({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required UtilitariosCompressLevel level,
    required int originalBytes,
    required int compressedBytes,
    String title = 'Compressão concluída',
    String? subtitle,
  }) async {
    if (!mounted || _cancelBusy) return;
    final saved = (originalBytes - compressedBytes).clamp(0, originalBytes);
    final pct = originalBytes <= 0
        ? 0.0
        : ((saved / originalBytes) * 100).clamp(0.0, 100.0);
    final grew = compressedBytes > originalBytes;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final dark = ModernModuleUI.isDark(ctx);
        return Container(
          decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 24),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 19),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle ?? '${level.reductionBadge} · ${level.label} · ${level.techSummary}',
                style: ModernModuleUI.moduleSubtitleStyle(ctx),
              ),
              const SizedBox(height: 16),
              // Card colorido com tamanhos + percentual.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF0F766E)]
                        : const [Color(0xFFEEF2FF), Color(0xFFE0E7FF), Color(0xFFCCFBF1)],
                  ),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF67E8F9).withValues(alpha: 0.35)
                        : const Color(0xFF6366F1).withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _CompressSizeChip(
                            label: 'Original',
                            value: _humanSize(originalBytes),
                            icon: Icons.insert_drive_file_outlined,
                            color: dark
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFFD97706),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: dark
                                ? Colors.white70
                                : const Color(0xFF6366F1),
                          ),
                        ),
                        Expanded(
                          child: _CompressSizeChip(
                            label: 'Comprimido',
                            value: _humanSize(compressedBytes),
                            icon: Icons.compress_rounded,
                            color: dark
                                ? const Color(0xFF34D399)
                                : const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.black.withValues(alpha: 0.28)
                            : Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            grew
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            color: grew
                                ? const Color(0xFFF87171)
                                : (dark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              grew
                                  ? 'Arquivo ficou ${pct.toStringAsFixed(0)}% maior'
                                  : 'Redução de ${pct.toStringAsFixed(0)}%  ·  ${_humanSize(saved)} a menos',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: dark
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: grew ? 1 : (1 - (pct / 100)).clamp(0.08, 1.0),
                        minHeight: 8,
                        backgroundColor: dark
                            ? Colors.white12
                            : const Color(0xFFCBD5E1),
                        color: grew
                            ? const Color(0xFFF87171)
                            : (dark
                                ? const Color(0xFF22D3EE)
                                : const Color(0xFF4F46E5)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'share'),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Compartilhar (WhatsApp e outros)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: const Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'save'),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Baixar local'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null || action == 'cancel') return;
    final ok = await utilitariosSaveOrShareBytes(
      context: context,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      preferShare: action == 'share',
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'share'
                ? 'Arquivo pronto — escolha WhatsApp, e-mail ou outro app.'
                : 'Download iniciado — arquivo no aparelho.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (action == 'share') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível abrir o compartilhamento. Use Baixar local.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _humanSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<UtilitariosArchiveFormat?> _pickArchiveFormat() async {
    var selected = UtilitariosArchiveFormat.zip;
    return showModalBottomSheet<UtilitariosArchiveFormat>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Container(
              decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 22),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Formato do arquivo',
                    style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Um ou vários arquivos · 100% no aparelho',
                    style: ModernModuleUI.moduleSubtitleStyle(ctx),
                  ),
                  const SizedBox(height: 14),
                  for (final f in UtilitariosArchiveFormat.values) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setModal(() => selected = f),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected == f
                                  ? const Color(0xFF0EA5E9)
                                  : const Color(0xFF64748B).withValues(alpha: 0.25),
                              width: selected == f ? 2 : 1,
                            ),
                            color: selected == f
                                ? const Color(0xFF0EA5E9).withValues(alpha: 0.10)
                                : Theme.of(ctx)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                f == UtilitariosArchiveFormat.rar
                                    ? Icons.archive_rounded
                                    : Icons.folder_zip_rounded,
                                color: const Color(0xFF0EA5E9),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.label,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: Theme.of(ctx).colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      f.subtitle,
                                      style: ModernModuleUI.moduleSubtitleStyle(
                                        ctx,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                selected == f
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: selected == f
                                    ? const Color(0xFF0EA5E9)
                                    : const Color(0xFF64748B),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, selected),
                    icon: const Icon(Icons.folder_zip_rounded),
                    label: Text('Continuar · ${selected.label}'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _compactarArquivos() async {
    if (!await _ensureLightQuota()) return;
    final format = await _pickArchiveFormat();
    if (format == null || !mounted) return;

    await _runBusy('Compactando (${format.label})…', () async {
      final picked = await utilitariosPickMultipleFileBytes(
        allowedExtensions: const [],
        type: FileType.any,
      );
      final entries = <({String name, Uint8List bytes})>[];
      for (final f in picked) {
        entries.add((name: f.name, bytes: f.bytes));
      }
      final out = await UtilitariosLocalService.archivePlatformFiles(
        entries,
        format: format,
      );
      await UtilitariosDailyQuotaService.consumeLight(
        _quotaUid,
        isAdmin: _isAdmin,
      );
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ext = format.fileExtension;
      final fileName = 'arquivos_${format.name}_$stamp.$ext';
      if (!mounted) return;
      await _afterResult(
        bytes: out,
        fileName: fileName,
        mimeType: format.mimeType,
        okMessage:
            '${entries.length} arquivo(s) compactados em ${format.label} — local.',
        preferShareFirst: true,
        shareButtonLabel: 'Compartilhar arquivo',
      );
    });
  }

  Future<void> _openPhotoTextExtract() async {
    if (!await _ensureLightQuota()) return;
    if (!mounted) return;
    await openUtilitariosPhotoTextExtractFlow(
      context,
      quotaUid: _quotaUid,
      isAdmin: _isAdmin,
    );
    if (!mounted) return;
    await _refreshQuota();
  }

  Future<void> _openPdfTool(UtilitariosPdfToolMode mode) async {
    if (!await _ensureLightQuota()) return;
    if (!mounted) return;
    final result = await openUtilitariosPdfToolFlow(context, mode);
    if (result == null || !mounted) return;
    await UtilitariosDailyQuotaService.consumeLight(
      _quotaUid,
      isAdmin: _isAdmin,
    );
    await _afterResult(
      bytes: result.bytes,
      fileName: result.fileName,
      mimeType: result.mimeType,
      okMessage: result.message,
      preferShareFirst: true,
      shareButtonLabel: 'Compartilhar',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scroll = widget.shellScrollController;
    final embeddedInShell = isHomeShellEmbeddedModule(
      shellScrollController: widget.shellScrollController,
      onNavigateTo: widget.onNavigateTo,
    );
    final lightOk = !_busy && !_lightLocked;
    final heavyOk = !_busy && !_heavyLocked;
    return ModernModuleUI.bodyWithGradient(
      context: context,
      child: Stack(
        children: [
          ListView(
            controller: scroll,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              homeShellScrollBottomPadding(
                context,
                embeddedInHomeShell: embeddedInShell,
                tail: 20,
              ),
            ),
            children: [
              _SecurityHeroCard(),
              const SizedBox(height: 8),
              _QuotaStatusCard(
                isAdmin: _isAdmin,
                lightUsed: _lightUsed,
                lightLimit: UtilitariosDailyQuotaService.kLightLimitPerDay,
                heavyUsed: _heavyUsed,
                heavyLimit: UtilitariosDailyQuotaService.kHeavyLimitPerDay,
                lightUnlockAt: _lightUnlockAt,
                heavyUnlockAt: _heavyUnlockAt,
              ),
              const SizedBox(height: 12),
              ModernModuleUI.sectionTitle(
                context,
                'CONVERSORES',
                accent: const Color(0xFF6366F1),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  final cards = [
                    _ToolTile(
                      icon: UtilitariosModuleIcons.pdfWord,
                      gradient: const [Color(0xFF2563EB), Color(0xFF7C3AED)],
                      title: 'PDF → Word',
                      subtitle: 'DOCX com formatação e tabelas',
                      onTap: lightOk ? _pdfToWord : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.pdfJpeg,
                      gradient: const [Color(0xFFEA580C), Color(0xFFF59E0B)],
                      title: 'PDF → JPEG',
                      subtitle: 'Páginas em imagem',
                      onTap: lightOk ? _pdfToJpeg : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.pdfPng,
                      gradient: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
                      title: 'PDF → PNG',
                      subtitle: 'Páginas em PNG',
                      onTap: lightOk ? _pdfToPng : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.jpegPdf,
                      gradient: const [Color(0xFFDC2626), Color(0xFFEF4444)],
                      title: 'JPEG → PDF',
                      subtitle: 'Uma ou várias fotos',
                      onTap: lightOk ? _jpegToPdf : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.pngPdf,
                      gradient: const [Color(0xFFDB2777), Color(0xFFF472B6)],
                      title: 'PNG → PDF',
                      subtitle: 'Uma ou várias PNGs',
                      onTap: lightOk ? _pngToPdf : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.wordPdf,
                      gradient: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
                      title: 'Word → PDF',
                      subtitle: 'DOCX / TXT / RTF',
                      onTap: lightOk ? _wordToPdf : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.pdfExcel,
                      gradient: const [Color(0xFF15803D), Color(0xFF22C55E)],
                      title: 'PDF → Excel',
                      subtitle: 'Planilha com linhas e tabelas',
                      onTap: lightOk ? _pdfToExcel : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.excelPdf,
                      gradient: const [Color(0xFF166534), Color(0xFF4ADE80)],
                      title: 'Excel → PDF',
                      subtitle: 'XLSX / CSV em tabela',
                      onTap: lightOk ? _excelToPdf : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.pdfPpt,
                      gradient: const [Color(0xFFC2410C), Color(0xFFF97316)],
                      title: 'PDF → PowerPoint',
                      subtitle: '1 slide por página',
                      onTap: lightOk ? _pdfToPowerPoint : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.compress,
                      gradient: const [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                      title: 'Compressor',
                      subtitle: 'Ultra Smart · Imagem · PDF · MP4',
                      onTap: heavyOk ? _compress : null,
                    ),
                  ];
                  if (narrow) {
                    return Column(
                      children: [
                        for (final w in cards) ...[
                          w,
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in cards)
                        SizedBox(
                          width: (c.maxWidth - 10) / 2,
                          child: w,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              ModernModuleUI.sectionTitle(
                context,
                'VÍDEO',
                accent: const Color(0xFF7C3AED),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  final videoTools = [
                    _ToolTile(
                      icon: UtilitariosModuleIcons.videoMp4,
                      gradient: const [Color(0xFF7C3AED), Color(0xFF2563EB)],
                      title: 'Vídeo → MP4',
                      subtitle: 'Full HD · 4K · comprimir opcional',
                      onTap: heavyOk ? _videoToMp4 : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.audioExtract,
                      gradient: const [Color(0xFFDB2777), Color(0xFFF472B6)],
                      title: 'Extrair áudio',
                      subtitle: 'M4A (AAC) ou MP3 do vídeo',
                      onTap: heavyOk ? _extractVideoAudio : null,
                    ),
                  ];
                  if (narrow) {
                    return Column(
                      children: [
                        for (final w in videoTools) ...[w, const SizedBox(height: 8)],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in videoTools)
                        SizedBox(
                          width: (c.maxWidth - 10) / 2,
                          child: w,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              ModernModuleUI.sectionTitle(
                context,
                'PDF PRO',
                accent: const Color(0xFF0EA5E9),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  final pdfTools = [
                    _ToolTile(
                      icon: UtilitariosModuleIcons.mergePdf,
                      gradient: const [Color(0xFF2563EB), Color(0xFF6366F1)],
                      title: 'Juntar PDF',
                      subtitle: 'Vários PDFs · reordenar páginas',
                      onTap: lightOk
                          ? () => _openPdfTool(UtilitariosPdfToolMode.merge)
                          : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.splitPdf,
                      gradient: const [Color(0xFFEA580C), Color(0xFFF97316)],
                      title: 'Dividir PDF',
                      subtitle: 'Escolher páginas ou intervalo',
                      onTap: lightOk
                          ? () => _openPdfTool(UtilitariosPdfToolMode.split)
                          : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.editPdf,
                      gradient: const [Color(0xFF059669), Color(0xFF34D399)],
                      title: 'Editor PDF',
                      subtitle: 'Texto, destaque e checks',
                      onTap: lightOk
                          ? () => _openPdfTool(UtilitariosPdfToolMode.edit)
                          : null,
                    ),
                  ];
                  if (narrow) {
                    return Column(
                      children: [
                        for (final w in pdfTools) ...[w, const SizedBox(height: 8)],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in pdfTools)
                        SizedBox(width: (c.maxWidth - 10) / 2, child: w),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              ModernModuleUI.sectionTitle(
                context,
                'FOTO & ARQUIVOS',
                accent: const Color(0xFFDB2777),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  final extraTools = [
                    _ToolTile(
                      icon: UtilitariosModuleIcons.photoTextExtract,
                      gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                      title: 'Extração de texto em foto',
                      subtitle: 'Lens · preview editável · Word e PDF',
                      onTap: lightOk ? _openPhotoTextExtract : null,
                    ),
                    _ToolTile(
                      icon: UtilitariosModuleIcons.archiveZip,
                      gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                      title: 'Compactar arquivos',
                      subtitle: 'ZIP · ZIP máximo · RAR (local)',
                      onTap: lightOk ? _compactarArquivos : null,
                    ),
                  ];
                  if (narrow) {
                    return Column(
                      children: [
                        for (final w in extraTools) ...[
                          w,
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in extraTools)
                        SizedBox(
                          width: (c.maxWidth - 10) / 2,
                          child: w,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                _footerQuotaText(),
                style: ModernModuleUI.moduleSubtitleStyle(context, fontSize: 11.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: ModernModuleUI.previewSheetDecoration(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          _busyLabel ?? 'Processando…',
                          textAlign: TextAlign.center,
                          style: ModernModuleUI.moduleTitleStyle(
                            context,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Aguarde a conclusão — não feche o app.',
                          textAlign: TextAlign.center,
                          style: ModernModuleUI.moduleSubtitleStyle(
                            context,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _footerQuotaText() {
    if (_isAdmin) {
      return 'Admin: conversões e compressões sem limite.';
    }
    if (_lightLocked || _heavyLocked) {
      final parts = <String>[];
      if (_lightLocked) {
        final at = _lightUnlockAt ??
            DateTime.now().add(UtilitariosDailyQuotaService.kLockDuration);
        parts.add(
          'Conversões: ${UtilitariosDailyQuotaService.unlockPhrase(at)}',
        );
      }
      if (_heavyLocked) {
        final at = _heavyUnlockAt ??
            DateTime.now().add(UtilitariosDailyQuotaService.kLockDuration);
        parts.add(
          'Compressões: ${UtilitariosDailyQuotaService.unlockPhrase(at)}',
        );
      }
      return parts.join('\n');
    }
    return 'Limites no aparelho: ${UtilitariosDailyQuotaService.kLightLimitPerDay} conversões · '
        '${UtilitariosDailyQuotaService.kHeavyLimitPerDay} compressões. Ao estourar, libera em 24h.';
  }
}

class _QuotaStatusCard extends StatelessWidget {
  final bool isAdmin;
  final int lightUsed;
  final int lightLimit;
  final int heavyUsed;
  final int heavyLimit;
  final DateTime? lightUnlockAt;
  final DateTime? heavyUnlockAt;

  const _QuotaStatusCard({
    required this.isAdmin,
    required this.lightUsed,
    required this.lightLimit,
    required this.heavyUsed,
    required this.heavyLimit,
    required this.lightUnlockAt,
    required this.heavyUnlockAt,
  });

  @override
  Widget build(BuildContext context) {
    if (isAdmin) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF059669).withValues(alpha: 0.10),
          border: Border.all(
            color: const Color(0xFF059669).withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFF059669),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Acesso admin: sem limites de conversão e compressão.',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.35,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final lightLeft = (lightLimit - lightUsed).clamp(0, lightLimit);
    final heavyLeft = (heavyLimit - heavyUsed).clamp(0, heavyLimit);
    final lightHint = lightLeft == 0
        ? (lightUnlockAt != null
            ? UtilitariosDailyQuotaService.unlockPhrase(lightUnlockAt!)
            : 'Esgotado')
        : 'Restam $lightLeft';
    final heavyHint = heavyLeft == 0
        ? (heavyUnlockAt != null
            ? UtilitariosDailyQuotaService.unlockPhrase(heavyUnlockAt!)
            : 'Esgotado')
        : 'Restam $heavyLeft';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.45),
        border: Border.all(
          color: const Color(0xFF64748B).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Uso no aparelho (libera em 24h ao estourar)',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuotaChip(
                  label: 'Conversões',
                  value: '$lightUsed/$lightLimit',
                  hint: lightHint,
                  accent: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuotaChip(
                  label: 'Compressões',
                  value: '$heavyUsed/$heavyLimit',
                  hint: heavyHint,
                  accent: const Color(0xFFE11D48),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuotaChip extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final Color accent;

  const _QuotaChip({
    required this.label,
    required this.value,
    required this.hint,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            hint,
            style: ModernModuleUI.moduleSubtitleStyle(context, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SecurityHeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1D4ED8),
            Color(0xFF0EA5E9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Ferramentas locais · 100% no aparelho',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Converta, edite e compacte arquivos com segurança — sem enviar documentos para a internet.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ToolTile({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: ModernModuleUI.moduleCardDecoration(
              context,
              borderAccent: gradient.last.withValues(alpha: 0.45),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  ModernModuleUI.iconBadge(icon: icon, gradient: gradient, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ModernModuleUI.moduleTitleStyle(
                            context,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          enabled ? subtitle : 'Limite atingido — aguarde 24h',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ModernModuleUI.moduleSubtitleStyle(context),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    enabled
                        ? Icons.chevron_right_rounded
                        : Icons.lock_clock_rounded,
                    color: ModernModuleUI.onSurfaceMuted(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompressSizeChip extends StatelessWidget {
  const _CompressSizeChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = ModernModuleUI.isDark(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.black.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white70 : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: dark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
