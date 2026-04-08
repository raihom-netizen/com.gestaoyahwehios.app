import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/department_template.dart';
import 'package:gestao_yahweh/services/church_departments_presets_data.dart';

/// Presets padrão — preenche docs faltantes em `igrejas/{id}/departamentos`.
class ChurchDepartmentsBootstrap {
  ChurchDepartmentsBootstrap._();

  /// Uma entrada por rótulo (evita Crianças/Louvor duplicados por keys legadas em inglês).
  static const _legacyKeys = {'kids', 'men', 'women', 'welcome', 'youth', 'worship', 'prayer'};

  static List<Map<String, dynamic>> get _presetsSorted {
    final byLabel = <String, Map<String, dynamic>>{};
    for (final e in kChurchDepartmentPresetRows) {
      final label = ((e['label'] as String).trim()).toLowerCase();
      final key = e['key'] as String;
      final cur = byLabel[label];
      if (cur == null) {
        byLabel[label] = e;
        continue;
      }
      final curKey = cur['key'] as String;
      final curLegacy = _legacyKeys.contains(curKey);
      final newLegacy = _legacyKeys.contains(key);
      if (curLegacy && !newLegacy) {
        byLabel[label] = e;
      } else if (curLegacy == newLegacy && !newLegacy && key.compareTo(curKey) < 0) {
        byLabel[label] = e;
      }
    }
    final list = byLabel.values.toList();
    list.sort((a, b) => (a['label'] as String).toLowerCase().compareTo((b['label'] as String).toLowerCase()));
    return list;
  }

  /// Quantidade de presets únicos (por nome) usada nas mensagens da UI.
  static int get uniquePresetCount => _presetsSorted.length;

  /// Itens do kit de boas-vindas (11 departamentos base).
  static int get welcomeKitCount => kDepartmentWelcomeKit.length;

  /// Lista ordenada para exibir sugestões na UI quando o Firestore ainda está vazio.
  static List<Map<String, dynamic>> get presetsSorted =>
      List<Map<String, dynamic>>.unmodifiable(_presetsSorted);

  /// Cria só o [kDepartmentWelcomeKit] quando a subcoleção está **completamente vazia**.
  /// Não substitui o catálogo completo ([ensureMissingPresetDocuments]).
  static Future<bool> ensureWelcomeKitDocuments(
    CollectionReference<Map<String, dynamic>> col, {
    bool refreshToken = false,
    void Function(Object error)? onError,
  }) async {
    try {
      if (refreshToken) {
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
      }
      // Cache primeiro (abertura do módulo); confirma no servidor só se parecer vazio.
      var snap = await col.get(GetOptions(source: Source.serverAndCache));
      if (snap.docs.isNotEmpty) return false;
      snap = await col.get(GetOptions(source: Source.server));
      if (snap.docs.isNotEmpty) return false;
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();
      for (final t in kDepartmentWelcomeKit) {
        batch.set(col.doc(t.docId), t.toFirestoreMap(now));
      }
      await batch.commit();
      debugPrint(
          'ChurchDepartmentsBootstrap: kit de boas-vindas (${kDepartmentWelcomeKit.length} deptos).');
      return true;
    } catch (e) {
      debugPrint('ChurchDepartmentsBootstrap.ensureWelcomeKit: $e');
      onError?.call(e);
    }
    return false;
  }

