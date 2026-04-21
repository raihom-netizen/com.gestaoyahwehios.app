/// Bancos comuns no Brasil (código COMPE/FEBRABAN quando aplicável) — seleção em cadastro de contas.
class BrasilBancoOption {
  final String codigo;
  final String nome;

  const BrasilBancoOption({required this.codigo, required this.nome});

  String get label => codigo.isEmpty ? nome : '$codigo — $nome';

  @override
  bool operator ==(Object other) =>
      other is BrasilBancoOption &&
      other.codigo == codigo &&
      other.nome == nome;

  @override
  int get hashCode => Object.hash(codigo, nome);
}

class BrasilBancoBranding {
  final String slug;
  final int colorHex;
  final String initials;
  final String? miniLogoAssetPath;

  const BrasilBancoBranding({
    required this.slug,
    required this.colorHex,
    required this.initials,
    required this.miniLogoAssetPath,
  });
}

const BrasilBancoBranding kBrasilBancoBrandingFallback = BrasilBancoBranding(
  slug: 'generic',
  colorHex: 0xFF2563EB,
  initials: 'BK',
  miniLogoAssetPath: null,
);

const Map<String, BrasilBancoBranding> _kBrasilBancoBrandingByCode = {
  '001': BrasilBancoBranding(
    slug: 'banco_do_brasil',
    colorHex: 0xFFF9D300,
    initials: 'BB',
    miniLogoAssetPath: 'assets/images/banks/banco_do_brasil.png',
  ),
  '033': BrasilBancoBranding(
    slug: 'santander',
    colorHex: 0xFFEC0000,
    initials: 'ST',
    miniLogoAssetPath: 'assets/images/banks/santander.png',
  ),
  '104': BrasilBancoBranding(
    slug: 'caixa',
    colorHex: 0xFF0066B3,
    initials: 'CX',
    miniLogoAssetPath: 'assets/images/banks/caixa.png',
  ),
  '237': BrasilBancoBranding(
    slug: 'bradesco',
    colorHex: 0xFFCC092F,
    initials: 'BR',
    miniLogoAssetPath: 'assets/images/banks/bradesco.png',
  ),
  '341': BrasilBancoBranding(
    slug: 'itau',
    colorHex: 0xFFEC7000,
    initials: 'IT',
    miniLogoAssetPath: 'assets/images/banks/itau.png',
  ),
  '077': BrasilBancoBranding(
    slug: 'inter',
    colorHex: 0xFFFF7A00,
    initials: 'IN',
    miniLogoAssetPath: 'assets/images/banks/inter.png',
  ),
  '260': BrasilBancoBranding(
    slug: 'nubank',
    colorHex: 0xFF8A05BE,
    initials: 'NU',
    miniLogoAssetPath: 'assets/images/banks/nubank.png',
  ),
  '336': BrasilBancoBranding(
    slug: 'c6_bank',
    colorHex: 0xFF111111,
    initials: 'C6',
    miniLogoAssetPath: 'assets/images/banks/c6_bank.png',
  ),
  '422': BrasilBancoBranding(
    slug: 'safra',
    colorHex: 0xFF1F2937,
    initials: 'SF',
    miniLogoAssetPath: 'assets/images/banks/safra.png',
  ),
  '041': BrasilBancoBranding(
    slug: 'banrisul',
    colorHex: 0xFF0057A8,
    initials: 'BR',
    miniLogoAssetPath: 'assets/images/banks/banrisul.png',
  ),
  '047': BrasilBancoBranding(
    slug: 'banese',
    colorHex: 0xFF0EA5E9,
    initials: 'BN',
    miniLogoAssetPath: 'assets/images/banks/banese.png',
  ),
  '070': BrasilBancoBranding(
    slug: 'brb',
    colorHex: 0xFF1E3A8A,
    initials: 'BRB',
    miniLogoAssetPath: 'assets/images/banks/brb.png',
  ),
  '085': BrasilBancoBranding(
    slug: 'ailos',
    colorHex: 0xFF0F766E,
    initials: 'AI',
    miniLogoAssetPath: 'assets/images/banks/ailos.png',
  ),
  '212': BrasilBancoBranding(
    slug: 'banco_original',
    colorHex: 0xFF047857,
    initials: 'OR',
    miniLogoAssetPath: 'assets/images/banks/banco_original.png',
  ),
  '218': BrasilBancoBranding(
    slug: 'bs2',
    colorHex: 0xFF2563EB,
    initials: 'BS',
    miniLogoAssetPath: 'assets/images/banks/bs2.png',
  ),
  '224': BrasilBancoBranding(
    slug: 'fibra',
    colorHex: 0xFF6D28D9,
    initials: 'FB',
    miniLogoAssetPath: 'assets/images/banks/fibra.png',
  ),
  '246': BrasilBancoBranding(
    slug: 'banco_abc_brasil',
    colorHex: 0xFF1D4ED8,
    initials: 'AB',
    miniLogoAssetPath: 'assets/images/banks/banco_abc_brasil.png',
  ),
  '748': BrasilBancoBranding(
    slug: 'sicredi',
    colorHex: 0xFF65B32E,
    initials: 'SI',
    miniLogoAssetPath: 'assets/images/banks/sicredi.png',
  ),
  '756': BrasilBancoBranding(
    slug: 'sicoob',
    colorHex: 0xFF00A859,
    initials: 'SC',
    miniLogoAssetPath: 'assets/images/banks/sicoob.png',
  ),
  '655': BrasilBancoBranding(
    slug: 'votorantim',
    colorHex: 0xFF1E40AF,
    initials: 'BV',
    miniLogoAssetPath: 'assets/images/banks/votorantim.png',
  ),
  '389': BrasilBancoBranding(
    slug: 'banco_mercantil',
    colorHex: 0xFFB91C1C,
    initials: 'BM',
    miniLogoAssetPath: 'assets/images/banks/banco_mercantil.png',
  ),
  '323': BrasilBancoBranding(
    slug: 'mercado_pago',
    colorHex: 0xFF00A1EA,
    initials: 'MP',
    miniLogoAssetPath: 'assets/images/banks/mercado_pago.png',
  ),
  '380': BrasilBancoBranding(
    slug: 'picpay',
    colorHex: 0xFF21C25E,
    initials: 'PP',
    miniLogoAssetPath: 'assets/images/banks/picpay.png',
  ),
};

