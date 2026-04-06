import 'package:cloud_firestore/cloud_firestore.dart';

/// Caminhos da frota (Jim Sabores) no Firestore — **tudo sob a igreja**.
///
/// Padrão: [defaultTenantId] (Brasil para Cristo Jardim Goiano). Pode mudar via
/// `--dart-define=FROTA_TENANT_ID=outro_id` em builds dedicados.
abstract final class FrotaFirestorePaths {
  FrotaFirestorePaths._();

  static const String defaultTenantId = String.fromEnvironment(
    'FROTA_TENANT_ID',
    defaultValue: 'igreja_o_brasil_para_cristo_jardim_goiano',
  );

  static DocumentReference<Map<String, dynamic>> igrejaDoc([
    String? tenantId,
  ]) {
    final tid = (tenantId ?? defaultTenantId).trim();
    return FirebaseFirestore.instance.collection('igrejas').doc(tid);
  }

  static CollectionReference<Map<String, dynamic>> abastecimentos([
    String? tenantId,
  ]) =>
      igrejaDoc(tenantId).collection('abastecimentos');

  static CollectionReference<Map<String, dynamic>> combustiveis([
    String? tenantId,
  ]) =>
      igrejaDoc(tenantId).collection('combustiveis');

  static CollectionReference<Map<String, dynamic>> veiculos([
    String? tenantId,
  ]) =>
      igrejaDoc(tenantId).collection('veiculos');
}