  /// Cria documentos de preset cujo [id] ainda não existe.
  /// [onError] — ex.: exibir SnackBar quando [permission-denied] (regras Firestore desatualizadas ou papel sem escrita).
  static Future<bool> ensureMissingPresetDocuments(
    CollectionReference<Map<String, dynamic>> col, {
    bool refreshToken = false,
    void Function(Object error)? onError,
  }) async {
    try {
      if (refreshToken) {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
      }
      final snap = await col.get(GetOptions(source: Source.server));
      final existingIds = snap.docs.map((d) => d.id).toSet();
      final now = Timestamp.now();
      const maxBatch = 450;
      final toCreate = <Map<String, dynamic>>[];
      for (final e in _presetsSorted) {
        final key = e['key'] as String;
        if (existingIds.contains(key)) continue;
        toCreate.add(e);
      }
      for (var i = 0; i < toCreate.length; i += maxBatch) {
        final end = min(i + maxBatch, toCreate.length);
        final chunk = toCreate.sublist(i, end);
        final batch = FirebaseFirestore.instance.batch();
        for (final e in chunk) {
          final key = e['key'] as String;
          final label = e['label'] as String;
          final c1 = e['c1'] as int;
          final c2 = e['c2'] as int;
          final visualKey = (e['iconKey'] ?? e['key'] ?? 'pastoral').toString();
          final desc = (e['description'] ?? '').toString();
          batch.set(col.doc(key), <String, dynamic>{
            'name': label,
            'description': desc,
            'iconKey': visualKey,
            'themeKey': visualKey,
            'bgColor1': c1,
            'bgColor2': c2,
            'bgImageUrl': '',
            'leaderCpfs': <String>[],
            'leaderCpf': '',
            'viceLeaderCpf': '',
            'leaderUid': '',
            'permissions': <String>[],
            'createdAt': now,
            'updatedAt': now,
            'active': true,
            'isDefaultPreset': true,
          });
        }
        await batch.commit();
      }
      if (toCreate.isNotEmpty) {
        debugPrint('ChurchDepartmentsBootstrap: criados ${toCreate.length} departamento(s) do preset.');
        return true;
      }
    } catch (e) {
      debugPrint('ChurchDepartmentsBootstrap: $e');
      onError?.call(e);
    }
    return false;
  }

  /// Docs criados só com id (ex.: [ens_professores]) sem [name]/[iconKey]: completa a partir do preset.
  /// Merge — não apaga campos já preenchidos pelo gestor.
  static Future<int> backfillPresetMetadataWhereMissing(
    CollectionReference<Map<String, dynamic>> col, {
    bool refreshToken = false,
  }) async {
    try {
      if (refreshToken) {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
      }
      final presetByKey = <String, Map<String, dynamic>>{};
      for (final e in _presetsSorted) {
        presetByKey[e['key'] as String] = e;
      }
      final snap = await col.get(const GetOptions(source: Source.server));
      final now = Timestamp.now();
      var patched = 0;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        final key = d.id;
        final preset = presetByKey[key];
        if (preset == null) continue;
        final data = d.data();
        final name =
            (data['name'] ?? data['nome'] ?? data['NOME'] ?? '').toString().trim();
        final iconKey = (data['iconKey'] ?? '').toString().trim();
        if (name.isNotEmpty && iconKey.isNotEmpty) continue;
        final label = preset['label'] as String;
        final c1 = preset['c1'] as int;
        final c2 = preset['c2'] as int;
        final visualKey =
            (preset['iconKey'] ?? preset['key'] ?? 'pastoral').toString();
        final desc = (preset['description'] ?? '').toString();
        final patch = <String, dynamic>{'updatedAt': now};
        if (name.isEmpty) patch['name'] = label;
        if (iconKey.isEmpty) patch['iconKey'] = visualKey;
        if ((data['themeKey'] ?? '').toString().trim().isEmpty) {
          patch['themeKey'] = visualKey;
        }
        if (data['bgColor1'] == null) patch['bgColor1'] = c1;
        if (data['bgColor2'] == null) patch['bgColor2'] = c2;
        if ((data['description'] ?? '').toString().trim().isEmpty &&
            desc.isNotEmpty) {
          patch['description'] = desc;
        }
        if (data['active'] == null && data['ativo'] == null) {
          patch['active'] = true;
        }
        batch.set(col.doc(key), patch, SetOptions(merge: true));
        patched++;
      }
      if (patched > 0) {
        await batch.commit();
        debugPrint(
            'ChurchDepartmentsBootstrap: backfill em $patched departamento(s).');
      }
      return patched;
    } catch (e) {
      debugPrint('ChurchDepartmentsBootstrap.backfillPresetMetadata: $e');
    }
    return 0;
  }
}
