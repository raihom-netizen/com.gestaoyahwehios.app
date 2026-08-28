import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/cache/tenant_deleted_doc_tombstones.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show eventTemplateCoverStoragePathFallbacks;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/panel_programacao_loader.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Resultado da exclusão — para a UI dizer ao utilizador o que saiu.
class ChurchEventTemplateDeleteResult {
  const ChurchEventTemplateDeleteResult({
    required this.templates,
    required this.eventos,
    required this.agenda,
  });

  final int templates;
  final int eventos;
  final int agenda;

  int get total => templates + eventos + agenda;
}

/// Exclusão **completa** de eventos fixos (`event_templates`).
///
/// Apagar só o documento do template deixava para trás tudo o que ele tinha
/// gerado, e por isso o evento «voltava»:
///
/// 1. **Eventos gerados** — «Gerar eventos futuros» cria um doc em `eventos`
///    por data (`templateId` + `generated: true`). Órfãos, continuavam a ser
///    lidos pelo Feed, pelo painel inicial e pelo site público.
/// 2. **Compromissos de agenda** — a mesma geração cria um doc em `agenda`
///    por data, com o mesmo `templateId`.
/// 3. **Cache em disco (Hive)** — a leitura é stale-while-revalidate: sem
///    remover o id do Hive, a lista voltava a pintar o registo apagado em
///    cada abertura da app, durante os 30 dias de TTL. E como o Hive nunca é
///    limpo por uma resposta vazia da rede (um vazio pode ser falha
///    temporária), apagar o último evento fixo nunca limpava nada.
/// 4. **Capa no Storage** — ficava a ocupar espaço no bucket sem nada a
///    referenciá-la.
abstract final class ChurchEventTemplateDeleteService {
  ChurchEventTemplateDeleteService._();

  /// Firestore limita 500 operações por batch — margem para segurança.
  static const int _chunkSize = 400;

  /// `whereIn` aceita no máximo 30 valores.
  static const int _whereInLimit = 30;

  static Future<ChurchEventTemplateDeleteResult> deleteTemplates({
    required String tenantId,
    required List<String> templateIds,
  }) async {
    final tid = ChurchRepository.churchId(tenantId);
    final ids = templateIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (tid.isEmpty || ids.isEmpty) {
      return const ChurchEventTemplateDeleteResult(
        templates: 0,
        eventos: 0,
        agenda: 0,
      );
    }

    // Lápides antes de tocar no servidor: fecham a corrida com um refresh em
    // background que já esteja a decorrer.
    TenantDeletedDocTombstones.mark(tid, 'event_templates', ids);

    final church = ChurchUiCollections.churchDoc(tid);
    final generatedEventos = await _docsByTemplateIds(
      church.collection('eventos'),
      ids,
    );
    final generatedAgenda = await _docsByTemplateIds(
      church.collection('agenda'),
      ids,
    );

    final refs = <DocumentReference<Map<String, dynamic>>>[
      for (final id in ids) church.collection('event_templates').doc(id),
      ...generatedEventos,
      ...generatedAgenda,
    ];

    for (var i = 0; i < refs.length; i += _chunkSize) {
      final batch = YahwehBatch();
      final end = i + _chunkSize > refs.length ? refs.length : i + _chunkSize;
      for (final r in refs.sublist(i, end)) {
        batch.deleteDoc(r);
      }
      await batch.commit();
    }

    // Só depois de o Firestore confirmar: se o commit rebentar, o chamador
    // desfaz as lápides e nada foi apagado do bucket nem dos caches.
    if (generatedEventos.isNotEmpty) {
      TenantDeletedDocTombstones.mark(
        tid,
        'eventos',
        generatedEventos.map((r) => r.id),
      );
    }
    if (generatedAgenda.isNotEmpty) {
      TenantDeletedDocTombstones.mark(
        tid,
        'agenda',
        generatedAgenda.map((r) => r.id),
      );
    }

    await _forgetCaches(
      tenantId: tid,
      templateIds: ids,
      eventoIds: generatedEventos.map((r) => r.id).toList(),
      agendaIds: generatedAgenda.map((r) => r.id).toList(),
    );

    // Capas no bucket — best-effort: o registo já saiu do Firestore, e falhar
    // aqui não pode transformar uma exclusão bem-sucedida em erro.
    unawaited(_deleteCovers(tid, ids));

    return ChurchEventTemplateDeleteResult(
      templates: ids.length,
      eventos: generatedEventos.length,
      agenda: generatedAgenda.length,
    );
  }

