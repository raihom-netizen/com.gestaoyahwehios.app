/// Igreja escolhida pelo operador global e **o que conta como id de documento
/// de igreja**.
///
/// Nem todo tenant em produção respeita o padrão `igreja_*`: há documentos
/// gravados como `assembleia_de_deus_palavra_que_da_vida` (sem prefixo) e
/// `igreta_batista_nacional_alianca` (gralha no nome de origem, que virou id).
///
/// O teste `^igreja_[a-z0-9_]+$` estava **duplicado em nove ficheiros** — core,
/// serviços e UI —, e cada cópia decidia sozinha. Ao visitar uma dessas igrejas,
/// cada módulo rejeitava o id por sua conta e caía na igreja de origem: Membros
/// e Cartas mostravam a Brasil Para Cristo enquanto Cadastro e Agenda já
/// mostravam a igreja certa. Por isso corrigir só um ponto nunca resolvia.
///
/// Este ficheiro **não importa nada** de propósito: assim pode ser usado por
/// `ChurchContext` e por `TenantResolverService` sem ciclo de imports.
abstract final class ChurchTenantOverride {
  ChurchTenantOverride._();

  /// Tenant escolhido no seletor "Trocar de igreja" (só operadores globais).
  ///
  /// `null` para toda a gente — quem não usa o seletor não é afetado por nada
  /// deste ficheiro.
  static String? explicit;

  static final RegExp _canonico = RegExp(r'^igreja_[a-z0-9_]+$');

  /// Ids que o app já viu como documento real de igreja.
  ///
  /// Alimentado por quem lê a fonte autoritativa: o índice `public_church_slugs`
  /// (site público) e a lista do seletor de igrejas. No site público não há
  /// operador logado, portanto [explicit] é `null` e sem este registo o id
  /// `igreta_batista_nacional_alianca` continuava a ser rejeitado — a página
  /// da igreja não montava.
  static final Set<String> _conhecidos = <String>{};

  /// Regista um id vindo de fonte autoritativa do Firestore.
  static void registerKnown(String? id) {
    final t = (id ?? '').trim();
    if (t.isEmpty) return;
    _conhecidos.add(t);
  }

  /// `true` quando [raw] pode ser usado directamente como `igrejas/{id}`.
  ///
  /// Aceita o padrão canónico **ou** o tenant escolhido a dedo, seja qual for
  /// o formato do id.
  static bool isChurchDocId(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return false;
    final forced = explicit?.trim() ?? '';
    if (forced.isNotEmpty && t == forced) return true;
    if (_conhecidos.contains(t)) return true;
    return _canonico.hasMatch(t);
  }

  /// Tenant escolhido, ou `null` quando o operador está na própria igreja.
  static String? get forcedOrNull {
    final t = explicit?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}
