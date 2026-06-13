import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';

/// Membro elegível como signatário oficial (pastor, gestor, secretário, etc.).
class ChurchSignatoryEntry {
  const ChurchSignatoryEntry({
    required this.memberId,
    required this.nome,
    required this.cargo,
    this.cpfDigits,
    this.assinaturaUrl,
  });

  final String memberId;
  final String nome;
  final String cargo;
  final String? cpfDigits;
  final String? assinaturaUrl;

  factory ChurchSignatoryEntry.fromMemberDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final nome =
        (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? '').toString().trim();
    final cpf = (d['CPF'] ?? d['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final url =
        (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
    final path =
        (d['assinaturaStoragePath'] ?? '').toString().trim();
    return ChurchSignatoryEntry(
      memberId: doc.id,
      nome: nome,
      cargo: signatoryCargoDisplayLabel(d),
      cpfDigits: cpf.length == 11 ? cpf : null,
      assinaturaUrl: url.isNotEmpty ? url : (path.isNotEmpty ? path : null),
    );
  }
}

/// Carga de signatários — `igrejas/{churchId}/membros` filtrado por liderança.
abstract final class ChurchSignatoryLoadService {
  ChurchSignatoryLoadService._();

  static const List<String> _roleQueryKeys = [
    'gestor',
    'pastor',
    'pastora',
    'secretario',
    'secretaria',
    'tesoureiro',
    'tesouraria',
    'administrador',
    'adm',
    'lider_departamento',
    'lider_de_departamento',
  ];

  static const int _queryLimit = YahwehPerformanceV4.memberCardSignatoryQueryLimit;

  /// Apenas pastor, gestor, secretário, tesoureiro, administrador ou líder de departamento.
  static Future<List<ChurchSignatoryEntry>> loadEligible({
    required String seedTenantId,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) return const [];

    final col = ChurchUiCollections.membros(churchId);
    final byId = <String, ChurchSignatoryEntry>{};
    final seenCpfs = <String>{};

    void absorbDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      if (byId.containsKey(doc.id)) return;
      final d = doc.data();
      if (!memberCanSignChurchDocuments(d)) return;
      final entry = ChurchSignatoryEntry.fromMemberDoc(doc);
      if (entry.nome.isEmpty) return;
      if (entry.cpfDigits != null) {
        if (seenCpfs.contains(entry.cpfDigits)) return;
        seenCpfs.add(entry.cpfDigits!);
      }
      byId[doc.id] = entry;
    }

    await Future.wait(
      _roleQueryKeys.map((role) async {
        try {
          final snap = await col
              .where('FUNCOES', arrayContains: role)
              .limit(_queryLimit)
              .get();
          for (final doc in snap.docs) {
            absorbDoc(doc);
          }
        } catch (_) {}
        try {
          final snap = await col
              .where('FUNCAO', isEqualTo: role)
              .limit(_queryLimit)
              .get();
          for (final doc in snap.docs) {
            absorbDoc(doc);
          }
        } catch (_) {}
      }),
    );

    try {
      final flagged = await col
          .where('certificadoSignatario', isEqualTo: true)
          .limit(_queryLimit)
          .get();
      for (final doc in flagged.docs) {
        absorbDoc(doc);
      }
    } catch (_) {}

    final list = byId.values.toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return list;
  }

  /// Filtra documentos de membros já carregados (certificados em lote, etc.).
  static List<QueryDocumentSnapshot<Map<String, dynamic>>>
      filterEligibleMemberDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seenCpfs = <String>{};
    for (final doc in docs) {
      final d = doc.data();
      if (!memberCanSignChurchDocuments(d)) continue;
      final nome =
          (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final cpf =
          (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (cpf.length == 11) {
        if (seenCpfs.contains(cpf)) continue;
        seenCpfs.add(cpf);
      }
      out.add(doc);
    }
    return out;
  }
}
