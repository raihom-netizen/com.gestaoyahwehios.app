import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:gestao_yahweh/core/marketing_gallery_cms.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/institutional_media_period.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_institutional_video.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

enum _GalleryKind { video, image, pdf }

enum _PublicTypeFilter { all, video, image, pdf }

class _GalleryEntry {
  final String title;
  final String description;
  final String category;
  final bool featured;
  final String storagePath;
  final _GalleryKind kind;
  final DateTime? uploadedAt;
  /// URL https do Storage (gravada no CMS); ajuda web/mobile quando só path falha.
  final String? downloadUrl;

  const _GalleryEntry({
    required this.title,
    this.description = '',
    this.category = '',
    this.featured = false,
    required this.storagePath,
    required this.kind,
    this.uploadedAt,
    this.downloadUrl,
  });
}

/// Galeria institucional: vídeos, imagens e PDFs em `public/gestao_yahweh/…`
/// (lista via Firestore ou varredura do Storage).
class MarketingGestaoYahwehGallerySection extends StatefulWidget {
  /// Painel master: checkboxes, respeita [adminConfig] (período + seleção).
  final InstitutionalMediaAdminConfig? adminConfig;

  /// Limite de ficheiros na varredura do Storage (modo admin pode subir).
  final int maxStorageFiles;

  const MarketingGestaoYahwehGallerySection({
    super.key,
    this.adminConfig,
    this.maxStorageFiles = 36,
  });

  @override
  State<MarketingGestaoYahwehGallerySection> createState() =>
      _MarketingGestaoYahwehGallerySectionState();
}

