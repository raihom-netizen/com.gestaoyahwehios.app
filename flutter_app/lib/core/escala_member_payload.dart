import 'package:cloud_firestore/cloud_firestore.dart';

/// Membro escalado — leitura unificada (denormalizado `escalados[]` ou legado CPF/nome).
class EscalaMemberRow {
  const EscalaMemberRow({
    required this.cpf,
    required this.cpfDigits,
    required this.name,
    this.uid = '',
    this.role = '',
    this.photoUrl = '',
    this.confirmation = '',
  });

  final String cpf;
  final String cpfDigits;
  final String name;
  final String uid;
  final String role;
  final String photoUrl;
  final String confirmation;

  /// Chave canónica para `confirmations` / `unavailabilityReasons` (UID preferido).
  String get confirmationKey => uid.trim().isNotEmpty ? uid.trim() : cpf;

  Map<String, dynamic> toFirestoreMap() => {
        if (uid.trim().isNotEmpty) 'uid': uid.trim(),
        'cpf': cpf,
        if (cpfDigits.length == 11) 'cpfDigits': cpfDigits,
        'name': name,
        if (role.trim().isNotEmpty) 'role': role.trim(),
        if (photoUrl.trim().isNotEmpty) 'photoUrl': photoUrl.trim(),
        if (confirmation.trim().isNotEmpty) 'confirmation': confirmation.trim(),
      };
}

/// Parse / gravação de membros em `igrejas/{id}/escalas` — sem sub-queries na UI.
abstract final class EscalaMemberPayload {
  EscalaMemberPayload._();

  static String normCpf(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9]'), '');

  static List<EscalaMemberRow> parseMembers(Map<String, dynamic> data) {
    final escalados = data['escalados'];
    if (escalados is List && escalados.isNotEmpty) {
      final out = <EscalaMemberRow>[];
      for (final raw in escalados) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final cpfRaw = (m['cpf'] ?? m['CPF'] ?? '').toString();
        final digits = normCpf(cpfRaw);
        final name = (m['name'] ?? m['nome'] ?? m['NOME_COMPLETO'] ?? '')
            .toString()
            .trim();
        if (name.isEmpty && digits.length != 11 && cpfRaw.isEmpty) continue;
        out.add(
          EscalaMemberRow(
            cpf: cpfRaw.isNotEmpty ? cpfRaw : digits,
            cpfDigits: digits.length == 11 ? digits : normCpf(cpfRaw),
            name: name,
            uid: (m['uid'] ?? m['authUid'] ?? m['firebaseUid'] ?? '')
                .toString()
                .trim(),
            role: (m['role'] ?? m['funcao'] ?? m['FUNCAO'] ?? '').toString(),
            photoUrl: (m['photoUrl'] ??
                    m['fotoUrl'] ??
                    m['FOTO_URL_OU_ID'] ??
                    '')
                .toString(),
            confirmation: (m['confirmation'] ?? m['statusPresenca'] ?? '')
                .toString(),
          ),
        );
      }
      if (out.isNotEmpty) return out;
    }

