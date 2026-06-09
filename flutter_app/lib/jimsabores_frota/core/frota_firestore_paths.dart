import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Caminhos da frota (Jim Sabores) no Firestore — **tudo sob a igreja**.
///
/// `churchId` vem de [ChurchContext.currentChurchId] ou parâmetro explícito.
/// Build dedicado: `--dart-define=FROTA_TENANT_ID=outro_id`.
abstract final class FrotaFirestorePaths {
  FrotaFirestorePaths._();

  static const String _envTenantId = String.fromEnvironment(
    'FROTA_TENANT_ID',
    defaultValue: '',
  );

  static String resolveTenantId([String? tenantId]) {
    final fromCtx = ChurchContext.currentChurchId;
    if (fromCtx != null && fromCtx.isNotEmpty) return fromCtx;
    final explicit = (tenantId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final env = _envTenantId.trim();
    if (env.isNotEmpty) return env;
    throw StateError(
      'Frota: churchId não definido — abra o painel da igreja ou passe tenantId.',
    );
  }

  static DocumentReference<Map<String, dynamic>> igrejaDoc([
    String? tenantId,
  ]) {
    final tid = resolveTenantId(tenantId);
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
