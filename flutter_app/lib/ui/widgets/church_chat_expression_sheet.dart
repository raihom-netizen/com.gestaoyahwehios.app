import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_expression_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// Escolha enviada ao chat (logo institucional ou figurinha da biblioteca).
class ChurchStickerPick {
  final String mediaUrl;
  final String? storagePath;
  final String stickerSource;

  const ChurchStickerPick({
    required this.mediaUrl,
    this.storagePath,
    required this.stickerSource,
  });
}

Future<void> showChurchChatStickerSheet({
  required BuildContext context,
  required String tenantId,
  required Future<void> Function(ChurchStickerPick pick) onStickerChosen,
}) async {
  await showChurchChatExpressionSheet(
    context: context,
    tenantId: tenantId,
    textEditingController: TextEditingController(),
    initialTabIndex: 1,
    onStickerChosen: onStickerChosen,
    disposeOrphanController: true,
  );
}

/// Painel unificado: **Emojis** | **Figurinhas** + recentes locais.
Future<void> showChurchChatExpressionSheet({
  required BuildContext context,
  required String tenantId,
  required TextEditingController textEditingController,
  int initialTabIndex = 0,
  required Future<void> Function(ChurchStickerPick pick) onStickerChosen,
  bool disposeOrphanController = false,
}) async {
  final mq = MediaQuery.sizeOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxWidth: mq.width,
      maxHeight: mq.height * 0.94,
    ),
    builder: (ctx) => _ExpressionSheetBody(
      tenantId: tenantId,
      textEditingController: textEditingController,
      initialTabIndex: initialTabIndex,
      onStickerChosen: onStickerChosen,
      disposeOrphanController: disposeOrphanController,
    ),
  );
}

class _ExpressionSheetBody extends StatefulWidget {
  final String tenantId;
  final TextEditingController textEditingController;
  final int initialTabIndex;
  final Future<void> Function(ChurchStickerPick pick) onStickerChosen;
  final bool disposeOrphanController;

  const _ExpressionSheetBody({
    required this.tenantId,
    required this.textEditingController,
    required this.initialTabIndex,
    required this.onStickerChosen,
    required this.disposeOrphanController,
  });

  @override
  State<_ExpressionSheetBody> createState() => _ExpressionSheetBodyState();
}