    final cpfs =
        ((data['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final names =
        ((data['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
    final confirmations =
        (data['confirmations'] as Map<String, dynamic>?) ?? const {};
    final out = <EscalaMemberRow>[];
    for (var i = 0; i < cpfs.length; i++) {
      final cpf = cpfs[i];
      final digits = normCpf(cpf);
      final name = i < names.length ? names[i].trim() : '';
      out.add(
        EscalaMemberRow(
          cpf: cpf,
          cpfDigits: digits,
          name: name,
          confirmation: mapValueForMemberKey(cpf, digits, confirmations),
        ),
      );
    }
    return out;
  }

  static String mapValueForMemberKey(
    String cpfKey,
    String cpfDigits,
    Map<String, dynamic> map,
  ) {
    if (map.isEmpty) return '';
    final direct = map[cpfKey];
    if (direct != null && direct.toString().isNotEmpty) {
      return direct.toString();
    }
    if (cpfDigits.length == 11) {
      final byDigits = map[cpfDigits];
      if (byDigits != null && byDigits.toString().isNotEmpty) {
        return byDigits.toString();
      }
    }
    for (final e in map.entries) {
      if (normCpf(e.key.toString()) == cpfDigits && cpfDigits.length == 11) {
        return (e.value ?? '').toString();
      }
    }
    return '';
  }

  static String confirmationStatus(
    Map<String, dynamic> data,
    EscalaMemberRow member,
  ) {
    if (member.confirmation.trim().isNotEmpty) return member.confirmation;
    final confirmations =
        (data['confirmations'] as Map<String, dynamic>?) ?? const {};
    return mapValueForMemberKey(
      member.confirmationKey,
      member.cpfDigits,
      confirmations,
    );
  }

  static Map<String, dynamic>? unavailabilityReason(
    Map<String, dynamic> data,
    EscalaMemberRow member,
  ) {
    final reasons =
        (data['unavailabilityReasons'] as Map<String, dynamic>?) ?? const {};
    final key = member.confirmationKey;
    final direct = reasons[key];
    if (direct is Map) return Map<String, dynamic>.from(direct);
    if (member.cpfDigits.length == 11) {
      final byDigits = reasons[member.cpfDigits];
      if (byDigits is Map) return Map<String, dynamic>.from(byDigits);
    }
    for (final e in reasons.entries) {
      if (normCpf(e.key.toString()) == member.cpfDigits &&
          member.cpfDigits.length == 11 &&
          e.value is Map) {
        return Map<String, dynamic>.from(e.value as Map);
      }
    }
    return null;
  }

  static EscalaMemberRow? findMemberForUser({
    required Map<String, dynamic> data,
    required String cpfDigits,
    String uid = '',
  }) {
    final digits = normCpf(cpfDigits);
    final authUid = uid.trim();
    for (final m in parseMembers(data)) {
      if (authUid.isNotEmpty && m.uid == authUid) return m;
      if (digits.length == 11 && m.cpfDigits == digits) return m;
    }
    return null;
  }

  static bool docContainsMember({
    required Map<String, dynamic> data,
    String cpfDigits = '',
    String uid = '',
  }) =>
      findMemberForUser(data: data, cpfDigits: cpfDigits, uid: uid) != null;

  static List<String> memberUids(List<EscalaMemberRow> members) => [
        for (final m in members)
          if (m.uid.trim().isNotEmpty) m.uid.trim(),
      ];

  static List<String> memberCpfs(List<EscalaMemberRow> members) =>
      members.map((m) => m.cpf).toList();

  static List<String> memberNames(List<EscalaMemberRow> members) =>
      members.map((m) => m.name).toList();

  /// Dual-write: `escalados[]` + `memberUids` + campos legados.
  static Map<String, dynamic> writeFieldsFromMembers(
    List<EscalaMemberRow> members,
  ) =>
      {
        'escalados': members.map((m) => m.toFirestoreMap()).toList(),
        'memberUids': memberUids(members),
        'memberCpfs': memberCpfs(members),
        'memberNames': memberNames(members),
      };

  static List<EscalaMemberRow> rowsFromParallelLists({
    required List<String> cpfs,
    required List<String> names,
    Map<String, Map<String, dynamic>>? memberDocByCpfDigits,
  }) {
    final out = <EscalaMemberRow>[];
    for (var i = 0; i < cpfs.length; i++) {
      final cpf = cpfs[i];
      final digits = normCpf(cpf);
      final name = i < names.length ? names[i].trim() : '';
      Map<String, dynamic>? doc;
      if (digits.length == 11 && memberDocByCpfDigits != null) {
        doc = memberDocByCpfDigits[digits];
      }
      final uid = (doc?['authUid'] ?? doc?['firebaseUid'] ?? '').toString();
      final role = (doc?['FUNCAO'] ?? doc?['funcao'] ?? doc?['role'] ?? '')
          .toString();
      final photo = (doc?['fotoUrl'] ??
              doc?['FOTO_URL_OU_ID'] ??
              doc?['photoUrl'] ??
              '')
          .toString();
      out.add(
        EscalaMemberRow(
          cpf: cpf,
          cpfDigits: digits,
          name: name,
          uid: uid,
          role: role,
          photoUrl: photo,
        ),
      );
    }
    return out;
  }

  static Map<String, Map<String, dynamic>> buildMemberDocIndexByCpf(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final d in docs) {
      final data = d.data();
      final cpf = normCpf(
        (data['CPF'] ?? data['cpf'] ?? d.id).toString(),
      );
      if (cpf.length == 11) map[cpf] = data;
    }
    return map;
  }

  /// Patch de confirmação — chaves UID (preferido) + legado CPF.
  static Map<Object, Object?> buildConfirmationUpdates({
    required EscalaMemberRow member,
    required String status,
    String? motivo,
  }) {
    final updates = <Object, Object?>{'updatedAt': FieldValue.serverTimestamp()};
    final uidKey = member.uid.trim();
    final cpfKey = member.cpf;
    final cpfDigits = member.cpfDigits;

    void setConfirmation(Object? value) {
      if (uidKey.isNotEmpty) {
        updates[FieldPath(['confirmations', uidKey])] = value;
      }
      updates[FieldPath(['confirmations', cpfKey])] = value;
      if (cpfDigits.length == 11 && cpfDigits != cpfKey) {
        updates[FieldPath(['confirmations', cpfDigits])] = value;
      }
    }

    void setReason(Object? value) {
      if (uidKey.isNotEmpty) {
        updates[FieldPath(['unavailabilityReasons', uidKey])] = value;
      }
      updates[FieldPath(['unavailabilityReasons', cpfKey])] = value;
      if (cpfDigits.length == 11 && cpfDigits != cpfKey) {
        updates[FieldPath(['unavailabilityReasons', cpfDigits])] = value;
      }
    }

    if (status.isEmpty) {
      setConfirmation(FieldValue.delete());
      setReason(FieldValue.delete());
      return updates;
    }

    setConfirmation(status);
    if (status == 'indisponivel' && (motivo ?? '').trim().isNotEmpty) {
      setReason({
        'reason': motivo!.trim(),
        'at': FieldValue.serverTimestamp(),
      });
    } else if (status != 'indisponivel') {
      setReason(FieldValue.delete());
    }
    return updates;
  }

  /// Aplica confirmação optimista em memória (UI imediata).
  static Map<String, dynamic> applyConfirmationOptimistic({
    required Map<String, dynamic> data,
    required EscalaMemberRow member,
    required String status,
    String? motivo,
  }) {
    final next = Map<String, dynamic>.from(data);
    final confirmations = Map<String, dynamic>.from(
      (next['confirmations'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final reasons = Map<String, dynamic>.from(
      (next['unavailabilityReasons'] as Map?)?.cast<String, dynamic>() ??
          const {},
    );
    final key = member.confirmationKey;
    if (status.isEmpty) {
      confirmations.remove(key);
      confirmations.remove(member.cpf);
      if (member.cpfDigits.length == 11) {
        confirmations.remove(member.cpfDigits);
      }
      reasons.remove(key);
      reasons.remove(member.cpf);
      if (member.cpfDigits.length == 11) {
        reasons.remove(member.cpfDigits);
      }
    } else {
      confirmations[key] = status;
      if (member.cpf.isNotEmpty && member.cpf != key) {
        confirmations[member.cpf] = status;
      }
      if (member.cpfDigits.length == 11) {
        confirmations[member.cpfDigits] = status;
      }
      if (status == 'indisponivel' && (motivo ?? '').trim().isNotEmpty) {
        final payload = {
          'reason': motivo!.trim(),
          'at': Timestamp.now(),
        };
        reasons[key] = payload;
      } else {
        reasons.remove(key);
      }
    }
    next['confirmations'] = confirmations;
    next['unavailabilityReasons'] = reasons;

    final escalados = next['escalados'];
    if (escalados is List) {
      final patched = <Map<String, dynamic>>[];
      for (final raw in escalados) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final rowUid = (row['uid'] ?? '').toString();
        final rowCpf = normCpf((row['cpf'] ?? row['CPF'] ?? '').toString());
        if ((member.uid.isNotEmpty && rowUid == member.uid) ||
            (member.cpfDigits.length == 11 && rowCpf == member.cpfDigits)) {
          row['confirmation'] = status;
        }
        patched.add(row);
      }
      next['escalados'] = patched;
    }
    return next;
  }
}
