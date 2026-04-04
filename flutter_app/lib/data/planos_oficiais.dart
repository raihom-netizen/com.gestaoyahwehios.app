/// Planos oficiais — mesma lista do site de divulgação.
/// Usado no painel igreja (Assinatura) e no site público para exibição consistente.

class PlanoOficial {
  final String id;
  final String name;
  final String members;
  /// Limite máximo de membros do plano (para controle e avisos).
  final int maxMembers;
  final double? monthlyPrice;
  final bool featured;
  final String? note;

  const PlanoOficial({
    required this.id,
    required this.name,
    required this.members,
    required this.maxMembers,
    this.monthlyPrice,
    this.featured = false,
    this.note,
  });

  /// Preço anual (12 por 10): 10 × mensal.
  double? get annualPrice =>
      monthlyPrice != null ? monthlyPrice! * 10 : null;
}

const List<PlanoOficial> planosOficiais = [
  PlanoOficial(
    id: 'inicial',
    name: 'Plano Inicial',
    members: 'Até 100 membros',
    maxMembers: 100,
    monthlyPrice: 49.90,
  ),
  PlanoOficial(
    id: 'essencial',
    name: 'Plano Essencial',
    members: '100 a 150 membros',
    maxMembers: 150,
    monthlyPrice: 59.90,
    featured: true,
  ),
  PlanoOficial(
    id: 'intermediario',
    name: 'Plano Intermediário',
    members: '150 a 250 membros',
    maxMembers: 250,
    monthlyPrice: 69.90,
  ),
  PlanoOficial(
    id: 'avancado',
    name: 'Plano Avançado',
    members: '250 a 350 membros',
    maxMembers: 350,
    monthlyPrice: 89.90,
  ),
  PlanoOficial(
    id: 'profissional',
    name: 'Plano Profissional',
    members: '350 a 400 membros',
    maxMembers: 400,
    monthlyPrice: 99.90,
  ),
  PlanoOficial(
    id: 'premium',
    name: 'Plano Premium',
    members: '400 a 500 membros',
    maxMembers: 500,
    monthlyPrice: 169.90,
  ),
  PlanoOficial(
    id: 'premium_plus',
    name: 'Plano Premium Plus',
    members: '500 a 600 membros',
    maxMembers: 600,
    monthlyPrice: 189.90,
  ),
  PlanoOficial(
    id: 'corporativo',
    name: 'Plano Corporativo',
    members: 'Acima de 600 membros',
    maxMembers: 10000,
    monthlyPrice: null,
    note: 'Valor a combinar',
  ),
];
