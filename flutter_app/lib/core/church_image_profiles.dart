/// Perfis de compressão — política única Web/Android/iOS.
abstract final class ChurchImageProfiles {
  ChurchImageProfiles._();

  /// Fotos gerais (eventos, avisos, patrimônio).
  static const int feedPhotoMaxEdge = 1920;
  static const int feedPhotoQuality = 80;

  /// Foto de perfil membro.
  static const int memberProfileEdge = 512;
  static const int memberProfileQuality = 80;

  /// Logo institucional.
  static const int churchLogoEdge = 1024;
  static const int churchLogoQuality = 85;
}
