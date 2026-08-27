import 'package:flutter/material.dart';

/// Escala de acesso da igreja — **níveis 1 a 5**.
///
/// Substitui a antiga hierarquia livre de 0 a 100 (100, 88, 72, 65, 55, 12),
/// que ninguém conseguia ler: dois cargos com 65 e 72 não diziam a ninguém
/// quem podia mais. Aqui o número é a própria regra.
///
/// | Nível | Cargo | O que pode |
/// |---|---|---|
/// | 1 | Membro / Congregado | ver a agenda (sem editar), o seu cartão e os aniversariantes |
/// | 2 | Líder de departamento | gerar escalas; editar os eventos e avisos que ele criou; **sem** financeiro |
/// | 3 | Secretário(a) | editar eventos, avisos, agenda, escalas e fichas; **sem** financeiro |
/// | 4 | Tesoureiro(a) | tudo, **com** financeiro, menos dar acesso de administrador |
/// | 5 | Pastor, gestor, adm e pastor auxiliar | tudo, incluindo financeiro e autorizar outros |
enum ChurchCargoNivel {
  membro(
    valor: 1,
    titulo: 'Membro / Congregado',
    resumo: 'Vê a agenda, o próprio cartão e os aniversariantes. Não edita.',
    cor: Color(0xFF64748B),
    icone: Icons.person_rounded,
  ),
  liderDepartamento(
    valor: 2,
    titulo: 'Líder de departamento',
    resumo:
        'Gera escalas e edita os eventos e avisos que ele mesmo criou. '
        'Sem acesso ao Financeiro.',
    cor: Color(0xFF7C3AED),
    icone: Icons.groups_rounded,
  ),
  secretario(
    valor: 3,
    titulo: 'Secretário(a)',
    resumo:
        'Edita eventos, avisos, agenda, escalas e fichas de membros. '
        'Sem acesso ao Financeiro.',
    cor: Color(0xFF0891B2),
    icone: Icons.edit_document,
  ),
  tesoureiro(
    valor: 4,
    titulo: 'Tesoureiro(a)',
    resumo:
        'Pode tudo, incluindo o Financeiro — menos dar acesso de '
        'administrador a outros membros.',
    cor: Color(0xFF059669),
    icone: Icons.account_balance_wallet_rounded,
  ),
  pastorGestor(
    valor: 5,
    titulo: 'Pastor / Gestor / Adm',
    resumo:
        'Pode tudo: Financeiro, remover, e autorizar outros membros. '
        'Inclui o pastor auxiliar.',
    cor: Color(0xFF1D4ED8),
    icone: Icons.shield_rounded,
  );

  const ChurchCargoNivel({
    required this.valor,
    required this.titulo,
    required this.resumo,
    required this.cor,
    required this.icone,
  });

  final int valor;
  final String titulo;
  final String resumo;
  final Color cor;
  final IconData icone;

  /// Traz qualquer número para a escala 1–5.
  ///
  /// Os cargos gravados antes desta mudança usam 0–100; a conversão mantém a
  /// ordem de quem podia mais (100/88 → 5, 72 → 3, 65 → 4, 55 → 2, resto → 1)
  /// para que nenhuma igreja perca ou ganhe acesso na migração.
  static int normalizar(int? bruto) {
    final v = bruto ?? 1;
    if (v >= 1 && v <= 5) return v;
    if (v >= 80) return 5; // pastor presidente (100) e auxiliar (88)
    if (v >= 66) return 3; // secretário (72)
    if (v >= 60) return 4; // tesoureiro (65)
    if (v >= 40) return 2; // líder de departamento (55)
    return 1; // membro (12) e tudo o que sobrar
  }

  static ChurchCargoNivel de(int? bruto) {
    final v = normalizar(bruto);
    return ChurchCargoNivel.values.firstWhere(
      (n) => n.valor == v,
      orElse: () => ChurchCargoNivel.membro,
    );
  }

  /// Modelo de permissões que o nível sugere ao criar/editar um cargo.
  String get templatePadrao => switch (this) {
    ChurchCargoNivel.membro => 'membro',
    ChurchCargoNivel.liderDepartamento => 'lider_departamento',
    ChurchCargoNivel.secretario => 'secretario',
    ChurchCargoNivel.tesoureiro => 'tesoureiro',
    ChurchCargoNivel.pastorGestor => 'pastor_presidente',
  };

  bool get veFinanceiro =>
      this == ChurchCargoNivel.tesoureiro ||
      this == ChurchCargoNivel.pastorGestor;

  /// Só o nível 5 autoriza outros membros (mexer no catálogo de cargos).
  bool get autorizaOutros => this == ChurchCargoNivel.pastorGestor;
}
