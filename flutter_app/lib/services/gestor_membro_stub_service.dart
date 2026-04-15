import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Garante documento mínimo em `igrejas/{tenantId}/membros/{authUid}` para o gestor —
/// nome (displayName ou e-mail) e e-mail; foto e demais dados em **Membros**.
class GestorMembroStubService {
  GestorMembroStubService._();

  static Future<void> ensurePreCadastroGestor({
    required String tenantId,
    required String role,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final rl = role.toLowerCase();
    if (rl != 'gestor' && rl != 'adm' && rl != 'admin' && rl != 'master') {
      return;
    }
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros');
    final ref = col.doc(user.uid);
    final snap = await ref.get();

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

    if (snap.exists) {
      final d = snap.data() ?? {};
      final patch = <String, dynamic>{
        'ATUALIZADO_EM': FieldValue.serverTimestamp(),
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
      await ref.set(patch, SetOptions(merge: true));
      return;
    }

    await ref.set(<String, dynamic>{
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
      'CRIADO_EM': FieldValue.serverTimestamp(),
      'alias': tenantId,
      'slug': tenantId,
    }, SetOptions(merge: true));
  }
}