class _ExpressionSheetBodyState extends State<_ExpressionSheetBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex.clamp(0, 1);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: idx,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (widget.disposeOrphanController) {
      widget.textEditingController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (ctx, _) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeCleanPremium.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.onSurfaceVariant
                        .withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 12, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            ThemeCleanPremium.primary,
                            ThemeCleanPremium.primaryLight,
                          ],
                        ),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      child: const Icon(Icons.interests_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expressar',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                          Text(
                            'Emojis e figurinhas da igreja',
                            style: TextStyle(
                              fontSize: 12,
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded,
                          color: ThemeCleanPremium.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                labelColor: ThemeCleanPremium.primary,
                unselectedLabelColor: ThemeCleanPremium.onSurfaceVariant,
                indicatorColor: ThemeCleanPremium.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.emoji_emotions_rounded), text: 'Emojis'),
                  Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Figurinhas'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _EmojiTab(
                      tenantId: widget.tenantId,
                      controller: widget.textEditingController,
                      bottomInset: bottom,
                    ),
                    _StickerLibraryTab(
                      tenantId: widget.tenantId,
                      bottomInset: bottom,
                      onStickerChosen: widget.onStickerChosen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmojiTab extends StatefulWidget {
  final String tenantId;
  final TextEditingController controller;
  final double bottomInset;

  const _EmojiTab({
    required this.tenantId,
    required this.controller,
    required this.bottomInset,
  });

  @override
  State<_EmojiTab> createState() => _EmojiTabState();
}

class _EmojiTabState extends State<_EmojiTab> {
  int _recentEpoch = 0;

  void _refreshRecent() => setState(() => _recentEpoch++);

  void _insertEmoji(String e) {
    final t = widget.controller.text;
    widget.controller.text = t + e;
    widget.controller.selection =
        TextSelection.collapsed(offset: widget.controller.text.length);
    unawaited(
      ChurchChatExpressionPrefs.rememberEmoji(widget.tenantId, e),
    );
    _refreshRecent();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<List<String>>(
          key: ValueKey(_recentEpoch),
          future: ChurchChatExpressionPrefs.recentEmojis(widget.tenantId),
          builder: (context, snap) {
            final recent = snap.data ?? [];
            if (recent.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recentes',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 46,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        return Material(
                          color: ThemeCleanPremium.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _insertEmoji(recent[i]),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: Center(
                                child: Text(
                                  recent[i],
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.bottomInset),
            child: LayoutBuilder(
              builder: (ctx, c) {
                final h = (c.maxHeight - 8).clamp(220.0, 520.0);
                final appLocale = Localizations.maybeLocaleOf(ctx);
                return EmojiPicker(
                  textEditingController: widget.controller,
                  onEmojiSelected: (category, emoji) {
                    unawaited(
                      ChurchChatExpressionPrefs.rememberEmoji(
                        widget.tenantId,
                        emoji.emoji,
                      ),
                    );
                    _refreshRecent();
                  },
                  config: Config(
                    height: h,
                    /// Na web e com fontes personalizadas, filtrar por «compatibilidade»
                    /// pode esvaziar a grelha; locale pt melhora busca e categorias.
                    checkPlatformCompatibility: false,
                    locale: appLocale ?? const Locale('pt'),
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: ThemeCleanPremium.cardBackground,
                      columns: kIsWeb ? 10 : 8,
                      emojiSizeMax: kIsWeb ? 26 : 28,
                      buttonMode:
                          kIsWeb ? ButtonMode.NONE : ButtonMode.MATERIAL,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StickerLibraryTab extends StatefulWidget {
  final String tenantId;
  final double bottomInset;
  final Future<void> Function(ChurchStickerPick pick) onStickerChosen;

  const _StickerLibraryTab({
    required this.tenantId,
    required this.bottomInset,
    required this.onStickerChosen,
  });

  @override
  State<_StickerLibraryTab> createState() => _StickerLibraryTabState();
}

class _StickerLibraryTabState extends State<_StickerLibraryTab> {
  bool _importing = false;
  int _recentEpoch = 0;

  void _refreshRecentStickers() => setState(() => _recentEpoch++);

  Future<void> _pickAndImportImage() async {
    if (_importing) return;
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (x == null || !mounted) return;

    final labelCtrl = TextEditingController();
    final labelOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar figurinha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nome opcional (ajuda a organizar na biblioteca).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                hintText: 'Ex.: Culto domingo',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    try {
      if (labelOk != true || !mounted) return;
      setState(() => _importing = true);
      final bytes = await x.readAsBytes();
      if (bytes.isEmpty || !mounted) return;
      final name = x.name.trim().isNotEmpty ? x.name : 'sticker.png';
      final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
      final up = await ChurchChatService.uploadStickerPackBytes(
        tenantId: widget.tenantId,
        bytes: bytes,
        fileName: name,
        contentType: mime,
      );
      await ChurchChatService.registerStickerPackEntry(
        tenantId: widget.tenantId,
        mediaUrl: up.url,
        storagePath: up.path,
        label: labelCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Figurinha adicionada — toque para enviar.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ThemeCleanPremium.primary,
        ),
      );
      _refreshRecentStickers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível importar: $e')),
      );
    } finally {
      labelCtrl.dispose();
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmDeleteSticker(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover figurinha'),
        content: const Text(
          'Remove da biblioteca da igreja (as mensagens já enviadas mantêm-se até expirarem).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await ChurchChatService.deleteStickerPackEntry(
      tenantId: widget.tenantId,
      stickerDocId: docId,
    );
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível remover.')),
      );
    } else {
      _refreshRecentStickers();
    }
  }

  void _emit(ChurchStickerPick pick) {
    Navigator.of(context).pop();
    unawaited(widget.onStickerChosen(pick));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + widget.bottomInset),
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(_recentEpoch),
          future: ChurchChatExpressionPrefs.recentStickers(widget.tenantId),
          builder: (context, snap) {
            final recent = snap.data ?? [];
            if (recent.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recentes',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final m = recent[i];
                        final url = (m['mediaUrl'] ?? '').toString().trim();
                        if (url.isEmpty) return const SizedBox.shrink();
                        final sp = (m['storagePath'] ?? '').toString();
                        final src =
                            (m['stickerSource'] ?? 'upload').toString();
                        return Material(
                          color: ThemeCleanPremium.cardBackground,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          elevation: 0,
                          child: InkWell(
                            onTap: () => _emit(
                              ChurchStickerPick(
                                mediaUrl: url,
                                storagePath:
                                    sp.isNotEmpty ? sp : null,
                                stickerSource: src,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: SafeNetworkImage(
                                  imageUrl: url,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream:               ChurchUiCollections.churchDoc(widget.tenantId)
              .watchSafe(),
          builder: (context, snap) {
            final data = snap.data?.data();
            final logoPath = ChurchBrandService.logoPathFromData(
              data,
              churchId: widget.tenantId,
            );
            if (logoPath == null || logoPath.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.cardBackground,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    border: Border.all(
                      color:
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: ThemeCleanPremium.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sem logo configurada. Defina a logo da igreja no cadastro para usar aqui.',
                          style: TextStyle(
                            fontSize: 13,
                            color: ThemeCleanPremium.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logo da igreja',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _emit(
                        ChurchStickerPick(
                          mediaUrl: '',
                          storagePath: logoPath,
                          stickerSource: 'church_logo',
                        ),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              ThemeCleanPremium.primary.withValues(alpha: 0.12),
                              ThemeCleanPremium.primaryLight
                                  .withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                ThemeCleanPremium.primary.withValues(alpha: 0.2),
                          ),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.08),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: StableChurchLogo(
                                  tenantId: widget.tenantId,
                                  tenantData: data,
                                  storagePath: logoPath,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Marca da igreja',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: ThemeCleanPremium.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Toque para enviar como figurinha.',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.35,
                                        color: ThemeCleanPremium.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.send_rounded,
                                color: ThemeCleanPremium.primary,
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
          },
        ),
        Row(
          children: [
            Text(
              'Biblioteca',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: ThemeCleanPremium.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _importing ? null : _pickAndImportImage,
              icon: _importing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ThemeCleanPremium.primary,
                      ),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded, size: 20),
              label: Text(_importing ? 'A importar…' : 'Importar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ChurchChatService.stickersCol(widget.tenantId)
              .orderBy('createdAt', descending: true)
              .limit(72)
              .watchSafe(),
          builder: (context, stickerSnap) {
            if (stickerSnap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = stickerSnap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Ainda não há figurinhas importadas.\nUse «Importar» ou envie a logo acima.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ThemeCleanPremium.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 118,
              ),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final doc = docs[i];
                final m = doc.data();
                final url = (m['mediaUrl'] ?? '').toString().trim();
                final mine =
                    (m['createdByUid'] ?? '').toString() == uid;
                final label =
                    (m['label'] ?? '').toString().trim();
                if (url.isEmpty) return const SizedBox.shrink();
                return Material(
                  color: ThemeCleanPremium.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  elevation: 0,
                  child: InkWell(
                    onTap: () => _emit(
                      ChurchStickerPick(
                        mediaUrl: url,
                        storagePath: (m['storagePath'] ?? '').toString(),
                        stickerSource: 'upload',
                      ),
                    ),
                    onLongPress: mine
                        ? () => _confirmDeleteSticker(doc.id)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(5, 5, 5, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SafeNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                            ),
                          ),
                          if (label.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 2),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
