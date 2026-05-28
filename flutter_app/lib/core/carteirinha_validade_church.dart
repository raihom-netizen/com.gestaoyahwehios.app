import 'package:cloud_firestore/cloud_firestore.dart';

/// Validade da carteirinha de membro — configurada no cadastro da igreja (`igrejas/{id}`).
enum CarteiraValidadeModo {
  permanente,
  anos2,
  anos3,
  anos5,
  dataFixa,
}

/// Regras de validade gravadas no documento da igreja.
class CarteiraValidadeChurch {
  const CarteiraValidadeChurch({
    required this.modo,
    this.dataFixa,
  });

  final CarteiraValidadeModo modo;
  final DateTime? dataFixa;

  static const String firestoreKeyModo = 'carteiraValidadeModo';
  static const String firestoreKeyDataFixa = 'carteiraValidadeDataFixa';

  static CarteiraValidadeChurch fromTenant(Map<String, dynamic>? tenant) {
    if (tenant == null || tenant.isEmpty) {
      return const CarteiraValidadeChurch(modo: CarteiraValidadeModo.anos3);
    }
    final rawModo = (tenant[firestoreKeyModo] ?? '').toString().trim();
    if (rawModo.isNotEmpty) {
      final parsed = _modoFromString(rawModo);
      if (parsed != null) {
        return CarteiraValidadeChurch(
          modo: parsed,
          dataFixa: parsed == CarteiraValidadeModo.dataFixa
              ? _parseDate(tenant[firestoreKeyDataFixa])
              : null,
        );
      }
    }
    if (tenant['carteiraValidadePermanente'] == true) {
      return const CarteiraValidadeChurch(modo: CarteiraValidadeModo.permanente);
    }
    final anos = tenant['carteiraValidadeAnos'];
    if (anos is int) {
      switch (anos) {
        case 2:
          return const CarteiraValidadeChurch(modo: CarteiraValidadeModo.anos2);
        case 5:
          return const CarteiraValidadeChurch(modo: CarteiraValidadeModo.anos5);
        case 3:
          return const CarteiraValidadeChurch(modo: CarteiraValidadeModo.anos3);
      }
    }
    return const CarteiraValidadeChurch(modo: CarteiraValidadeModo.anos3);
  }

  static CarteiraValidadeModo? _modoFromString(String raw) {
    switch (raw) {
      case 'permanente':
        return CarteiraValidadeModo.permanente;
      case 'anos_2':
        return CarteiraValidadeModo.anos2;
      case 'anos_3':
        return CarteiraValidadeModo.anos3;
      case 'anos_5':
        return CarteiraValidadeModo.anos5;
      case 'data_fixa':
        return CarteiraValidadeModo.dataFixa;
      default:
        return null;
    }
  }

  String get firestoreModoValue {
    switch (modo) {
      case CarteiraValidadeModo.permanente:
        return 'permanente';
      case CarteiraValidadeModo.anos2:
        return 'anos_2';
      case CarteiraValidadeModo.anos3:
        return 'anos_3';
      case CarteiraValidadeModo.anos5:
        return 'anos_5';
      case CarteiraValidadeModo.dataFixa:
        return 'data_fixa';
    }
  }

  String get uiLabel {
    switch (modo) {
      case CarteiraValidadeModo.permanente:
        return 'Permanente';
      case CarteiraValidadeModo.anos2:
        return '02 anos (a partir da emissão)';
      case CarteiraValidadeModo.anos3:
        return '03 anos (a partir da emissão)';
      case CarteiraValidadeModo.anos5:
        return '05 anos (a partir da emissão)';
      case CarteiraValidadeModo.dataFixa:
        if (dataFixa != null) {
          return 'Data fixa: ${_fmtDate(dataFixa!)}';
        }
        return 'Data fixa (defina abaixo)';
    }
  }

  /// Texto exibido no cartão («VÁLIDO ATÉ»).
  String displayLabel({required DateTime baseDate}) {
    switch (modo) {
      case CarteiraValidadeModo.permanente:
        return 'Permanente';
      case CarteiraValidadeModo.anos2:
        return _fmtDate(_addYears(baseDate, 2));
      case CarteiraValidadeModo.anos3:
        return _fmtDate(_addYears(baseDate, 3));
      case CarteiraValidadeModo.anos5:
        return _fmtDate(_addYears(baseDate, 5));
      case CarteiraValidadeModo.dataFixa:
        final d = dataFixa;
        if (d == null) return '—';
        return _fmtDate(d);
    }
  }

  static DateTime emissionBaseFromMember(Map<String, dynamic> member) {
    return _parseDate(member['carteirinhaAssinadaEm']) ??
        _parseDate(member['DATA_MEMBRO']) ??
        _parseDate(member['dataMembro']) ??
        _parseDate(member['dataAdmissao']) ??
        _parseDate(member['DATA_ADMISSAO']) ??
        _parseDate(member['admissao']) ??
        DateTime.now();
  }

  static DateTime _addYears(DateTime d, int years) {
    return DateTime(d.year + years, d.month, d.day);
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is Map) {
      final sec = v['seconds'] ?? v['_seconds'];
      if (sec is num) {
        return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000).toLocal();
      }
    }
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  static String _fmtDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year}';
  }
}
