import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestao_yahweh/services/utilitarios_video_downloader_service.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';

/// Abre o fluxo de download de vídeos (YouTube/Instagram/Facebook/TikTok + qualquer vídeo).
Future<void> openUtilitariosVideoDownloaderFlow(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _VideoDownloaderPage(),
    ),
  );
}

class _VideoDownloaderPage extends StatefulWidget {
  const _VideoDownloaderPage();

  @override
  State<_VideoDownloaderPage> createState() => _VideoDownloaderPageState();
}

class _VideoDownloaderPageState extends State<_VideoDownloaderPage> {
  static const _gradient = [
    Color(0xFFE11D48),
    Color(0xFF7C3AED),
    Color(0xFF2563EB),
  ];

  final _urlCtrl = TextEditingController();
  final _focusNode = FocusNode();

  bool _busy = false;
  String? _busyLabel;
  double _progress = 0;
  VideoInfo? _videoInfo;
  VideoDownloadResult? _lastResult;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  VideoDownPlatform get _platform =>
      UtilitariosVideoDownloaderService.detectPlatform(_urlCtrl.text);

  bool get _hasValidUrl =>
      UtilitariosVideoDownloaderService.isValidUrl(_urlCtrl.text);

  IconData _platformIcon(VideoDownPlatform p) => switch (p) {
        VideoDownPlatform.youtube => Icons.play_circle_fill_rounded,
        VideoDownPlatform.instagram => Icons.camera_alt_rounded,
        VideoDownPlatform.facebook => Icons.thumb_up_rounded,
        VideoDownPlatform.tiktok => Icons.music_note_rounded,
        VideoDownPlatform.generic => Icons.videocam_rounded,
        VideoDownPlatform.unknown => Icons.link_rounded,
      };

  String _platformLabel(VideoDownPlatform p) => switch (p) {
        VideoDownPlatform.youtube => 'YouTube',
        VideoDownPlatform.instagram => 'Instagram',
        VideoDownPlatform.facebook => 'Facebook',
        VideoDownPlatform.tiktok => 'TikTok',
        VideoDownPlatform.generic => 'Vídeo Web',
        VideoDownPlatform.unknown => 'Desconhecido',
      };