class _MarketingGestaoYahwehGallerySectionState
    extends State<MarketingGestaoYahwehGallerySection> {
  List<_GalleryEntry>? _storageEntries;
  bool _storageRequested = false;
  bool _storageLoading = false;
  Timer? _firestoreWaitTimer;
  bool _firestoreWaitExceeded = false;
  _PublicTypeFilter _typeFilter = _PublicTypeFilter.all;
  String _lastVisiblePathsKey = '';

  @override
  void dispose() {
    _firestoreWaitTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MarketingGestaoYahwehGallerySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminConfig?.onVisiblePathsUpdated !=
        widget.adminConfig?.onVisiblePathsUpdated) {
      _lastVisiblePathsKey = '';
    }
  }

  void _reportAdminVisiblePaths(List<_GalleryEntry> entries) {
    final cb = widget.adminConfig?.onVisiblePathsUpdated;
    if (cb == null) return;
    final paths = entries
        .map((e) => MarketingStorageLayout.normalizeObjectPath(e.storagePath))
        .toList()
      ..sort();
    final key = paths.join('\u0001');
    if (key == _lastVisiblePathsKey) return;
    _lastVisiblePathsKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.adminConfig?.onVisiblePathsUpdated?.call(paths);
    });
  }

  void _armFirestoreWaitCap() {
    _firestoreWaitTimer ??= Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _firestoreWaitExceeded = true);
    });
  }

  void _disarmFirestoreWaitCap() {
    _firestoreWaitTimer?.cancel();
    _firestoreWaitTimer = null;
  }

  void _scheduleStorageFallback() {
    if (_storageRequested) return;
    _storageRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFromStorage();
    });
  }

  static _GalleryKind _kindFromString(String? k, String pathLow) {
    final s = (k ?? '').toLowerCase().trim();
    if (s == 'video' || s == 'vídeo') return _GalleryKind.video;
    if (s == 'image' || s == 'imagem' || s == 'foto') return _GalleryKind.image;
    if (s == 'pdf' || s == 'documento') return _GalleryKind.pdf;
    if (pathLow.endsWith('.pdf')) return _GalleryKind.pdf;
    if (pathLow.endsWith('.mp4') ||
        pathLow.endsWith('.webm') ||
        pathLow.endsWith('.mov') ||
        pathLow.endsWith('.m4v')) {
      return _GalleryKind.video;
    }
    return _GalleryKind.image;
  }

  static String _basename(String path) {
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  static String? _pickDownloadUrl(Map<String, dynamic> m) {
    for (final k in const [
      'downloadUrl',
      'videoUrl',
      'imageUrl',
      'mediaUrl',
      'url',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  List<_GalleryEntry> _parseFirestoreItems(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['items'];
    if (raw is! List) return [];
    final out = <_GalleryEntry>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final path = MarketingStorageLayout.normalizeObjectPath(
        (m['path'] ?? m['storagePath'] ?? '').toString(),
      );
      if (path.isEmpty) continue;
      final title = (m['title'] ?? m['name'] ?? _basename(path)).toString().trim();
      final desc = (m['description'] ?? m['shortDescription'] ?? '').toString().trim();
      final rawCat = (m['category'] ?? '').toString().trim();
      final cat = rawCat.isEmpty
          ? ''
          : MarketingGalleryCms.normalizeCategory(rawCat);
      final featured = MarketingGalleryCms.truthy(m['featured']);
      final kind = _kindFromString(m['kind']?.toString(), path.toLowerCase());
      final uploaded = institutionalMediaDateFromItem(m, storagePath: path);
      out.add(_GalleryEntry(
        title: title,
        description: desc,
        category: cat,
        featured: featured,
        storagePath: path,
        kind: kind,
        uploadedAt: uploaded,
        downloadUrl: _pickDownloadUrl(m),
      ));
    }
    return out;
  }

  List<_GalleryEntry> _sortFeaturedFirst(List<_GalleryEntry> items) {
    final f = <_GalleryEntry>[];
    final r = <_GalleryEntry>[];
    for (final e in items) {
      if (e.featured) {
        f.add(e);
      } else {
        r.add(e);
      }
    }
    return [...f, ...r];
  }

  List<_GalleryEntry> _applyTypeFilter(
      List<_GalleryEntry> list, _PublicTypeFilter f) {
    switch (f) {
      case _PublicTypeFilter.all:
        return list;
      case _PublicTypeFilter.video:
        return list.where((e) => e.kind == _GalleryKind.video).toList();
      case _PublicTypeFilter.image:
        return list.where((e) => e.kind == _GalleryKind.image).toList();
      case _PublicTypeFilter.pdf:
        return list.where((e) => e.kind == _GalleryKind.pdf).toList();
    }
  }

  Future<void> _loadFromStorage() async {
    if (_storageLoading) return;
    if (!mounted) return;
    setState(() => _storageLoading = true);
    try {
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      }
      final root =
          FirebaseStorage.instance.ref(MarketingStorageLayout.storageRoot);
      final refs = await _listFilesRecursive(root, maxFiles: widget.maxStorageFiles)
          .timeout(
        const Duration(seconds: 22),
        onTimeout: () {
          debugPrint(
              'MarketingGestaoYahwehGallerySection: list timeout ${MarketingStorageLayout.storageRoot}');
          return <Reference>[];
        },
      );
      final entries = <_GalleryEntry>[];
      for (final r in refs) {
        final name = r.name.toLowerCase();
        if (name.startsWith('.')) continue;
        _GalleryKind kind;
        if (name.endsWith('.pdf')) {
          kind = _GalleryKind.pdf;
        } else if (name.endsWith('.mp4') ||
            name.endsWith('.webm') ||
            name.endsWith('.mov') ||
            name.endsWith('.m4v')) {
          kind = _GalleryKind.video;
        } else if (name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp') ||
            name.endsWith('.gif')) {
          kind = _GalleryKind.image;
        } else {
          continue;
        }
        final full =
            MarketingStorageLayout.normalizeObjectPath(r.fullPath);
        entries.add(_GalleryEntry(
          title: _basename(full),
          storagePath: full,
          kind: kind,
          uploadedAt: institutionalMediaDateFromPath(full),
        ));
      }
      entries.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (mounted) {
        setState(() {
          _storageEntries = entries;
          _storageLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MarketingGestaoYahwehGallerySection._loadFromStorage: $e');
      if (mounted) {
        setState(() {
          _storageEntries = [];
          _storageLoading = false;
        });
      }
    }
  }

  static Future<List<Reference>> _listFilesRecursive(
    Reference ref, {
    required int maxFiles,
    int depth = 0,
  }) async {
    if (depth > 8) return [];
    final out = <Reference>[];
    try {
      final list = await ref.listAll().timeout(
        const Duration(seconds: 14),
        onTimeout: () {
          debugPrint(
              'MarketingGestaoYahwehGallerySection: listAll timeout at depth $depth');
          throw TimeoutException('listAll', const Duration(seconds: 14));
        },
      );
      out.addAll(list.items);
      for (final p in list.prefixes) {
        if (out.length >= maxFiles) break;
        out.addAll(await _listFilesRecursive(p,
            maxFiles: maxFiles - out.length, depth: depth + 1));
      }
    } on TimeoutException {
      return out.take(maxFiles).toList();
    } catch (e) {
      debugPrint('MarketingGestaoYahwehGallerySection list: $e');
    }
    return out.take(maxFiles).toList();
  }

  List<_GalleryEntry> _filterByAdmin(List<_GalleryEntry> entries) {
    final cfg = widget.adminConfig;
    if (cfg == null) return entries;
    return entries
        .where((e) => institutionalMediaMatchesPeriod(
              e.uploadedAt,
              cfg.period,
              cfg.customStart,
              cfg.customEnd,
            ))
        .toList();
  }

  Widget _buildTypeFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _filterChip('Tudo', _PublicTypeFilter.all),
        _filterChip('Vídeos', _PublicTypeFilter.video),
        _filterChip('Imagens', _PublicTypeFilter.image),
        _filterChip('PDFs', _PublicTypeFilter.pdf),
      ],
    );
  }

  Widget _filterChip(String label, _PublicTypeFilter value) {
    final sel = _typeFilter == value;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _typeFilter = value),
      selectedColor: const Color(0xFFBFDBFE),
      checkmarkColor: const Color(0xFF1E5AA8),
      labelStyle: TextStyle(
        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
        color: sel ? const Color(0xFF1E3A5F) : const Color(0xFF475569),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(
        color: sel ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
      ),
    );
  }

  Widget _buildMediaGrid(BuildContext context, List<_GalleryEntry> entries) {
    final admin = widget.adminConfig;
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    if (admin != null) {
      final w = isMobile ? double.infinity : 300.0;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: entries
            .map(
              (e) => SizedBox(
                width: w,
                child: _MediaCard(
                  entry: e,
                  adminConfig: admin,
                  showMetaBelow: true,
                ),
              ),
            )
            .toList(),
      );
    }
    final cross = isMobile ? 2 : 3;
    return MasonryGridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: cross,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _MediaCard(
          entry: entries[index],
          adminConfig: null,
          showMetaBelow: true,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance
        .collection(MarketingStorageLayout.firestoreCollection)
        .doc(MarketingStorageLayout.firestoreGalleryDocId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasData || snap.hasError) {
          _disarmFirestoreWaitCap();
        }

        final fromFs = snap.hasError
            ? <_GalleryEntry>[]
            : _parseFirestoreItems(snap.data?.data());
        if (fromFs.isNotEmpty) {
          var ordered = _sortFeaturedFirst(fromFs);
          final filtered = _filterByAdmin(ordered);
          final forPublic = widget.adminConfig == null
              ? _applyTypeFilter(filtered, _typeFilter)
              : filtered;
          if (filtered.isEmpty && widget.adminConfig != null) {
            _reportAdminVisiblePaths([]);
            return _GalleryChrome(
              adminConfig: widget.adminConfig,
              showPublicFilters: false,
              typeFilterChips: null,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nenhuma mídia neste período (ou sem data no nome do ficheiro). '
                    'Escolha «Todo o período» ou envie novos ficheiros.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            );
          }
          if (forPublic.isEmpty && widget.adminConfig == null) {
            return _GalleryChrome(
              adminConfig: widget.adminConfig,
              showPublicFilters: true,
              typeFilterChips: _buildTypeFilterChips(),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Nenhum item nesta categoria.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            );
          }
          _reportAdminVisiblePaths(
              widget.adminConfig != null ? forPublic : const []);
          return _GalleryChrome(
            adminConfig: widget.adminConfig,
            showPublicFilters: widget.adminConfig == null,
            typeFilterChips: widget.adminConfig == null ? _buildTypeFilterChips() : null,
            children: [
              _buildMediaGrid(context, forPublic),
            ],
          );
        }

        final fsWaiting =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        if (fsWaiting && !_firestoreWaitExceeded) {
          _armFirestoreWaitCap();
          _reportAdminVisiblePaths([]);
          return _GalleryChrome(
            adminConfig: widget.adminConfig,
            showPublicFilters: false,
            typeFilterChips: null,
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          );
        }

        if (snap.hasError) {
          debugPrint('MarketingGestaoYahwehGallerySection Firestore: ${snap.error}');
        }
        _scheduleStorageFallback();

        if (_storageLoading && (_storageEntries == null)) {
          _reportAdminVisiblePaths([]);
          return _GalleryChrome(
            adminConfig: widget.adminConfig,
            showPublicFilters: false,
            typeFilterChips: null,
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          );
        }

        final rawStorage = _storageEntries ?? [];
        var ordered = _sortFeaturedFirst(rawStorage);
        final list = _filterByAdmin(ordered);
        final forPublic = widget.adminConfig == null
            ? _applyTypeFilter(list, _typeFilter)
            : list;
        if (list.isEmpty) {
          _reportAdminVisiblePaths([]);
          final periodFilteredOut = widget.adminConfig != null &&
              rawStorage.isNotEmpty &&
              widget.adminConfig!.period != InstitutionalMediaPeriod.all;
          return _GalleryChrome(
            adminConfig: widget.adminConfig,
            showPublicFilters: widget.adminConfig == null,
            typeFilterChips: widget.adminConfig == null ? _buildTypeFilterChips() : null,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  periodFilteredOut
                      ? 'Nenhuma mídia neste período na varredura do Storage. '
                          'Ajuste o filtro ou confira se os ficheiros têm data no nome (ex.: 1730…_foto.jpg).'
                      : snap.hasError
                          ? 'Não foi possível carregar a lista da galeria agora. '
                              'As mídias em ${MarketingStorageLayout.storageRoot}/ no Storage '
                              'continuam disponíveis para o painel master.'
                          : 'Nenhuma mídia na galeria no momento. '
                              'No Firebase Storage, adicione imagens, vídeos ou PDFs em '
                              '${MarketingStorageLayout.storageRoot}/ (pastas videos, fotos ou pdf). '
                              'Opcionalmente ordene os itens no Firestore em '
                              '${MarketingStorageLayout.firestoreCollection}/'
                              '${MarketingStorageLayout.firestoreGalleryDocId}.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          );
        }
        if (forPublic.isEmpty && widget.adminConfig == null) {
          return _GalleryChrome(
            adminConfig: widget.adminConfig,
            showPublicFilters: true,
            typeFilterChips: _buildTypeFilterChips(),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nenhum item nesta categoria.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ),
            ],
          );
        }
        _reportAdminVisiblePaths(
            widget.adminConfig != null ? forPublic : const []);
        return _GalleryChrome(
          adminConfig: widget.adminConfig,
          showPublicFilters: widget.adminConfig == null,
          typeFilterChips: widget.adminConfig == null ? _buildTypeFilterChips() : null,
          children: [
            _buildMediaGrid(context, forPublic),
          ],
        );
      },
    );
  }
}

