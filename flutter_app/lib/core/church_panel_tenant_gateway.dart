import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/church_panel_paths.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';

/// Porta única de tenant no **painel igreja** pós-login.
///
/// **Usar em todo módulo** (Membros, Financeiro, Chat, Certificados, etc.):
/// - `ChurchPanelTenantGateway.churchId(shellHint)` → `igreja_o_brasil_para_cristo_jardim_goiano`
/// - `ChurchPanelTenantGateway.firestoreRoot(hint)` → `igrejas/{churchId}`
/// - `ChurchPanelTenantGateway.membros(hint)` → coleção canónica do módulo
///
/// **Proibido no painel:** `TenantResolverService.resolveOperationalChurchDocId`,
/// `collection('tenants')`, `church_aliases`, paths Storage soltos.
abstract final class ChurchPanelTenantGateway {
  ChurchPanelTenantGateway._();

  /// ID canónico síncrono — sessão bound → hint do shell (slug BPC mapeado).
  static String churchId([String? shellHint]) =>
      ChurchRepository.churchId(shellHint);

  static String requireChurchId([String? shellHint]) =>
      ChurchRepository.requireChurchId(shellHint);

  static String resolve(String? tenantHint) =>
      ChurchPanelTenant.resolve(tenantHint);

  static String forFirestore(String? tenantHint) =>
      ChurchPanelTenant.forFirestore(tenantHint);

  /// `igrejas/{churchId}` — Firestore.
  static String firestoreRoot([String? shellHint]) =>
      ChurchPanelPaths.firestoreRoot(shellHint);

  /// `igrejas/{churchId}/` — Storage.
  static String storageRoot([String? shellHint]) =>
      ChurchPanelPaths.storageRoot(shellHint);

  static String storagePath(String relative, [String? shellHint]) {
    final root = storageRoot(shellHint);
    if (root.isEmpty) return relative.trim();
    final rel = relative.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    return rel.isEmpty ? root : '$root$rel';
  }

  static String storageFolder(String folder, [String? shellHint]) {
    final root = storageRoot(shellHint);
    if (root.isEmpty) return folder.trim();
    return '$root/${folder.trim()}';
  }

  static DocumentReference<Map<String, dynamic>> churchDoc([String? h]) =>
      ChurchPanelPaths.churchDoc(h);

  // ─── Módulos Firestore (delegação única) ─────────────────────────────────

  static CollectionReference<Map<String, dynamic>> membros([String? h]) =>
      ChurchPanelPaths.membros(h);

  static CollectionReference<Map<String, dynamic>> departamentos([String? h]) =>
      ChurchPanelPaths.departamentos(h);

  static CollectionReference<Map<String, dynamic>> cargos([String? h]) =>
      ChurchPanelPaths.cargos(h);

  static CollectionReference<Map<String, dynamic>> eventos([String? h]) =>
      ChurchPanelPaths.eventos(h);

  static CollectionReference<Map<String, dynamic>> avisos([String? h]) =>
      ChurchUiCollections.avisos(h);

  static CollectionReference<Map<String, dynamic>> chats([String? h]) =>
      ChurchUiCollections.chats(h);

  static CollectionReference<Map<String, dynamic>> certificados([String? h]) =>
      ChurchUiCollections.certificados(h);

  static CollectionReference<Map<String, dynamic>> patrimonio([String? h]) =>
      ChurchPanelPaths.patrimonio(h);

  static CollectionReference<Map<String, dynamic>> financeiro([String? h]) =>
      ChurchPanelPaths.financeiro(h);

  static CollectionReference<Map<String, dynamic>> escalas([String? h]) =>
      ChurchPanelPaths.escalas(h);

  static CollectionReference<Map<String, dynamic>> agenda([String? h]) =>
      ChurchPanelPaths.agenda(h);

  static CollectionReference<Map<String, dynamic>> visitantes([String? h]) =>
      ChurchPanelPaths.visitantes(h);

  static CollectionReference<Map<String, dynamic>> pedidosOracao([String? h]) =>
      ChurchPanelPaths.pedidosOracao(h);

  /// Subpath textual — ex.: `membros`, `departamentos`.
  static String subcollectionPath(String sub, [String? h]) =>
      ChurchDataPaths.subcollection(churchId(h), sub);
}
