/// Domínios usados para gerar ícones offline (`tool/fetch_bank_brand_icons.dart`).
/// Não depende do Flutter — pode ser importado pelo script em `tool/`.
const Map<String, String> kFinanceBankFaviconHosts = {
  'bradesco': 'www.bradesco.com.br',
  'itau': 'www.itau.com.br',
  'caixa': 'www.caixa.gov.br',
  'nubank': 'www.nubank.com.br',
  'c6': 'www.c6bank.com.br',
  'santander': 'www.santander.com.br',
  'bb': 'www.bb.com.br',
  'mercadopago': 'www.mercadopago.com.br',
  'inter': 'www.bancointer.com.br',
  'sicoob': 'www.sicoob.com.br',
  'sicredi': 'www.sicredi.com.br',
  'original': 'www.original.com.br',
  'btg': 'www.btgpactual.com',
  'xp': 'www.xpi.com.br',
  'picpay': 'picpay.com',
  'stone': 'www.stone.com.br',
  'cielo': 'www.cielo.com.br',
  'pagbank': 'pagbank.com.br',
  'neon': 'neon.com.br',
  'will': 'willbank.com.br',
};

/// `id` do preset → nome do arquivo em `assets/images/banks/` quando difere do id
/// (a maioria bate direto, ex.: `nubank` → `nubank.png`).
const Map<String, String> _kFinanceBankAssetFileOverrides = {
  'bb': 'banco_do_brasil',
  'original': 'banco_original',
  'c6': 'c6_bank',
  'mercadopago': 'mercado_pago',
};

/// Miniatura embutida no app — pasta real do projeto é `assets/images/banks/`
/// (não `bank_brands/`, que nunca existiu aqui nem está declarada no pubspec).
String? financeBankBrandAssetPath(String presetId) {
  if (!kFinanceBankFaviconHosts.containsKey(presetId)) return null;
  final file = _kFinanceBankAssetFileOverrides[presetId] ?? presetId;
  return 'assets/images/banks/$file.png';
}
