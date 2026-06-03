import 'package:flutter/foundation.dart';

/// Matriz canónica — mesma experiência Android / iOS / Web (regras de negócio unificadas).
enum YahwehQaPlatform {
  android('Android', '🤖'),
  ios('iOS', '🍎'),
  web('Web', '🌐');

  const YahwehQaPlatform(this.label, this.icon);
  final String label;
  final String icon;
}

class MultiplatformModuleSpec {
  const MultiplatformModuleSpec({
    required this.id,
    required this.label,
    required this.sameExperienceOnAndroid,
    required this.sameExperienceOnIos,
    required this.sameExperienceOnWeb,
    this.note = '',
  });

  final String id;
  final String label;
  final bool sameExperienceOnAndroid;
  final bool sameExperienceOnIos;
  final bool sameExperienceOnWeb;
  final String note;

  bool requiredOn(YahwehQaPlatform platform) => switch (platform) {
        YahwehQaPlatform.android => sameExperienceOnAndroid,
        YahwehQaPlatform.ios => sameExperienceOnIos,
        YahwehQaPlatform.web => sameExperienceOnWeb,
      };
}

abstract final class MultiplatformQaMatrix {
  MultiplatformQaMatrix._();

  static const releasePlatforms = YahwehQaPlatform.values;

  /// Módulos com experiência idêntica nas três plataformas (salvo nota).
  static const unifiedModules = <MultiplatformModuleSpec>[
    MultiplatformModuleSpec(
      id: 'login',
      label: 'Login',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'chat',
      label: 'Chat',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'avisos',
      label: 'Avisos',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'eventos',
      label: 'Eventos',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'membros',
      label: 'Membros',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'patrimonio',
      label: 'Patrimônio',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'financeiro',
      label: 'Financeiro',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'uploads',
      label: 'Uploads',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
    ),
    MultiplatformModuleSpec(
      id: 'sync',
      label: 'Sincronização',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
      note: 'Mesma lógica SyncEngine + filas',
    ),
    MultiplatformModuleSpec(
      id: 'resume',
      label: 'Retornar onde parou',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
      note: 'AppResumeStateService',
    ),
    MultiplatformModuleSpec(
      id: 'offline',
      label: 'Offline',
      sameExperienceOnAndroid: true,
      sameExperienceOnIos: true,
      sameExperienceOnWeb: true,
      note: 'Mobile: Hive obrigatório. Web: cache local + recuperação automática',
    ),
  ];

  /// Apenas estas áreas podem usar ramos por plataforma (`kIsWeb`, `Platform.is*`).
  static const platformIsolatedCapabilities = <String>[
    'câmera',
    'notificações push',
    'biometria',
    'compartilhamento',
    'acesso a ficheiros',
  ];

  static YahwehQaPlatform currentPlatform() {
    if (kIsWeb) return YahwehQaPlatform.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return YahwehQaPlatform.ios;
      case TargetPlatform.android:
        return YahwehQaPlatform.android;
      default:
        return YahwehQaPlatform.web;
    }
  }

  static String currentPlatformSummary() {
    final p = currentPlatform();
    return '${p.icon} ${p.label}';
  }

  /// Gate de release: falha numa plataforma bloqueia release.
  static const releaseBlockedIfAnyPlatformFails = true;
}
