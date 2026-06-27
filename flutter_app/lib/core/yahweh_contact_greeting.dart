/// Saudação por horário — Chat Igreja e atalhos WhatsApp (membros, líderes, pastoral).
abstract final class YahwehContactGreeting {
  YahwehContactGreeting._();

  static String timeOfDayGreeting([DateTime? at]) {
    final h = (at ?? DateTime.now()).hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  /// Texto padrão ao abrir chat da igreja ou WhatsApp com «Fale comigo».
  static String faleComigoDraft([DateTime? at]) {
    return '${timeOfDayGreeting(at)}. Paz Senhor, gostaria de falar contigo.';
  }
}