class _GalleryChrome extends StatelessWidget {
  final List<Widget> children;
  final InstitutionalMediaAdminConfig? adminConfig;
  final bool showPublicFilters;
  final Widget? typeFilterChips;

  const _GalleryChrome({
    required this.children,
    this.adminConfig,
    required this.showPublicFilters,
    this.typeFilterChips,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final cfg = adminConfig;
    final filterActive = cfg != null && cfg.period != InstitutionalMediaPeriod.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Galeria Gestão YAHWEH',
          style: TextStyle(
            fontSize: isMobile ? 19 : 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vídeos, imagens e PDFs — materiais de apoio e divulgação (CMS no Painel Master).',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Colors.grey.shade700,
          ),
        ),
        if (showPublicFilters && typeFilterChips != null) ...[
          const SizedBox(height: 14),
          typeFilterChips!,
        ],
        if (filterActive) ...[
          const SizedBox(height: 8),
          Text(
            'A mostrar só mídias no período selecionado (acima). Itens sem data no ficheiro ficam ocultos neste filtro.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        if (cfg != null && cfg.selectionMode && cfg.selectedPaths.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${cfg.selectedPaths.length} selecionado(s) na grelha — use o botão na barra acima para excluir.',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF15803D),
            ),
          ),
        ],
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class _MediaCard extends StatelessWidget {
  final _GalleryEntry entry;
  final InstitutionalMediaAdminConfig? adminConfig;
  final bool showMetaBelow;

  const _MediaCard({
    required this.entry,
    this.adminConfig,
    this.showMetaBelow = true,
  });

  static const Color _selGreen = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final cfg = adminConfig;
    final normPath =
        MarketingStorageLayout.normalizeObjectPath(entry.storagePath);
    final sel =
        cfg != null && cfg.selectedPaths.contains(normPath);
    final mediaBlock = Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            switch (entry.kind) {
              _GalleryKind.video => _VideoPosterCard(
                  path: entry.storagePath,
                  title: entry.title,
                  playUrl: entry.downloadUrl,
                ),
              _GalleryKind.image => _ImagePreview(
                  path: entry.storagePath,
                  imageUrl: entry.downloadUrl,
                  onOpenLightbox: () => _openImageLightbox(
                        context,
                        entry.storagePath,
                        entry.downloadUrl,
                      ),
                ),
              _GalleryKind.pdf => const _PdfHero(),
            },
          ],
        ),
        if (entry.featured && cfg == null)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(12),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 4),
                  Text(
                    'Destaque',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (cfg != null && cfg.selectionMode)
          Positioned(
            top: 8,
            left: 8,
            child: Material(
              color: Colors.white.withValues(alpha: 0.92),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 1,
              child: InkWell(
                onTap: () => cfg.onPathToggle(normPath),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    sel
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: sel ? _selGreen : Colors.grey.shade700,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: sel ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(
          color: sel ? _selGreen : const Color(0xFFE8ECF4),
          width: sel ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          mediaBlock,
          if (showMetaBelow)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.category.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        MarketingGalleryCms.categoryLabel(entry.category),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: const Color(0xFF1E5AA8),
                        ),
                      ),
                    ),
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.25,
                    ),
                  ),
                  if (entry.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (entry.kind == _GalleryKind.pdf)
                    FilledButton.icon(
                      onPressed: () => _openStoragePath(entry.storagePath),
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text('Baixar material'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E5AA8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  else if (entry.kind == _GalleryKind.image)
                    OutlinedButton.icon(
                      onPressed: () => _openImageLightbox(
                            context,
                            entry.storagePath,
                            entry.downloadUrl,
                          ),
                      icon: const Icon(Icons.fullscreen_rounded, size: 18),
                      label: const Text('Ver em tela cheia'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E5AA8),
                        side: const BorderSide(color: Color(0xFFBFDBFE)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  else
                    Text(
                      'Toque no vídeo para assistir',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> _openStoragePath(String path) async {
    try {
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      }
      final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
      final u = Uri.tryParse(url);
      if (u != null && await canLaunchUrl(u)) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('_openStoragePath: $e');
    }
  }

  static Future<void> _openImageLightbox(
    BuildContext context,
    String storagePath, [
    String? fallbackDownloadUrl,
  ]) async {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => _MarketingImageLightboxDialog(
            storagePath: storagePath,
            fallbackDownloadUrl: fallbackDownloadUrl,
          ),
    );
  }
}

/// Lightbox: bytes via Storage SDK (evita CORS/`Image.network` preso em loading no web).
class _MarketingImageLightboxDialog extends StatefulWidget {
  final String storagePath;
  final String? fallbackDownloadUrl;

  const _MarketingImageLightboxDialog({
    required this.storagePath,
    this.fallbackDownloadUrl,
  });

  @override
  State<_MarketingImageLightboxDialog> createState() =>
      _MarketingImageLightboxDialogState();
}

class _MarketingImageLightboxDialogState
    extends State<_MarketingImageLightboxDialog> {
  static const int _maxBytes = 18 * 1024 * 1024;
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List?> _load() async {
    try {
      final ref = FirebaseStorage.instance.ref(widget.storagePath);
      final b = await ref.getData(_maxBytes);
      if (b != null && b.isNotEmpty) return b;
    } catch (e) {
      debugPrint('_MarketingImageLightboxDialog Storage: $e');
    }
    final u = widget.fallbackDownloadUrl?.trim();
    if (u == null || u.isEmpty) return null;
    try {
      final resp = await http
          .get(Uri.parse(u))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200 &&
          resp.bodyBytes.isNotEmpty &&
          resp.bodyBytes.length <= _maxBytes) {
        return resp.bodyBytes;
      }
    } catch (e) {
      debugPrint('_MarketingImageLightboxDialog http: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FutureBuilder<Uint8List?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 280,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                );
              }
              final bytes = snap.data;
              if (bytes == null || bytes.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Não foi possível carregar a imagem.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: math.min(MediaQuery.sizeOf(context).width - 16, 920),
                  height: math.min(MediaQuery.sizeOf(context).height - 120, 720),
                  child: PhotoView(
                    imageProvider: MemoryImage(bytes),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2.5,
                    backgroundDecoration: const BoxDecoration(color: Colors.black),
                    loadingBuilder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPosterCard extends StatelessWidget {
  final String path;
  final String title;
  final String? playUrl;

  const _VideoPosterCard({
    required this.path,
    required this.title,
    this.playUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openVideoModal(context, path, title, playUrl),
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF312E81),
                          Color(0xFF5B21B6),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.play_circle_filled_rounded,
                      size: 68,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 28, 14, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.78),
                          ],
                        ),
                      ),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _openVideoModal(
    BuildContext context,
    String storagePath,
    String caption,
    String? playUrl,
  ) {
    final h = MediaQuery.sizeOf(context).height;
    final trimmed = playUrl?.trim() ?? '';
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: h * 0.88,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: PremiumInstitutionalVideoCard(
                videoUrl: trimmed.isNotEmpty ? trimmed : null,
                storagePath: trimmed.isEmpty ? storagePath : null,
                height: math.min(400, h * 0.42),
                caption: caption,
                hintBelow: null,
                heroAutoplay: false,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String path;
  final String? imageUrl;
  final VoidCallback onOpenLightbox;

  const _ImagePreview({
    required this.path,
    this.imageUrl,
    required this.onOpenLightbox,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenLightbox,
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: const Color(0xFFF1F5F9),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final h = c.maxHeight;
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    final mw = (w * dpr).round().clamp(64, 1600);
                    final mh = (h * dpr).round().clamp(64, 1600);
                    final shimmer = Shimmer.fromColors(
                      baseColor: const Color(0xFFE2E8F0),
                      highlightColor: const Color(0xFFF8FAFC),
                      child: Container(
                        width: w,
                        height: h,
                        color: Colors.white,
                      ),
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        StableStorageImage(
                          storagePath: path,
                          imageUrl: imageUrl,
                          width: w,
                          height: h,
                          fit: BoxFit.cover,
                          placeholder: shimmer,
                          errorWidget: const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40),
                          ),
                          memCacheWidth: mw,
                          memCacheHeight: mh,
                        ),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onOpenLightbox,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero PDF — ícone na cor de marca Yahweh (evita dependência pesada de miniatura).
class _PdfHero extends StatelessWidget {
  const _PdfHero();

  static const _brand = Color(0xFF1E5AA8);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _brand.withValues(alpha: 0.12),
                const Color(0xFFEFF6FF),
              ],
            ),
            border: Border.all(color: _brand.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf_rounded, size: 56, color: _brand),
              const SizedBox(height: 8),
              Text(
                'Documento PDF',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: _brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
