import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart'
    show firestoreRestGetDoc;
/// Garante documento mínimo em `igrejas/{tenantId}/membros/{authUid}` para o gestor —
/// nome (displayName ou e-mail) e e-mail; foto e demais dados em **Membros**.
class GestorMembroStubService {
  GestorMembroStubService._();

  static Future<void> ensurePreCadastroGestor({
    required String tenantId,
    required String role,
  }) async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null) return;
    final rl = role.toLowerCase();
    if (rl != 'gestor' && rl != 'adm' && rl != 'admin' && rl != 'master') {
      return;
    }
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    final col =         ChurchOperationalPaths.churchDoc(op)
        .collection('membros');
    final ref = col.doc(user.uid);

    // Leitura curada: este `.get()` cru era a fonte do
    // «Igreja salva. Pre-cadastro em Membros: INTERNAL ASSERTION FAILED».
    // Com o SDK web envenenado ele lanca, e a escrita a seguir (que ja usa
    // YahwehDocWrite, com REST) nem chegava a acontecer. Falhar a leitura nao
    // pode impedir o stub: no pior caso trata-se como documento inexistente.
    Map<String, dynamic>? existente;
    var existe = false;
    try {
      final snap = await ref.get().timeout(const Duration(seconds: 8));
      existe = snap.exists;
      existente = snap.data();
    } catch (_) {
      if (kIsWeb) {
        try {
          final rest = await firestoreRestGetDoc(
            ref.path,
          ).timeout(const Duration(seconds: 10));
          existe = rest != null;
          existente = rest;
        } catch (_) {}
      }
    }

    String nome() {
      final dn = user.displayName?.trim() ?? '';
      if (dn.isNotEmpty) return dn;
      final em = user.email ?? '';
      if (em.isEmpty) return 'Gestor';
      return em.split('@').first;
    }

    final nomeVal = nome();
    final email = user.email?.trim().toLowerCase() ?? '';
    final funcaoKey = rl == 'master' ? 'master' : 'adm';
    final cargoLabel = rl == 'master' ? 'Master' : 'Administrador';
    final seed = Uri.encodeComponent(nomeVal);
    final placeholderAvatar =
        'https://api.dicebear.com/7.x/initials/png?seed=$seed&backgroundColor=EAF2FF,DDEBFF,CFE3FF';

    if (existe) {
      final d = existente ?? {};
      final patch = <String, dynamic>{
        'ATUALIZADO_EM': YahwehFv.serverTimestamp,
      };
      if ((d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim().isEmpty) {
        patch['NOME_COMPLETO'] = nomeVal;
      }
      if ((d['EMAIL'] ?? d['email'] ?? '').toString().trim().isEmpty &&
          email.isNotEmpty) {
        patch['EMAIL'] = email;
      }
      if ((d['authUid'] ?? '').toString().trim().isEmpty) {
        patch['authUid'] = user.uid;
      }
      if (patch.length == 1) return;
      await YahwehDocWrite.set(ref, patch);
      return;
    }

    await YahwehDocWrite.set(ref, <String, dynamic>{
      'MEMBER_ID': user.uid,
      'tenantId': tenantId,
      'authUid': user.uid,
      'NOME_COMPLETO': nomeVal,
      'EMAIL': email,
      'FUNCAO': funcaoKey,
      'FUNCOES': <String>[funcaoKey],
      'CARGO': cargoLabel,
      'role': funcaoKey,
      'STATUS': 'ativo',
      'status': 'ativo',
      'GESTOR_PRECADASTRO': true,
      'FOTO_URL_OU_ID': placeholderAvatar,
      'fotoUrl': placeholderAvatar,
      'CRIADO_EM': YahwehFv.serverTimestamp,
      'alias': tenantId,
      'slug': tenantId,
    });
  }
}

