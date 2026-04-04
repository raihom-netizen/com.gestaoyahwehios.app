/// Nome do ficheiro da logo no Storage: `logo_{nomeSanitizado}_{idDaIgreja}.jpg`
/// sob `igrejas/{id}/logo/`, para identificação clara no bucket (carteirinha, certificados, cadastro).
library;

abstract final class ChurchLogoStorageNaming {
  ChurchLogoStorageNaming._();

  /// Nome da igreja reduzido a [a-zA-Z0-9_] (espaços viram `_`), até [maxSlugLen].
  static String asciiSlugFromChurchName(String name, {int maxSlugLen = 48}) {
    final t = name.trim();
    if (t.isEmpty) return 'Igreja';
    final sb = StringBuffer();
    var lastUnderscore = false;
    for (var i = 0; i < t.length && sb.length < maxSlugLen; i++) {
      final c = t[i];
      final code = c.codeUnitAt(0);
      if ((code >= 48 && code <= 57) ||
          (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122)) {
        sb.write(c);
        lastUnderscore = false;
      } else if (c == ' ' || c == '_' || c == '-') {
        if (sb.isNotEmpty && !lastUnderscore) {
          sb.write('_');
          lastUnderscore = true;
        }
      }
    }
    var s = sb.toString().replaceAll(RegExp(r'_+'), '_');
    if (s.startsWith('_')) s = s.substring(1);
    if (s.endsWith('_')) s = s.substring(0, s.length - 1);
    if (s.isEmpty) return 'Igreja';
    return s;
  }

  /// Segmento do nome do ficheiro **sem** `.jpg` (fica `logo_{slug}_{tenantId}`).
  static String fileStemWithoutExt({
    required String churchName,
    required String tenantId,
  }) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return 'logo_Igreja_sem_id';
    final slug = asciiSlugFromChurchName(churchName);
    return 'logo_${slug}_$tid';
  }
}
