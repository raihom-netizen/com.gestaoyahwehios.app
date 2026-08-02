/// Mensagens simples para o utilizador (sem dump técnico do TDLib).
String formatTdlibErrorForUser(Object error) {
  // Alguns wrappers TDLib fazem toString() = "Instance of 'Error'" — ler campos.
  String raw = error.toString();
  try {
    final dyn = error as dynamic;
    final msg = dyn.message?.toString();
    final code = dyn.code?.toString();
    if (msg != null && msg.trim().isNotEmpty) {
      raw = 'code: ${code ?? ''} message: $msg';
    }
  } catch (_) {}
  final lower = raw.toLowerCase();

  if (lower.contains('inputfile is not specified') ||
      lower.contains('input file is not specified')) {
    return 'Não foi possível anexar o ficheiro. Escolha a foto ou o vídeo de novo.';
  }
  if (lower.contains('supergroup') &&
      (lower.contains('inputfile') || lower.contains('location'))) {
    return 'Não foi possível criar o grupo. Tente de novo em alguns segundos.';
  }
  if (lower.contains('code: 404') ||
      lower.contains('not found') ||
      lower.contains('não encontrado') ||
      lower.contains('nao encontrado')) {
    return 'Contato não encontrado no Telegram. Confira se o telefone do cadastro '
        'é o mesmo da conta Telegram do membro.';
  }
  if (lower.contains('code: 400') && lower.contains('phone')) {
    return 'Telefone inválido para o Telegram. Atualize o cadastro do membro.';
  }
  if (lower.contains('ainda não está pronto') ||
      lower.contains('ainda nao esta pronto') ||
      lower.contains('not ready')) {
    return 'O chat ainda está a conectar. Aguarde uns segundos e tente de novo.';
  }
  if (lower.contains('permission') || lower.contains('forbidden')) {
    return 'Sem permissão neste chat. Peça à gestão para o adicionar ao grupo.';
  }
  if (lower.contains('flood') || lower.contains('too many')) {
    return 'Muitas tentativas. Aguarde um minuto e tente novamente.';
  }
  if (lower.contains('network') || lower.contains('timeout')) {
    return 'Falha de rede. Verifique a internet e tente de novo.';
  }

  // StateError / ArgumentError já com mensagem curta em português.
  if (error is StateError || error is ArgumentError) {
    final m = error is StateError
        ? error.message
        : (error as ArgumentError).message?.toString();
    if (m != null && m.trim().isNotEmpty && m.length < 160 && !m.contains('{@type')) {
      return m.trim();
    }
  }

  return 'Não foi possível concluir. Tente novamente.';
}
