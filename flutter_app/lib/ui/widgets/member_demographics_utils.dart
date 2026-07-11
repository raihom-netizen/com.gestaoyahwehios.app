import 'package:cloud_firestore/cloud_firestore.dart';

/// Data de nascimento a partir de vários formatos (Timestamp, Map Firestore, string BR dd/MM/yyyy, ISO).
DateTime? birthDateFromMemberData(Map<String, dynamic>? data) {
  if (data == null) return null;
  const keys = [
    'DATA_NASCIMENTO',
    'dataNascimento',
    'birthDate',
    'nascimento',
    'data_nascimento',
    'dtNascimento',
    'dataNasc',
  ];
  dynamic raw;
  for (final k in keys) {
    final v = data[k];
    if (v != null) {
      raw = v;
      break;
    }
  }
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is Map) {
    final sec = raw['seconds'] ?? raw['_seconds'];
    if (sec != null) {
      return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
    }
  }
  if (raw is int) {
    if (raw > 1000000000000) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      } catch (_) {}
    }
  }
  if (raw is String) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final br = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})').firstMatch(t);
    if (br != null) {
      final day = int.tryParse(br.group(1)!);
      final month = int.tryParse(br.group(2)!);
      final year = int.tryParse(br.group(3)!);
      if (day != null && month != null && year != null && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        try {
          return DateTime(year, month, day);
        } catch (_) {}
      }
    }
    final iso = DateTime.tryParse(t.length >= 10 ? t.substring(0, 10) : t);
    if (iso != null) return iso;
  }

  int? monthFromIndexed(dynamic raw) {
    if (raw is num) return raw.toInt();
    final p = int.tryParse('$raw');
    if (p != null && p >= 1 && p <= 12) return p;
    return null;
  }

  int? dayFromIndexed(dynamic raw) {
    if (raw is num) return raw.toInt();
    final p = int.tryParse('$raw');
    if (p != null && p >= 1 && p <= 31) return p;
    return null;
  }

  final indexedMonth = monthFromIndexed(data['birthMonth']);
  final indexedDay = dayFromIndexed(data['birthDay']);
  if (indexedMonth != null && indexedDay != null) {
    try {
      return DateTime(DateTime.now().year, indexedMonth, indexedDay);
    } catch (_) {}
  }

  return null;
}

/// Idade em anos completos na data de referência (calendário local).
/// Só incrementa após passar o dia/mês de aniversário no ano de [reference].
int ageInYearsAt(DateTime birth, DateTime reference) {
  var age = reference.year - birth.year;
  if (reference.month < birth.month ||
      (reference.month == birth.month && reference.day < birth.day)) {
    age--;
  }
  return age;
}

/// Idade em anos; usa data de nascimento ou campos IDADE/idade/age.
int? ageFromMemberData(Map<String, dynamic>? data) {
  if (data == null) return null;
  final dt = birthDateFromMemberData(data);
  if (dt != null) {
    return ageInYearsAt(dt, DateTime.now());
  }
  for (final k in ['IDADE', 'idade', 'age']) {
    final v = data[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    final p = int.tryParse(v?.toString().trim() ?? '');
    if (p != null && p >= 0 && p < 130) return p;
  }
  return null;
}

/// 'M' = masculino, 'F' = feminino, '' = não informado.
/// Trata Mulher/Mulheres antes de Masculino (evita startsWith('m') em "mulher").
String genderCategoryFromMemberData(Map<String, dynamic>? data) {
  if (data == null) return '';
  dynamic raw = data['SEXO'] ?? data['sexo'] ?? data['genero'] ?? data['gender'];
  if (raw == null) return '';
  if (raw is num) {
    final n = raw.toInt();
    if (n == 2) return 'F';
    if (n == 1) return 'M';
    return '';
  }
  final s = raw.toString().toLowerCase().trim();
  if (s.isEmpty) return '';
  if (s == 'f' || s == '2' || s == 'female') return 'F';
  if (s.startsWith('mulh') || s.contains('femin') || s == 'femea' || s == 'fêmea') return 'F';
  if (s == 'm' || s == '1' || s == 'male' || s == 'h') return 'M';
  if (s.startsWith('masc') || s.startsWith('hom')) return 'M';
  if (s == 'masculino') return 'M';
  if (s == 'feminino') return 'F';
  return '';
}

/// Faixa etária: `todas` | `criancas` | `adolescentes` | `adultos` | `idosos`.
bool memberMatchesAgeBand(Map<String, dynamic>? data, String band) {
  if (band == 'todas' || band.isEmpty) return true;
  final idade = ageFromMemberData(data);
  if (idade == null) return false;
  switch (band) {
    case 'criancas':
      return idade < 13;
    case 'adolescentes':
      return idade >= 13 && idade < 18;
    case 'adultos':
      return idade >= 18 && idade < 60;
    case 'idosos':
      return idade >= 60;
    default:
      return true;
  }
}

bool memberMatchesGenderFilter(Map<String, dynamic>? data, String filter) {
  if (filter == 'todos' || filter.isEmpty) return true;
  final g = genderCategoryFromMemberData(data);
  if (filter == 'masculino') return g == 'M';
  if (filter == 'feminino') return g == 'F';
  return true;
}

/// [deptFilter] = id ou nome do departamento; `todos` = sem filtro.
bool memberMatchesDepartmentFilter(
  Map<String, dynamic>? data,
  String deptFilter, {
  Iterable<({String id, String name})> knownDepts = const [],
}) {
  if (deptFilter == 'todos' || deptFilter.isEmpty) return true;
  if (data == null) return false;
  final depts = data['DEPARTAMENTOS'] ?? data['departamentos'];
  if (depts is List) {
    for (final x in depts) {
      final s = x.toString();
      if (s == deptFilter) return true;
      for (final d in knownDepts) {
        if (d.id == deptFilter && d.name == s) return true;
      }
    }
  }
  final d =
      (data['departamento'] ?? data['DEPARTAMENTO'] ?? '').toString().trim();
  if (d.isEmpty) return false;
  if (d == deptFilter) return true;
  for (final known in knownDepts) {
    if (known.id == deptFilter && known.name == d) return true;
  }
  return false;
}

/// Vários departamentos: conjunto vazio = sem filtro; membro passa se pertencer a **qualquer** um selecionado.
bool memberMatchesDepartmentsFilter(
  Map<String, dynamic>? data,
  Set<String> selectedDeptIds, {
  Iterable<({String id, String name})> knownDepts = const [],
}) {
  if (selectedDeptIds.isEmpty) return true;
  for (final id in selectedDeptIds) {
    if (memberMatchesDepartmentFilter(
      data,
      id,
      knownDepts: knownDepts,
    )) {
      return true;
    }
  }
  return false;
}
