// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const String _kHardReloadAtKey = 'gyh_hard_reload_at';
const String _kHardReloadCountKey = 'gyh_hard_reload_count';

/// Máx. 1 hard reload a cada 3 min — evita loop `?_r=` a trocar e splash infinito.
const int _kHardReloadCooldownMs = 180000;

/// Recarrega a aba (recuperação Firestore JS). URL **estável** (sem spam de `_r=`).
///
/// [force]: ignora o cooldown de 3min. Usado quando o cliente Firestore foi
/// TERMINADO (`failed-precondition: client already terminated`) — nesse estado
/// só um reload recupera, e a página nova re-inicializa o cliente (não há risco
/// de loop pelo mesmo motivo). NÃO use force no assertion comum (aí o cooldown
/// evita reload em cadeia).
void reloadWebPageHard({bool force = false}) {
  try {
    final ss = html.window.sessionStorage;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = int.tryParse(ss[_kHardReloadAtKey] ?? '') ?? 0;
    // force (cliente terminado): não bypassa 100% — usa um gap mínimo de 15s
    // para recuperar rápido SEM virar loop apertado se o terminate reincidir.
    final cooldown = force ? 15000 : _kHardReloadCooldownMs;
    if (last > 0 && (now - last) < cooldown) {
      // Já tentámos há pouco — não voltar a navegar (quebra o loop do painel).
      return;
    }
    final count = (int.tryParse(ss[_kHardReloadCountKey] ?? '') ?? 0) + 1;
    ss[_kHardReloadCountKey] = '$count';
    ss[_kHardReloadAtKey] = '$now';

    final loc = html.window.location;
    final path = loc.pathname ?? '/';
    final pathNorm = path.endsWith('/') ? path : '$path/';
    final base = loc.origin ?? '';
    // URL limpa e estável — sem `?_r=` a mudar a cada F5 forçado.
    final clean = '$base$pathNorm';
    final href = loc.href ?? '';
    if (href.contains('_r=') || href.contains('gyhUpd=')) {
      // Já estamos numa URL de cache-bust: reload simples, não gerar novo query.
      loc.replace(clean);
      return;
    }
    // Um único reload estável (sem query).
    loc.reload();
  } catch (_) {
    try {
      html.window.location.reload();
    } catch (_) {}
  }
}