BrasilBancoBranding brasilBancoBrandingFor({
  String? codigo,
  String? nome,
}) {
  final code = (codigo ?? '').trim();
  if (code.isNotEmpty && _kBrasilBancoBrandingByCode.containsKey(code)) {
    return _kBrasilBancoBrandingByCode[code]!;
  }
  final n = (nome ?? '').toLowerCase();
  if (n.contains('nubank')) return _kBrasilBancoBrandingByCode['260']!;
  if (n.contains('itaú') || n.contains('itau')) {
    return _kBrasilBancoBrandingByCode['341']!;
  }
  if (n.contains('bradesco')) return _kBrasilBancoBrandingByCode['237']!;
  if (n.contains('santander')) return _kBrasilBancoBrandingByCode['033']!;
  if (n.contains('caixa')) return _kBrasilBancoBrandingByCode['104']!;
  if (n.contains('banco do brasil')) return _kBrasilBancoBrandingByCode['001']!;
  if (n.contains('inter')) return _kBrasilBancoBrandingByCode['077']!;
  if (n.contains('mercado pago')) return _kBrasilBancoBrandingByCode['323']!;
  if (n.contains('picpay')) return _kBrasilBancoBrandingByCode['380']!;
  if (n.contains('sicoob')) return _kBrasilBancoBrandingByCode['756']!;
  if (n.contains('sicredi')) return _kBrasilBancoBrandingByCode['748']!;
  if (n.contains('safra')) return _kBrasilBancoBrandingByCode['422']!;
  if (n.contains('c6')) return _kBrasilBancoBrandingByCode['336']!;
  if (n.contains('original')) return _kBrasilBancoBrandingByCode['212']!;
  if (n.contains('brb') || n.contains('brasilia')) {
    return _kBrasilBancoBrandingByCode['070']!;
  }
  if (n.contains('banrisul')) return _kBrasilBancoBrandingByCode['041']!;
  if (n.contains('banese') || n.contains('sergipe')) {
    return _kBrasilBancoBrandingByCode['047']!;
  }
  if (n.contains('ailos')) return _kBrasilBancoBrandingByCode['085']!;
  if (n.contains('bs2')) return _kBrasilBancoBrandingByCode['218']!;
  if (n.contains('fibra')) return _kBrasilBancoBrandingByCode['224']!;
  if (n.contains('abc brasil')) return _kBrasilBancoBrandingByCode['246']!;
  if (n.contains('votorantim') || n == 'bv' || n.contains('banco bv')) {
    return _kBrasilBancoBrandingByCode['655']!;
  }
  if (n.contains('mercantil')) return _kBrasilBancoBrandingByCode['389']!;
  return kBrasilBancoBrandingFallback;
}

/// Lista enxuta; "Outro / Caixa interno" para caixas físicas da igreja.
const List<BrasilBancoOption> kBrasilBancosComuns = [
  BrasilBancoOption(codigo: '001', nome: 'Banco do Brasil'),
  BrasilBancoOption(codigo: '033', nome: 'Santander'),
  BrasilBancoOption(codigo: '104', nome: 'Caixa Econômica Federal'),
  BrasilBancoOption(codigo: '237', nome: 'Bradesco'),
  BrasilBancoOption(codigo: '341', nome: 'Itaú'),
  BrasilBancoOption(codigo: '077', nome: 'Inter'),
  BrasilBancoOption(codigo: '260', nome: 'Nubank'),
  BrasilBancoOption(codigo: '336', nome: 'C6 Bank'),
  BrasilBancoOption(codigo: '422', nome: 'Safra'),
  BrasilBancoOption(codigo: '041', nome: 'Banrisul'),
  BrasilBancoOption(codigo: '047', nome: 'Banco do Estado de Sergipe'),
  BrasilBancoOption(codigo: '070', nome: 'BRB — Banco de Brasília'),
  BrasilBancoOption(codigo: '085', nome: 'Cooperativa Central Ailos'),
  BrasilBancoOption(codigo: '212', nome: 'Banco Original'),
  BrasilBancoOption(codigo: '218', nome: 'BS2'),
  BrasilBancoOption(codigo: '224', nome: 'Fibra'),
  BrasilBancoOption(codigo: '246', nome: 'Banco ABC Brasil'),
  BrasilBancoOption(codigo: '748', nome: 'Sicredi'),
  BrasilBancoOption(codigo: '756', nome: 'Sicoob'),
  BrasilBancoOption(codigo: '655', nome: 'Votorantim'),
  BrasilBancoOption(codigo: '389', nome: 'Banco Mercantil'),
  BrasilBancoOption(codigo: '323', nome: 'Mercado Pago'),
  BrasilBancoOption(codigo: '380', nome: 'PicPay'),
  BrasilBancoOption(codigo: '', nome: 'Outro banco / instituição'),
  BrasilBancoOption(codigo: '', nome: 'Caixa interno / numerário (sem banco)'),
];
