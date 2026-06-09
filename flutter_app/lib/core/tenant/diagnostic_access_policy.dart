/// Quem pode ver telas de diagnóstico técnico (DEBUG CHURCH, paths Firestore, etc.).
abstract final class DiagnosticAccessPolicy {
  DiagnosticAccessPolicy._();

  /// Painel Master — `adm`, `admin`, `master`.
  static bool isMasterDiagnosticRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'master';
  }
}