  Color _platformColor(VideoDownPlatform p) => switch (p) {
        VideoDownPlatform.youtube => const Color(0xFFFF0000),
        VideoDownPlatform.instagram => const Color(0xFFE4405F),
        VideoDownPlatform.facebook => const Color(0xFF1877F2),
        VideoDownPlatform.tiktok => const Color(0xFF00F2EA),
        VideoDownPlatform.generic => const Color(0xFF8B5CF6),
        VideoDownPlatform.unknown => const Color(0xFF64748B),
      };

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _urlCtrl.text = data.text!;
        _urlCtrl.selection =
            TextSelection.collapsed(offset: _urlCtrl.text.length);
        _videoInfo = null;
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _fetchInfo() async {
    if (!_hasValidUrl) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Buscando informações…';
      _progress = 0;
    });
    try {
      final info = await UtilitariosVideoDownloaderService.fetchVideoInfo(
        _urlCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _videoInfo = info);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyDownloaderError(e)),
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

  Future<void> _download({required bool audioOnly}) async {
    if (!_hasValidUrl) return;
    setState(() {
      _busy = true;
      _busyLabel = audioOnly ? 'Baixando MP3…' : 'Baixando vídeo…';
      _progress = 0;
      _lastResult = null;
    });
    try {
      final result = await UtilitariosVideoDownloaderService.download(
        url: _urlCtrl.text.trim(),
        audioOnly: audioOnly,
        onProgress: (p) {
          if (!mounted) return;
          final clamped = p.clamp(0.0, 1.0);
          // Só atualiza a UI quando a % muda de fato (>= 1 ponto) — evita
          // dezenas de setState por segundo em downloads grandes.
          if (clamped >= 1.0 || (clamped - _progress).abs() >= 0.01) {
            setState(() => _progress = clamped);
          }
        },
      );
      if (!mounted) return;
      setState(() => _lastResult = result);
      await _showResultSheet(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyDownloaderError(e)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Tentar de novo',
            onPressed: () => _download(audioOnly: audioOnly),
          ),
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

  /// Mensagem amigável em pt-BR a partir de uma exceção do downloader.
  /// `StateError.toString()` já vem em pt-BR com o prefixo técnico
  /// "Bad state: " (não "StateError: ", que nunca batia aqui) — só limpa o
  /// prefixo; se não reconhecer o formato, cai numa mensagem genérica.
  String _friendlyDownloaderError(Object e) {
    var msg = e.toString();
    for (final prefix in ['Bad state: ', 'StateError: ', 'Exception: ']) {
      if (msg.startsWith(prefix)) {
        msg = msg.substring(prefix.length);
        break;
      }
    }
    msg = msg.trim();
    if (msg.isEmpty || msg.length > 200) {
      return 'Não foi possível baixar agora. Verifique o link e sua conexão, e tente de novo.';
    }
    return msg;
  }

  Future<void> _showResultSheet(VideoDownloadResult result) async {
    final action = await utilitariosShowShareSaveActionSheet(
      context,
      title: 'Download pronto!',
      subtitle:
          '${result.isAudioOnly ? 'Áudio (MP3/M4A)' : 'Vídeo (MP4)'} · ${_humanSize(result.bytes.length)} · 100% local no aparelho',
      fileName: result.title.isEmpty ? result.fileName : result.title,
    );
    if (!mounted || action == null) return;

    final isShare = action == 'share';
    final isFolderPick = action == 'save_folder';
    final ok = await utilitariosSaveOrShareBytes(
      context: context,
      bytes: result.bytes,
      fileName: result.fileName,
      mimeType: result.mimeType,
      preferShare: isShare,
      chooseSaveLocation: isFolderPick,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (isShare
                  ? 'Escolha WhatsApp, e-mail ou outro app.'
                  : 'Arquivo salvo na pasta escolhida.')
              : 'Não foi possível concluir.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _humanSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final platform = _platform;
    final validUrl = _hasValidUrl;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Baixar Vídeo'),
        leading: TextButton.icon(
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          label: Text(
            ModernModuleUI.previewRetornarLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ),
        leadingWidth: 120,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero card
                _buildHeroCard(),
                const SizedBox(height: 18),

                // URL input with paste button
                _buildUrlInput(platform, validUrl),
                const SizedBox(height: 14),

                // Platform badge
                if (validUrl) _buildPlatformBadge(platform),
                if (validUrl) const SizedBox(height: 14),

                // Video info preview
                if (_videoInfo != null) ...[
                  _buildVideoInfoCard(_videoInfo!),
                  const SizedBox(height: 14),
                ],

                // Action buttons
                _buildActionButtons(validUrl),

                // Progress
                if (_busy && _progress > 0) ...[
                  const SizedBox(height: 14),
                  _buildProgressBar(),
                ],
              ],
            ),
          ),
          if (_busy && _progress == 0) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _gradient.map((c) => c.withValues(alpha: 0.12)).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _gradient.first.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: _gradient),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _gradient.first.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.cloud_download_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Baixar Vídeos',
            style: ModernModuleUI.moduleTitleStyle(context, fontSize: 19),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'TikTok · YouTube · Instagram · Facebook\nCole o link → baixe rápido → salve ou compartilhe\nMP4/MP3 · multi-fonte · 100% no aparelho',
            textAlign: TextAlign.center,
            style: ModernModuleUI.moduleSubtitleStyle(context),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlInput(VideoDownPlatform platform, bool validUrl) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: validUrl
              ? _platformColor(platform).withValues(alpha: 0.5)
              : const Color(0xFF64748B).withValues(alpha: 0.3),
          width: 1.5,
        ),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          // Botão Colar
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              tooltip: 'Colar link',
              icon: const Icon(Icons.content_paste_rounded, size: 22),
              color: _gradient.first,
              onPressed: _busy ? null : _pasteFromClipboard,
            ),
          ),
          // URL field
          Expanded(
            child: TextField(
              controller: _urlCtrl,
              focusNode: _focusNode,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Cole o link do vídeo aqui…',
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              // Menu nativo em pt-BR (evita "Paste" em inglês no Android/iOS).
              contextMenuBuilder: _ptBrContextMenuBuilder,
              onChanged: (_) => setState(() => _videoInfo = null),
              onSubmitted: (_) {
                if (validUrl) _fetchInfo();
              },
            ),
          ),
          // Clear button
          if (_urlCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.clear_rounded, size: 20),
                color: const Color(0xFF64748B),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _urlCtrl.clear();
                          _videoInfo = null;
                        }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ptBrContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    String? mapLabel(ContextMenuButtonType type) {
      switch (type) {
        case ContextMenuButtonType.cut:
          return 'Recortar';
        case ContextMenuButtonType.copy:
          return 'Copiar';
        case ContextMenuButtonType.paste:
          return 'Colar';
        case ContextMenuButtonType.selectAll:
          return 'Selecionar tudo';
        case ContextMenuButtonType.lookUp:
          return 'Consultar';
        case ContextMenuButtonType.searchWeb:
          return 'Pesquisar na web';
        case ContextMenuButtonType.share:
          return 'Compartilhar';
        case ContextMenuButtonType.liveTextInput:
          return 'Escanear texto';
        default:
          return null;
      }
    }

    final mappedItems = editableTextState.contextMenuButtonItems
        .map((item) => item.copyWith(label: mapLabel(item.type) ?? item.label))
        .toList();

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: mappedItems,
    );
  }

  Widget _buildPlatformBadge(VideoDownPlatform platform) {
    final c = _platformColor(platform);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_platformIcon(platform), color: c, size: 18),
              const SizedBox(width: 6),
              Text(
                _platformLabel(platform),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: c,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Link detectado — pronto para baixar',
            style: ModernModuleUI.moduleSubtitleStyle(context, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoInfoCard(VideoInfo info) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _gradient.first.withValues(alpha: 0.06),
        border: Border.all(color: _gradient.first.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          if (info.thumbnailUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                info.thumbnailUrl,
                width: 90,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 90,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _gradient.first.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.videocam_rounded,
                    color: _gradient.first,
                    size: 28,
                  ),
                ),
              ),
            )
          else
            Container(
              width: 90,
              height: 60,
              decoration: BoxDecoration(
                color: _gradient.first.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.videocam_rounded,
                color: _gradient.first,
                size: 28,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.author,
                  style:
                      ModernModuleUI.moduleSubtitleStyle(context, fontSize: 12),
                ),
                if (info.duration != null)
                  Text(
                    _formatDuration(info.duration!),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: _gradient.last,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool validUrl) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy || !validUrl
                ? null
                : () => _download(audioOnly: false),
            icon: const Icon(Icons.bolt_rounded, size: 22),
            label: const Text('Baixar Vídeo MP4'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 54),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !validUrl ? null : _fetchInfo,
                icon: const Icon(Icons.info_outline_rounded, size: 20),
                label: const Text('Info'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 50),
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy || !validUrl
                    ? null
                    : () => _download(audioOnly: true),
                icon: const Icon(Icons.audiotrack_rounded, size: 20),
                label: const Text('Só Áudio'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 50),
                  backgroundColor: const Color(0xFFE11D48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 10,
            backgroundColor: _gradient.first.withValues(alpha: 0.12),
            color: _gradient.last,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(_progress * 100).toInt()}%',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: _gradient.last,
          ),
        ),
      ],
    );
  }

  Widget _buildBusyOverlay() {
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 36),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _gradient.last.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _gradient.last,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _busyLabel ?? 'Processando…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}min';
    return '${m}min${s.toString().padLeft(2, '0')}s';
  }
}
