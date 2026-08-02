import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gestao_yahweh/services/pdf_launcher.dart';
import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'anexo_viewer_stub.dart' if (dart.library.html) 'anexo_viewer_web.dart' as anexo_web;

/// Exibe ofício de comparecimento (PDF ou imagem) dentro do app, sem baixar.
/// Carrega o arquivo pela URL e mostra em viewer (PdfPreview ou Image).
class AnexoViewerScreen extends StatefulWidget {
  final String url;
  final String? fileName;
  /// Quando definido (ex.: [mostrarAnexoNaMesmaTela]), o GET já corre em paralelo à animação do painel.
  final Future<http.Response>? prefetchResponse;

  const AnexoViewerScreen({
    super.key,
    required this.url,
    this.fileName,
    this.prefetchResponse,
  });

  @override
  State<AnexoViewerScreen> createState() => _AnexoViewerScreenState();
}

class _AnexoViewerScreenState extends State<AnexoViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  bool get _isPdf {
    final name = (widget.fileName ?? '').toLowerCase();
    if (name.endsWith('.pdf')) return true;
    // Fallback: PDF magic bytes
    if (_bytes != null && _bytes!.length >= 5) {
      return _bytes![0] == 0x25 && _bytes![1] == 0x50 && _bytes![2] == 0x44 && _bytes![3] == 0x46;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Na web, não fazemos fetch (Firebase Storage bloqueia por CORS). Abrimos em nova aba.
  bool _webAbrirExterno = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _bytes = null;
      _webAbrirExterno = false;
    });
    if (kIsWeb) {
      if (mounted) setState(() { _loading = false; _webAbrirExterno = true; });
      return;
    }
    try {
      final resp = widget.prefetchResponse != null
          ? await widget.prefetchResponse!
          : await http.get(Uri.parse(widget.url));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Não foi possível carregar o arquivo (${resp.statusCode})';
          _loading = false;
        });
        return;
      }
      setState(() {
        _bytes = resp.bodyBytes;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().split('\n').first;
          _loading = false;
        });
      }
    }
  }

  Future<void> _abrirEmNovaAba() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link. Copie e cole no navegador.')),
        );
      }
    }
  }

  String get _fileName {
    final n = (widget.fileName ?? '').trim();
    if (n.isNotEmpty) return n;
    return _isPdf ? 'oficio.pdf' : 'oficio.jpg';
  }

  String get _mimeType {
    final name = _fileName.toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  Future<void> _compartilhar(BuildContext context) async {
    if (_bytes == null || _bytes!.isEmpty) return;
    try {
      final xfile = XFile.fromData(_bytes!, name: _fileName, mimeType: _mimeType);
      Rect? origin;
      final ro = context.findRenderObject();
      if (ro is RenderBox && ro.hasSize && ro.size.width > 0 && ro.size.height > 0) {
        origin = ro.localToGlobal(Offset.zero) & ro.size;
      } else {
        final sz = MediaQuery.sizeOf(context);
        final pad = MediaQuery.paddingOf(context);
        origin = Rect.fromCenter(
          center: Offset(sz.width / 2, pad.top + sz.height / 3),
          width: 2,
          height: 2,
        );
      }
      await Share.shareXFiles(
        [xfile],
        text: 'Ofício de comparecimento',
        sharePositionOrigin: origin,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compartilhar aberto.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao compartilhar: ${e.toString().split('\n').first}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _baixar(BuildContext context) {
    if (_bytes == null || _bytes!.isEmpty) return;
    try {
      if (_isPdf) {
        openPdfFallback(_bytes!, filename: _fileName);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF aberto. Use "Salvar" ou "Compartilhar" para guardar no dispositivo.')),
          );
        }
      } else {
        // Imagem: usar compartilhar para o usuário poder salvar em Fotos/Arquivos
        Share.shareXFiles([XFile.fromData(_bytes!, name: _fileName, mimeType: _mimeType)], text: 'Ofício');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Escolha "Salvar imagem" ou "Salvar em Arquivos" para baixar.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao baixar: ${e.toString().split('\n').first}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.fileName ?? 'Ofício de comparecimento';
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextButton.icon(
            onPressed: () {
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            label: const Text('Voltar'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ),
        leadingWidth: 100,
        title: Text(
          title.length > 35 ? '${title.substring(0, 32)}...' : title,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
        actions: [
          if (kIsWeb)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Abrir em nova aba',
              onPressed: _abrirEmNovaAba,
            ),
          if (_bytes != null && _bytes!.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: () => _compartilhar(context),
              tooltip: 'Compartilhar',
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () => _baixar(context),
              tooltip: 'Baixar',
            ),
          ],
          if (_error != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
              tooltip: 'Tentar novamente',
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Carregando...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }
    if (_webAbrirExterno) {
      return anexo_web.buildAnexoWebViewer(widget.url, fileName: widget.fileName);
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 56, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }
    if (_bytes == null || _bytes!.isEmpty) {
      return const Center(
        child: Text(
          'Arquivo vazio.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    if (_isPdf) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: PdfPreview(
          build: (PdfPageFormat format) => Future.value(_bytes!),
          allowPrinting: false,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          initialPageFormat: PdfPageFormat.a4,
        ),
      );
    }

    // Imagem (PNG, JPEG)
    return Center(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.memory(
              _bytes!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Não foi possível exibir a imagem.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
