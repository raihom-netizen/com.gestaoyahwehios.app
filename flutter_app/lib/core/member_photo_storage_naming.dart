/// **Canónico (uploads atuais):** `igrejas/{idIgreja}/membros/{idDocumentoMembro}/foto_perfil.jpg`
/// — o [idDocumentoMembro] é o id do doc Firestore (muitas vezes o CPF só dígitos, ex. `94536368191`);
/// o ficheiro é sempre `foto_perfil.jpg` (ver [ChurchStorageLayout.memberCanonicalProfilePhotoPath]).
///
/// **Legado / descoberta:** pasta alternativa `PrimeiroNome_uidDoFirebase` (ex.: `Raihom_WIQ6…`) usada em
/// [profileFolderStem] para [FirebaseStorageService.getMemberProfilePhotoDownloadUrl] tentar caminhos antigos.
library;

abstract final class MemberPhotoStorageNaming {
  MemberPhotoStorageNaming._();

  /// Segmento da pasta (sem barras). Apenas letras ASCII do primeiro nome + `_` + id.
  static String profileFolderStem({
    required String nomeCompleto,
    required String memberDocId,
    String? authUid,
  }) {
    final idPart = (authUid != null && authUid.trim().isNotEmpty)
        ? authUid.trim()
        : memberDocId.trim();
    if (idPart.isEmpty) return 'sem_id';
    final first = firstNameAsciiSegment(nomeCompleto);
    final safeFirst = first.isEmpty ? 'Membro' : first;
    return '${safeFirst}_$idPart';
  }

  /// Primeiro token do nome, só [a-zA-Z0-9], até 40 caracteres (compatível com Storage).
  static String firstNameAsciiSegment(String nomeCompleto) {
    final t = nomeCompleto.trim();
    if (t.isEmpty) return '';
    final parts = t.split(RegExp(r'\s+'));
    var word = '';
    for (final p in parts) {
      if (p.isNotEmpty) {
        word = p;
        break;
      }
    }
    if (word.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < word.length && sb.length < 40; i++) {
      final code = word.codeUnitAt(i);
      if ((code >= 48 && code <= 57) ||
          (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122)) {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }
}
