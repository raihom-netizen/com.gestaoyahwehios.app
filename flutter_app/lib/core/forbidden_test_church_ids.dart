/// IDs/slugs de igrejas de teste — nunca criar no Master nem deixar voltar.
library;

const Set<String> kForbiddenTestChurchIds = {
  'igreja_de_teste',
  'igreja_de_teste_1',
  'igreja_de_teste_2',
  'igreja_de_teste_3',
  'teste_apple',
  'igreja_teste',
  'igreja-teste',
};

bool isForbiddenTestChurchId(String? id) {
  final raw = (id ?? '').trim().toLowerCase();
  if (raw.isEmpty) return false;
  if (kForbiddenTestChurchIds.contains(raw)) return true;
  if (RegExp(r'^igreja_de_teste(_\d+)?$').hasMatch(raw)) return true;
  if (RegExp(r'^teste_apple(_\d+)?$').hasMatch(raw)) return true;
  if (RegExp(r'^igreja_teste(_\d+)?$').hasMatch(raw)) return true;
  return false;
}
