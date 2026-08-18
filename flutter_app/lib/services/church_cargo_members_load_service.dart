import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/models/blind_member_doc.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Membro vinculado a um cargo ? doc Firestore + dados normalizados.
class ChurchCargoMemberRow {
  const ChurchCargoMemberRow({
    required this.id,
    required this.data,
    required this.ref,
  });

  final String id;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> ref;

  String get displayName => BlindMemberDoc.fromFirestore(id: id, data: data)
      .displayName
      .trim();
}

class ChurchCargoMembersLoadResult {
  const ChurchCargoMembersLoadResult({
    required this.churchId,
    required this.members,
    required this.readSource,
    this.softError,
    this.fromCache = false,
  });

  final String churchId;
  final List<ChurchCargoMemberRow> members;
  final String readSource;
  final String? softError;
  final bool fromCache;
}

/// Carga estável de membros por cargo — `igrejas/{churchId}/membros`, cache-first.
abstract final class ChurchCargoMembersLoadService {
  ChurchCargoMembersLoadService._();

  static const int _kLimit = 500;

  static Duration get _queryCap => kIsWeb
      ? const Duration(seconds: 16)
      : ChurchPanelReadTimeouts.queryCap;

  static String _asciiLower(String raw) {
    var s = raw.toLowerCase().trim();
    const accents = {
      '\u00e1': 'a', '\u00e0': 'a', '\u00e3': 'a', '\u00e2': 'a', '\u00e4': 'a',
      '\u00e9': 'e', '\u00e8': 'e', '\u00ea': 'e', '\u00eb': 'e',
      '\u00ed': 'i', '\u00ec': 'i', '\u00ee': 'i', '\u00ef': 'i',
      '\u00f3': 'o', '\u00f2': 'o', '\u00f5': 'o', '\u00f4': 'o', '\u00f6': 'o',
      '\u00fa': 'u', '\u00f9': 'u', '\u00fb': 'u', '\u00fc': 'u',
      '\u00e7': 'c', '\u00f1': 'n',
    };
    for (final e in accents.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _slug(String raw) =>
      _asciiLower(raw).replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static String memberPrimaryCargoKey(Map<String, dynamic> d) {
    return (d['FUNCAO'] ??
            d['FUNCAO_PERMISSOES'] ??
            d['CARGO'] ??
            d['cargo'] ??
            d['funcao'] ??
            d['role'] ??
            '')
        .toString()
        .trim();
  }

  /// Compara chave/nome do cargo com campos do membro (FUNCOES + primário).
  static bool memberMatchesCargo(
    Map<String, dynamic> d, {
    required String cargoKey,
    required String cargoName,
  }) {
    final keyNorm = _asciiLower(cargoKey);
    final nameNorm = _asciiLower(cargoName);
    final keySlug = _slug(cargoKey);
    final nameSlug = _slug(cargoName);

    bool tokenMatches(String token) {
      if (token.isEmpty) return false;
      final t = _asciiLower(token);
      final tSlug = _slug(token);
      return t == keyNorm ||
          t == nameNorm ||
          tSlug == keySlug ||
          tSlug == nameSlug;
    }

    final funcoes = d['FUNCOES'] ?? d['funcoes'];
    if (funcoes is List) {
      for (final f in funcoes) {
        if (tokenMatches((f ?? '').toString())) return true;
      }
    }

    final primary = memberPrimaryCargoKey(d);
    return tokenMatches(primary);
  }

  static ChurchCargoMemberRow _rowFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = BlindMemberDoc.fromFirestore(id: doc.id, data: doc.data())
        .toMemberDataMap();
    return ChurchCargoMemberRow(id: doc.id, data: data, ref: doc.reference);
  }

  static List<ChurchCargoMemberRow> _filterDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String cargoKey,
    required String cargoName,
    String? onlyChurchId,
  }) {
    final seen = <String>{};
    final out = <ChurchCargoMemberRow>[];
    for (final doc in docs) {
      if (seen.contains(doc.id)) continue;
      if (onlyChurchId != null &&
          onlyChurchId.isNotEmpty &&
          !doc.reference.path.startsWith('igrejas/$onlyChurchId/')) {
        continue;
      }
      final raw = doc.data();
      if (!ChurchModuleFirestoreListRead.isActiveRecord(raw)) continue;
      if (!memberMatchesCargo(
        raw,
        cargoKey: cargoKey,
        cargoName: cargoName,
      )) {
        continue;
      }
      seen.add(doc.id);
      out.add(_rowFromDoc(doc));
    }
    out.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return out;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _queryArrayContains({
    required String churchId,
    required String token,
  }) async {
    final t = token.trim();
    if (t.isEmpty) return const [];
    final snap = await ChurchUiCollections.membros(churchId)
        .where('FUNCOES', arrayContains: t)
        .limit(_kLimit)
        .get();
    return snap.docs;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadAllMemberDocs({
    required String churchId,
    bool forceRefresh = false,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final loaded = await ChurchMembersLoadService.load(
      seedTenantId: churchId,
      limit: _kLimit,
      forceRefresh: forceRefresh,
      // Picker de cargo = igreja inteira (sem o teto de página de 50).
      fullList: true,
    ).timeout(_queryCap);

    if (loaded.docs.isNotEmpty) return loaded.docs;

    final ram = ChurchMembersLoadService.peekRamAny(churchId);
    if (ram != null && ram.isNotEmpty) return ram;

    return ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.membros(churchId),
      cacheKey: '${churchId.trim()}_cargo_members_$_kLimit',
      limit: _kLimit,
      sortDocs: (docs) => docs,
    );
  }

  static Future<ChurchCargoMembersLoadResult> loadLinked({
    required String seedTenantId,
    required String cargoKey,
    required String cargoName,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchCargoMembersLoadResult(
        churchId: '',
        members: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    String? softError;
    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    Future<void> mergeQuery(Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> q) async {
      try {
        final docs = await q.timeout(_queryCap);
        for (final d in docs) {
          merged[d.id] = d;
        }
      } catch (e) {
        softError ??= _humanize(e);
      }
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    await mergeQuery(
      _queryArrayContains(churchId: churchId, token: cargoKey),
    );
    final nameTrim = cargoName.trim();
    if (nameTrim.isNotEmpty && _asciiLower(nameTrim) != _asciiLower(cargoKey)) {
      await mergeQuery(
        _queryArrayContains(churchId: churchId, token: nameTrim),
      );
    }

    try {
      final all = await _loadAllMemberDocs(
        churchId: churchId,
        forceRefresh: forceRefresh,
      );
      for (final d in all) {
        merged.putIfAbsent(d.id, () => d);
      }
    } catch (e) {
      softError ??= _humanize(e);
    }

    final members = _filterDocs(
      merged.values,
      cargoKey: cargoKey,
      cargoName: cargoName,
      onlyChurchId: churchId,
    );

    return ChurchCargoMembersLoadResult(
      churchId: churchId,
      members: members,
      readSource: merged.isEmpty ? 'empty' : 'cargo_members_merged',
      softError: members.isEmpty ? softError : null,
      fromCache: !forceRefresh,
    );
  }

  static Future<ChurchCargoMembersLoadResult> loadAllForPicker({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchCargoMembersLoadResult(
        churchId: '',
        members: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    String? softError;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = const [];
    try {
      docs = await _loadAllMemberDocs(
        churchId: churchId,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      softError = _humanize(e);
    }

    final seen = <String>{};
    final rows = <ChurchCargoMemberRow>[];
    for (final doc in docs) {
      if (seen.contains(doc.id)) continue;
      if (!ChurchModuleFirestoreListRead.isActiveRecord(doc.data())) continue;
      seen.add(doc.id);
      rows.add(_rowFromDoc(doc));
    }
    rows.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    return ChurchCargoMembersLoadResult(
      churchId: churchId,
      members: rows,
      readSource: 'all_members',
      softError: softError,
      fromCache: !forceRefresh,
    );
  }

  static String? _humanize(Object e) {
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar membros. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}?';
    return s;
  }
}
