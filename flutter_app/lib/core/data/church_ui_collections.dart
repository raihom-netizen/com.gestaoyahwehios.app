import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Atalhos tipados para subcoleções — substitui `.collection()` nas telas.
abstract final class ChurchUiCollections {
  ChurchUiCollections._();

  static String _id([String? hint]) => ChurchRepository.churchId(hint ?? '');

  static DocumentReference<Map<String, dynamic>> churchDoc([String? hint]) =>
      ChurchFirestoreAccess.churchDoc(_id(hint));

  static CollectionReference<Map<String, dynamic>> ref(
    String sub, {
    String? churchIdHint,
  }) =>
      ChurchFirestoreAccess.collectionRef(_id(churchIdHint), sub);

  static CollectionReference<Map<String, dynamic>> membros([String? h]) =>
      ref(ChurchDataPaths.membros, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> departamentos([String? h]) =>
      ref(ChurchDataPaths.departamentos, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> cargos([String? h]) =>
      ref(ChurchDataPaths.cargos, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> eventos([String? h]) =>
      ref(ChurchDataPaths.eventos, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> avisos([String? h]) =>
      ref(ChurchDataPaths.avisos, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> chats([String? h]) =>
      ref(ChurchDataPaths.chats, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> patrimonio([String? h]) =>
      ref(ChurchDataPaths.patrimonio, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> financeiro([String? h]) =>
      ref(ChurchDataPaths.financeiro, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> financeLogs([String? h]) =>
      ref(ChurchDataPaths.financeLogs, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> financeMpNotifications(
          [String? h]) =>
      ref(ChurchDataPaths.financeMpNotifications, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> fornecedores([String? h]) =>
      ref(ChurchDataPaths.fornecedores, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> fornecedorCompromissos(
          [String? h]) =>
      ref(ChurchDataPaths.fornecedorCompromissos, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> escalas([String? h]) =>
      ref(ChurchDataPaths.escalas, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> escalaTemplates([String? h]) =>
      ref(ChurchDataPaths.escalaTemplates, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> agenda([String? h]) =>
      ref(ChurchDataPaths.agenda, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> lideres([String? h]) =>
      ref(ChurchDataPaths.lideres, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> administrativo([String? h]) =>
      ref(ChurchDataPaths.administrativo, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> doacoes([String? h]) =>
      ref(ChurchDataPaths.doacoes, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> mercadopago([String? h]) =>
      ref(ChurchDataPaths.mercadopago, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> cartoes([String? h]) =>
      ref(ChurchDataPaths.cartoes, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> certificados([String? h]) =>
      ref(ChurchDataPaths.certificados, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> certificadosHistorico(
          [String? h]) =>
      ref(ChurchDataPaths.certificadosHistorico, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> certificadosProtocolIndex(
          [String? h]) =>
      ref(ChurchDataPaths.certificadosProtocolIndex, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> pedidosOracao([String? h]) =>
      ref(ChurchDataPaths.pedidosOracao, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> transferencias([String? h]) =>
      ref(ChurchDataPaths.transferencias, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> cartasModelos([String? h]) =>
      ref(ChurchDataPaths.cartasModelos, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> visitantes([String? h]) =>
      ref('visitantes', churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> config([String? h]) =>
      ref(ChurchDataPaths.config, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> contas([String? h]) =>
      ref('contas', churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> despesasFixas([String? h]) =>
      ref('despesas_fixas', churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> eventTemplates([String? h]) =>
      ref('event_templates', churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> eventCategories([String? h]) =>
      ref('event_categories', churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> patrimonioInventarioHistorico([String? h]) =>
      ref(ChurchDataPaths.patrimonioInventarioHistorico, churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> usersIndex([String? h]) =>
      ref('usersIndex', churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> tenantUsers([String? h]) =>
      ref('users', churchIdHint: h);

  static CollectionReference<Map<String, dynamic>> subOf(
    DocumentReference<Map<String, dynamic>> parent,
    String sub,
  ) =>
      parent.collection(sub.trim());
}
