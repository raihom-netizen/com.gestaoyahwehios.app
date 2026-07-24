import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_disk_cache.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/utils/finance_comprovante_utils.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_original_media_viewer.dart';
import 'package:gestao_yahweh/ui/widgets/finance_comprovante_viewer_web_stub.dart'
    if (dart.library.html) 'package:gestao_yahweh/ui/widgets/finance_comprovante_viewer_web.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';

/// Visualização premium de comprovante (imagem ou PDF) — padrão Controle Total.
abstract final class FinanceComprovanteViewerSheet {
  FinanceComprovanteViewerSheet._();

  static Future<void> showFromDoc(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    if (!FinanceComprovanteAttachService.hasComprovanteInDoc(data)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este lançamento não tem comprovante.')),
        );
      }
      return;
    }
    final mime = FinanceComprovanteAttachService.mimeFromDoc(data);
    final fileName = FinanceComprovanteAttachService.displayNameFromDoc(data);
    final storagePath = FinanceComprovanteUtils.storagePath(data);
    var url =
        await FinanceComprovantePublishService.resolveComprovanteUrl(data);
    if (!context.mounted) return;
    // Path-only / getDownloadURL falhou: carregar bytes direto do Storage.
    if (url.isEmpty) {
      if (storagePath.isNotEmpty) {
        final isPdf = mime.toLowerCase().contains('pdf') ||
            fileName.toLowerCase().endsWith('.pdf');
        if (isPdf) {
          await _showPdfFromStorage(context, data, fileName);
        } else {
          await _showImageFromStorage(context, data, fileName, mime);
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o comprovante.'),
        ),
      );
      return;
    }
    await show(
      context,
      url: url,
      fileName: fileName,
      mimeType: mime,
      storagePath: storagePath,
    );
  }

  static Future<void> _showImageFromStorage(
    BuildContext context,
    Map<String, dynamic> data,
    String fileName,
    String mime,
  ) async {
    try {
      await ensureFirebaseCore(requireAuth: false);
      final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
      if (path.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir o comprovante.')),
          );
        }
        return;
      }
      final bytes = await firebaseDefaultStorage
          .ref(path)
          .getData(FinanceComprovanteAttachService.maxBytes);
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível carregar a imagem.')),
        );
        return;
      }
      if (kIsWeb) {
        await showFinanceComprovanteWebBytes(
          context: context,
          bytes: bytes,
          fileName: fileName,
          mimeType: mime,
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.45,
          maxChildSize: 0.98,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString();
        final missing = msg.contains('object-not-found') ||
            msg.contains('No object exists');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              missing
                  ? 'Comprovante não encontrado no Storage. Use «Trocar» para anexar de novo.'
                  : 'Erro ao abrir comprovante: ${msg.split('\n').first}',
            ),
          ),
        );
      }
    }
  }

  static Future<void> show(
    BuildContext context, {
    required String url,
    required String fileName,
    required String mimeType,
    String storagePath = '',
  }) async {
    if (url.trim().isEmpty) return;
    if (kIsWeb) {
      await showFinanceComprovanteWebEmbed(
        context: context,
        url: url,
        fileName: fileName,
        mimeType: mimeType,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.45,
        maxChildSize: 0.98,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: mimeType.contains('pdf')
                    ? _PdfBody(
                        url: url,
                        storagePath: storagePath,
                        fileName: fileName,
                      )
                    : Center(
                        child: GestureDetector(
                          onTap: () => showYahwehOriginalImageZoom(
                            context,
                            imageUrl: url,
                          ),
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 5,
                            child: SafeNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _showPdfFromStorage(
    BuildContext context,
    Map<String, dynamic> data,
    String fileName,
  ) async {
    try {
      await ensureFirebaseCore(requireAuth: false);
      final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
      Uint8List? bytes;
      if (path.isNotEmpty) {
        bytes = await firebaseDefaultStorage
            .ref(path)
            .getData(FinanceComprovanteAttachService.maxBytes);
      }
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível carregar o PDF.')),
        );
        return;
      }
      await showPdfActions(context, bytes: bytes, filename: fileName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao abrir PDF: ${e.toString().split('\n').first}',
            ),
          ),
        );
      }
    }
  }
}

class _PdfBody extends StatefulWidget {
  const _PdfBody({
    required this.url,
    required this.storagePath,
    required this.fileName,
  });

  final String url;
  final String storagePath;
  final String fileName;

  @override
  State<_PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends State<_PdfBody> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await ensureFirebaseCore(requireAuth: false);
      final cacheKey = FinanceComprovanteDiskCache.keyFor(
        storagePath: widget.storagePath,
        url: widget.url,
      );
      Uint8List? bytes = await FinanceComprovanteDiskCache.getBytes(cacheKey);
      if (bytes == null || bytes.isEmpty) {
        final path = widget.storagePath.trim();
        if (path.isNotEmpty) {
          bytes = await firebaseDefaultStorage
              .ref(path)
              .getData(FinanceComprovanteAttachService.maxBytes);
        }
        if ((bytes == null || bytes.isEmpty) && widget.url.isNotEmpty) {
          bytes = await firebaseDefaultStorage
              .refFromURL(widget.url)
              .getData(FinanceComprovanteAttachService.maxBytes);
        }
        if (bytes != null && bytes.isNotEmpty) {
          unawaited(FinanceComprovanteDiskCache.putBytes(cacheKey, bytes));
        }
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'PDF não encontrado no Storage.';
        });
        return;
      }
      setState(() => _loading = false);
      await showPdfActions(
        context,
        bytes: bytes,
        filename: widget.fileName,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().split('\n').first;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _error ?? 'Abrindo PDF…',
          textAlign: TextAlign.center,
          style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
        ),
      ),
    );
  }
}