  /// Quantos eventos e compromissos de agenda saem junto com [templateIds].
  ///
  /// Serve para o diálogo de confirmação dizer ao utilizador o que vai
  /// desaparecer do Feed, do painel e do site — não para decidir a exclusão.
  static Future<({int eventos, int agenda})> countGenerated({
    required String tenantId,
    required List<String> templateIds,
  }) async {
    final tid = ChurchRepository.churchId(tenantId);
    final ids = templateIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (tid.isEmpty || ids.isEmpty) return (eventos: 0, agenda: 0);
    final church = ChurchUiCollections.churchDoc(tid);
    final eventos = await _docsByTemplateIds(
      church.collection('eventos'),
      ids,
    );
    final agenda = await _docsByTemplateIds(church.collection('agenda'), ids);
    return (eventos: eventos.length, agenda: agenda.length);
  }

  /// Desfaz as lápides quando o commit falhou (nada foi apagado).
  static void unmarkTombstones(String tenantId, List<String> templateIds) {
    final tid = ChurchRepository.churchId(tenantId);
    for (final id in templateIds) {
      TenantDeletedDocTombstones.unmark(tid, 'event_templates', id);
    }
  }

  static Future<List<DocumentReference<Map<String, dynamic>>>>
  _docsByTemplateIds(
    CollectionReference<Map<String, dynamic>> col,
    List<String> templateIds,
  ) async {
    final out = <DocumentReference<Map<String, dynamic>>>[];
    for (var i = 0; i < templateIds.length; i += _whereInLimit) {
      final end = i + _whereInLimit > templateIds.length
          ? templateIds.length
          : i + _whereInLimit;
      final chunk = templateIds.sublist(i, end);
      try {
        final snap = await col.where('templateId', whereIn: chunk).get();
        out.addAll(snap.docs.map((d) => d.reference));
      } catch (e) {
        // Índice em falta / offline: não apagar às cegas. O template sai à
        // mesma e o utilizador pode repetir — melhor deixar um órfão do que
        // apagar o que não era para apagar.
        if (kDebugMode) {
          debugPrint('event_template_delete_query_falhou (${col.path}): $e');
        }
      }
    }
    return out;
  }

  static Future<void> _forgetCaches({
    required String tenantId,
    required List<String> templateIds,
    required List<String> eventoIds,
    required List<String> agendaIds,
  }) async {
    // Os templates vivem no módulo `agenda` do cache Hive — ver
    // ChurchTenantResilientReads.eventTemplates.
    await TenantModuleHiveCache.removeDocIds(
      tenantId,
      TenantModuleKeys.agenda,
      [...templateIds, ...agendaIds],
    );
    if (eventoIds.isNotEmpty) {
      await TenantModuleHiveCache.removeDocIds(
        tenantId,
        TenantModuleKeys.eventos,
        eventoIds,
      );
    }
    await PanelProgramacaoLoader.clear(tenantId);
    FirestoreReadResilience.forgetKeysWithPrefix('${tenantId}_event_templates');
    FirestoreReadResilience.forgetKeysWithPrefix('${tenantId}_noticias');
    FirestoreReadResilience.forgetKeysWithPrefix('${tenantId}_eventos');
    FirestoreReadResilience.forgetKeysWithPrefix('${tenantId}_agenda');
  }

  static Future<void> _deleteCovers(
    String tenantId,
    List<String> templateIds,
  ) async {
    final paths = <String>[];
    for (final id in templateIds) {
      paths.addAll(
        eventTemplateCoverStoragePathFallbacks(
          churchId: tenantId,
          templateId: id,
        ),
      );
    }
    if (paths.isEmpty) return;
    try {
      await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(paths);
    } catch (e) {
      if (kDebugMode) debugPrint('event_template_cover_delete_falhou: $e');
    }
  }
}
