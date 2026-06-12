import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Categorias do património — canónicas + extras por igreja (`config/patrimonio`).
abstract final class PatrimonioCategoriaService {
  PatrimonioCategoriaService._();

  static const List<String> categoriasCanon = [
    'Som',
    'Móveis',
    'Instrumentos',
    'Imóveis',
    'Veículo',
    'Eletrônico',
    'Equipamento',
    'Outro',
  ];

  static const Map<String, String> _legadoParaCanon = {
    'móvel': 'Móveis',
    'imóvel': 'Imóveis',
    'instrumento musical': 'Instrumentos',
    'som e mídia': 'Som',
    'equipamentos': 'Equipamento',
    'eletrônicos': 'Eletrônico',
  };

  static String normalizar(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Outro';
    return _legadoParaCanon[t.toLowerCase()] ?? t;
  }

  /// Lista para filtros e formulário — canónicas + extras, sem duplicar legado.
  static List<String> mergeExtras(dynamic categoriasExtras) {
    final map = <String, String>{};
    for (final c in categoriasCanon) {
      final n = normalizar(c);
      map[n.toLowerCase()] = n;
    }
    if (categoriasExtras is List) {
      for (final e in categoriasExtras) {
        final n = normalizar(e.toString());
        if (n.isEmpty) continue;
        map.putIfAbsent(n.toLowerCase(), () => n);
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  static String _resolve(String hint) => ChurchPanelTenant.resolve(hint.trim());

  static Future<List<String>> loadCategorias(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return List<String>.from(categoriasCanon);
    try {
      final snap = await ChurchTenantResilientReads.patrimonioConfig(churchId);
      return mergeExtras(snap.data()?['categoriasExtras']);
    } catch (_) {
      return List<String>.from(categoriasCanon);
    }
  }

  /// Grava categoria extra — web-safe (`prepareForCriticalWrite` + retry).
  static Future<void> addCategoria({
    required String seedTenantId,
    required String nome,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      throw StateError('Igreja não identificada.');
    }
    final label = normalizar(nome);
    if (label.isEmpty) {
      throw ArgumentError('Informe o nome da categoria.');
    }

    await FirestoreWebGuard.prepareForCriticalWrite();
    await FirestoreWebGuard.runWithWebRecovery(
      () async {
        await ChurchUiCollections.config(churchId).doc('patrimonio').set(
          {
            'categoriasExtras': FieldValue.arrayUnion([label]),
            'atualizadoEm': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      },
      maxAttempts: 4,
    );
  }
}
