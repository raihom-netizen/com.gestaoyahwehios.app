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
