/// Emojis modernos do widget de calendário — inferidos por tipo + título/abreviação.
class WidgetEventSymbols {
  WidgetEventSymbols._();

  static String resolve({
    required String type,
    required String title,
    String abbreviation = '',
  }) {
    final t = type.toLowerCase().trim();
    final hay = _normalize('$title $abbreviation');

    if (t == 'finance') return '💳';
    if (t == 'audiencia' || _matches(hay, _audienciaKeys)) return '⚖️';

    if (_matches(hay, _birthdayKeys)) return '🎂';
    if (_matches(hay, _dentistKeys)) return '🦷';
    if (_matches(hay, _doctorKeys)) return '🩺';
    if (_matches(hay, _churchKeys)) return '⛪';
    if (_matches(hay, _weddingKeys)) return '💒';
    if (_matches(hay, _meetingKeys)) return '👥';
    if (_matches(hay, _schoolKeys)) return '🎓';
    if (_matches(hay, _shoppingKeys)) return '🛒';
    if (_matches(hay, _travelKeys)) return '✈️';
    if (_matches(hay, _gymKeys)) return '💪';
    if (_matches(hay, _operationKeys)) return '⚡';
    if (_matches(hay, _vtrKeys)) return '🚓';

    if (t == 'scale' || t == 'plantao' || t == 'plantão') {
      if (_matches(hay, _patrolKeys)) return '👮';
      return '🚔';
    }

    if (t == 'compromisso') {
      // Gestão Yahweh não tem presets de compromisso do Controle Total —
      // emoji direto por palavra-chave já coberta acima; padrão calendário.
      return '📅';
    }
    return '📌';
  }

  /// Cor da barra lateral quando o evento não traz accent próprio.
  static String defaultBarHex({
    required String type,
    required String symbol,
    required bool isToday,
  }) {
    switch (symbol) {
      case '🎂':
        return '#FFEC407A';
      case '🩺':
        return '#FF26A69A';
      case '🦷':
        return '#FF42A5F5';
      case '⚖️':
        return '#FF7C4DFF';
      case '🚓':
        return '#FF2563EB';
      case '👮':
        return '#FF00BCD4';
      case '⚡':
        return '#FFFFB300';
      case '⛪':
        return '#FF8D6E63';
      case '💒':
        return '#FFE91E63';
      case '👥':
        return '#FF1E88E5';
      case '🎓':
        return '#FF5C6BC0';
      case '💳':
        return '#FFFF8A50';
      case '📅':
        return '#FF12B5A5';
      default:
        break;
    }
    switch (type.toLowerCase()) {
      case 'audiencia':
        return '#FF7C4DFF';
      case 'compromisso':
        return '#FF12B5A5';
      case 'finance':
        return '#FFFF8A50';
      default:
        return isToday ? '#FF00BCD4' : '#FFFFC107';
    }
  }

  static String _normalize(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }

  static bool _matches(String hay, List<String> keys) {
    for (final k in keys) {
      if (hay.contains(k)) return true;
    }
    return false;
  }

  static const _birthdayKeys = [
    'anivers',
    'birthday',
    'bolo',
    'festa de aniv',
  ];

  static const _dentistKeys = [
    'dentist',
    'odonto',
    'ortodont',
  ];

  static const _doctorKeys = [
    'medico',
    'medic',
    'consulta med',
    'hospital',
    'clinica',
    'exame',
    'laborator',
    'psicolog',
    'terapia',
    'vacina',
    'farmacia',
    'veterin',
    'dermatolog',
    'oftalmolog',
    'cardiolog',
    'neurolog',
    'fisioter',
    'nutricion',
  ];

  static const _audienciaKeys = [
    'audienc',
    'advogado',
    'forum',
    'vara',
    'tribunal',
    'juri',
  ];

  static const _vtrKeys = [
    'vtr',
    'viatura',
    'patrulh',
    'bpm',
    'sv.',
    'sv ',
    'servico viatura',
  ];

  static const _patrolKeys = [
    'plantao',
    'escala',
    'ordin',
    'extra',
    'servico',
    'turno',
    'ronda',
  ];

  static const _operationKeys = [
    'operac',
    'equipe de oper',
    'tatico',
    'coe',
    'rotam',
  ];

  static const _churchKeys = ['igreja', 'culto', 'missa'];
  static const _weddingKeys = ['casamento', 'noiv', 'matrim'];
  static const _meetingKeys = ['reuniao', 'meeting', 'networking'];
  static const _schoolKeys = [
    'escola',
    'faculdade',
    'curso',
    'aula',
    'prova',
    'vestibular',
  ];
  static const _shoppingKeys = [
    'mercado',
    'supermercado',
    'compras',
    'shopping',
    'banco',
    'conta',
  ];
  static const _travelKeys = ['viagem', 'aeroporto', 'hotel', 'onibus'];
  static const _gymKeys = ['academia', 'treino', 'corrida', 'natacao'];
}
