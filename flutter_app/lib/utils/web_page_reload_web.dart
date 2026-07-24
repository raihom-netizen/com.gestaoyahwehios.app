// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const String _kHardReloadAtKey = 'gyh_hard_reload_at';
const String _kHardReloadCountKey = 'gyh_hard_reload_count';

/// Máx. 1 hard reload a cada 3 min — evita loop `?_r=` a trocar e splash infinito.
const int _kHardReloadCooldownMs = 180000;

/// Recarrega a aba (recuperação Firestore JS). URL **estável** (sem spam de `_r=`).
void reloadWebPageHard() {
  try {
    final ss = html.window.sessionStorage;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = int.tryParse(ss[_kHardReloadAtKey] ?? '') ?? 0;
    if (last > 0 && (now - last) < _kHardReloadCooldownMs) {
      // Já tentámos — não voltar a navegar (quebra o loop do painel).
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
