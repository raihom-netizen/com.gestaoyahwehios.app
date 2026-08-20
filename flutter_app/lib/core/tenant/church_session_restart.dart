import 'package:flutter/foundation.dart';

/// Reinício de sessão do painel — o mesmo efeito de entrar de novo.
///
/// Trocar de igreja mexe em tudo: contexto, permissões, caches, e em cada
/// módulo que já esteja montado com os dados da igreja anterior. Corrigir isso
/// módulo a módulo foi tentado três vezes e a cada volta sobrava um ecrã a
/// mostrar a igreja errada — porque basta **um** widget guardar o id antigo.
///
/// Aqui o caminho é outro: em vez de convencer cada módulo a esquecer o que
/// tinha, deita-se abaixo a árvore inteira e reconstrói-se do zero, exatamente
/// como acontece depois de um login. Quem escolhe a igreja não fica a torcer
/// para que todos os ecrãs se atualizem — nenhum deles sobrevive à troca.
///
/// **Não é um reload do browser.** A app não se recarrega sozinha na web (é
/// regra do produto); o que muda é a chave da raiz, e o Flutter descarta e
/// recria todo o estado. O mesmo código serve web, Android e iOS.
abstract final class ChurchSessionRestart {
  ChurchSessionRestart._();

  /// Muda a cada reinício. A raiz da app usa isto como `Key`.
  static final ValueNotifier<int> epoch = ValueNotifier<int>(0);

  /// Reconstrói a app inteira. Chamar **depois** de o novo tenant estar
  /// escolhido e os caches purgados, senão a árvore nova nasce com os dados
  /// velhos ainda em memória.
  static void reiniciar() => epoch.value = epoch.value + 1;
}
