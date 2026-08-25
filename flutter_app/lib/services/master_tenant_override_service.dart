import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/core/tenant/church_tenant_override.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart'
    show firestoreRestCollect;

/// Igreja disponível para o master abrir no painel.
class MasterSwitchableChurch {
  const MasterSwitchableChurch({
    required this.id,
    required this.name,
    this.logoRef = '',
  });

  final String id;
  final String name;

  /// URL https ou path do Storage — [SafeNetworkImage] resolve os dois.
  final String logoRef;
}

/// Troca de igreja (base de dados) dentro do painel — **só para os operadores
/// globais**, para dar suporte/implantação sem sair da conta.
///
/// Regras: os dois UIDs já constam em `admins/{uid}`, então `isMaster()` do
/// Firestore já libera a leitura/escrita de qualquer tenant — esta classe é só
/// a escolha de QUAL tenant o painel abre.
///
/// **Não grava nada no tenant visitado**: gestor e membros não têm como notar
/// a visita (a preferência fica no aparelho do operador).
abstract final class MasterTenantOverrideService {
  MasterTenantOverrideService._();

  /// raihom@gmail.com e isabelle.krdoso@gmail.com.
  static const Set<String> allowedUids = {
    'O0qRLmLER2hwBFqvlzqSdtAUC3D3',
    'PljAYp6FBuWlGNl69Q2vnRp6gZh2',
  };

  static const String _prefsKey = 'master_tenant_override_v1';
  static int _selectionEpoch = 0;

  /// Muda quando o operador troca de igreja — o shell reconstrói ouvindo isto.
  static final ValueNotifier<String?> current = ValueNotifier<String?>(null);

  static bool get isAllowedUser {
    final uid = firebaseDefaultAuth.currentUser?.uid.trim() ?? '';
    return uid.isNotEmpty && allowedUids.contains(uid);
  }

  /// Tenant escolhido pelo operador (null = a própria igreja de origem).
  static String? get tenantId {
    if (!isAllowedUser) return null;
    final v = current.value?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  static Future<void> restore() async {
    final epoch = _selectionEpoch;
    if (!isAllowedUser) {
      ChurchContext.explicitTenantOverride = null;
      current.value = null;
      return;
    }
    String? restored;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_prefsKey) ?? '').trim();
      restored = saved.isEmpty ? null : saved;
    } catch (_) {
      restored = null;
    }
    if (epoch != _selectionEpoch) return;
    // O contexto global precisa mudar ANTES de notificar o shell. Caso
    // contrário, o listener resolve o destino enquanto o override ainda
    // aponta para a igreja anterior e volta a alimentar todos os módulos com
    // dados do tenant errado.
    ChurchContext.explicitTenantOverride = restored;
    current.value = restored;
  }

  static Future<void> setTenant(String? churchId) async {
    if (!isAllowedUser) return;
    final epoch = ++_selectionEpoch;
    final id = (churchId ?? '').trim();
    final next = id.isEmpty ? null : id;
    // Persiste antes de reconstruir a arvore. O novo AuthGate chama restore()
    // no arranque e nao pode reencontrar a preferencia da igreja anterior.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, id);
      }
    } catch (_) {}
    if (epoch != _selectionEpoch) return;
    ChurchContext.explicitTenantOverride = next;
    current.value = next;
  }

  static Future<void> clear() => setTenant(null);

  /// Lista de igrejas para o seletor. Web = REST (imune à assertion do SDK).
  static Future<List<MasterSwitchableChurch>> listChurches() async {
    if (!isAllowedUser) return const [];
    String nameOf(Map<String, dynamic> d, String id) {
      for (final k in ['nome', 'name', 'nomeIgreja', 'razaoSocial']) {
        final v = (d[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return id;
    }

    String logoOf(Map<String, dynamic> d) {
      for (final k in [
        'logoUrl',
        'logo',
        'logoPath',
        'logoStoragePath',
        'imagemUrl',
      ]) {
        final v = (d[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    // Toda igreja listada aqui é um documento real — regista para o resolvedor
    // aceitar ids fora do padrão `igreja_*`.
    void registar(Iterable<MasterSwitchableChurch> lista) {
      for (final c in lista) {
        ChurchTenantOverride.registerKnown(c.id);
      }
    }

    if (kIsWeb) {
      try {
        final docs = await firestoreRestCollect(collectionPath: 'igrejas');
        final out = [
          for (final d in docs)
            MasterSwitchableChurch(
              id: d.id,
              name: nameOf(d.data(), d.id),
              logoRef: logoOf(d.data()),
            ),
        ];
        if (out.isNotEmpty) {
          registar(out);
          out.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          return out;
        }
      } catch (_) {
        // Cai no SDK.
      }
    }
    try {
      final snap = await firebaseDefaultFirestore
          .collection('igrejas')
          .get(const GetOptions(source: Source.serverAndCache));
      final out = [
        for (final d in snap.docs)
          MasterSwitchableChurch(
            id: d.id,
            name: nameOf(d.data(), d.id),
            logoRef: logoOf(d.data()),
          ),
      ];
      registar(out);
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } catch (_) {
      return const [];
    }
  }
}
