/// Campos canónicos de tenant em documentos Firestore — `igrejas/{churchId}/…`.
abstract final class ChurchTenantFields {
  ChurchTenantFields._();

  /// Garante `churchId` e `tenantId` alinhados ao doc raiz da igreja.
  static Map<String, dynamic> stamp(
    String churchId,
    Map<String, dynamic> data,
  ) {
    final id = churchId.trim();
    if (id.isEmpty) return data;
    return {
      ...data,
      'churchId': id,
      'tenantId': id,
    };
  }
}
