import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Site público consolidado — `igrejas/{tid}/_panel_cache/public_site`.
class PanelPublicSiteSnapshot {
  const PanelPublicSiteSnapshot({
    this.churchName = '',
    this.churchSlug = '',
    this.sitePublicoUrl = '',
    this.churchLogoUrl,
    this.prefetchUrls = const [],
    this.publicAvisosCount = 0,
    this.publicEventosCount = 0,
    this.feedPreview = const [],
    this.feedData = const [],
    this.updatedAt,
  });

  final String churchName;
  final String churchSlug;
  final String sitePublicoUrl;
  final String? churchLogoUrl;
  final List<String> prefetchUrls;
  final int publicAvisosCount;
  final int publicEventosCount;
  final List<Map<String, dynamic>> feedPreview;
  final List<Map<String, dynamic>> feedData;
  final Timestamp? updatedAt;

  bool get hasData =>
      feedData.isNotEmpty ||
      feedPreview.isNotEmpty ||
      (churchLogoUrl ?? '').isNotEmpty ||
      updatedAt != null;

  factory PanelPublicSiteSnapshot.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const PanelPublicSiteSnapshot();
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    List<Map<String, dynamic>> maps(dynamic v, {int max = 50}) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .take(max)
          .toList();
    }

    final urls = <String>[];
    final list = raw['prefetchUrls'];
    if (list is List) {
      for (final e in list) {
        final s = (e ?? '').toString().trim();
        if (s.startsWith('http')) urls.add(s);
      }
    }

    final logo = (raw['churchLogoUrl'] ?? '').toString().trim();
    final preview = maps(raw['feedPreview'], max: 12);
    final data = maps(raw['data'], max: 50);

    return PanelPublicSiteSnapshot(
      churchName: (raw['churchName'] ?? '').toString(),
      churchSlug: (raw['churchSlug'] ?? '').toString(),
      sitePublicoUrl: (raw['sitePublicoUrl'] ?? '').toString(),
      churchLogoUrl: logo.isEmpty ? null : logo,
      prefetchUrls: urls,
      publicAvisosCount: n(raw['publicAvisosCount']),
      publicEventosCount: n(raw['publicEventosCount']),
      feedPreview: preview,
      feedData: data.isNotEmpty ? data : preview,
      updatedAt:
          raw['updatedAt'] is Timestamp ? raw['updatedAt'] as Timestamp : null,
    );
  }

  /// Compatível com leitores de `_performance_cache/public_feed`.
  Map<String, dynamic> toLegacyPublicFeedMap() {
    return <String, dynamic>{
      if (churchLogoUrl != null) 'churchLogoUrl': churchLogoUrl,
      'prefetchUrls': prefetchUrls,
      'data': feedData,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }
}

abstract final class PanelPublicSiteSnapshotService {
  PanelPublicSiteSnapshotService._();

  static DocumentReference<Map<String, dynamic>> ref(String tenantId) {
    final id = ChurchRepository.churchId(tenantId.trim());
    return ChurchRepository.churchDoc(id.isNotEmpty ? id : tenantId.trim())
        .collection('_panel_cache')
        .doc('public_site');
  }

  static Future<PanelPublicSiteSnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const PanelPublicSiteSnapshot();
    try {
      final snap = await ref(tid).get(
        const GetOptions(source: Source.serverAndCache),
      );
      final parsed = PanelPublicSiteSnapshot.fromMap(snap.data());
      if (parsed.hasData) return parsed;
    } catch (_) {}
    try {
      final snap = await ref(tid).get();
      return PanelPublicSiteSnapshot.fromMap(snap.data());
    } catch (_) {
      return const PanelPublicSiteSnapshot();
    }
  }

  static Stream<PanelPublicSiteSnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return Stream.value(const PanelPublicSiteSnapshot());
    }
    return ref(tid).watchSafe().map(
          (snap) => PanelPublicSiteSnapshot.fromMap(snap.data()),
        );
  }
}
