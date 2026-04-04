// ignore_for_file: lines_longer_than_80_chars

/// Presets de departamentos para novas igrejas (ids únicos + ícone visual existente).
/// [iconKey] referencia chaves já mapeadas em [DepartmentsPage] (_iconOptions / _themeOptions).
const List<Map<String, dynamic>> kChurchDepartmentPresetRows = [
  // —— Legado (mantém compatibilidade) ——
  {'key': 'auxiliares', 'label': 'Auxiliares', 'iconKey': 'auxiliares', 'c1': 0xFF4A148C, 'c2': 0xFF6A1B9A, 'description': 'Geral'},
  {'key': 'comunicacao', 'label': 'Comunicação', 'iconKey': 'comunicacao', 'c1': 0xFF006064, 'c2': 0xFF0097A7, 'description': 'Tecnologia e comunicação'},
  {'key': 'criancas', 'label': 'Crianças', 'iconKey': 'criancas', 'c1': 0xFF00BCD4, 'c2': 0xFF80DEEA, 'description': 'Infantil e jovens'},
  {'key': 'diaconal', 'label': 'Diaconal', 'iconKey': 'diaconal', 'c1': 0xFF5D4037, 'c2': 0xFF8D6E63, 'description': 'Administração e liderança'},
  {'key': 'evangelismo', 'label': 'Evangelismo', 'iconKey': 'evangelismo', 'c1': 0xFF6A1B9A, 'c2': 0xFF7B1FA2, 'description': 'Evangelismo e missões'},
  {'key': 'finance', 'label': 'Financeiro', 'iconKey': 'finance', 'c1': 0xFF546E7A, 'c2': 0xFF90A4AE, 'description': 'Financeiro'},
  {'key': 'intercessao', 'label': 'Intercessão', 'iconKey': 'intercessao', 'c1': 0xFFB71C1C, 'c2': 0xFFD32F2F, 'description': 'Recepção e apoio'},
  {'key': 'jovens', 'label': 'Jovens', 'iconKey': 'jovens', 'c1': 0xFF6A1B9A, 'c2': 0xFFAB47BC, 'description': 'Infantil e jovens'},
  {'key': 'louvor', 'label': 'Louvor', 'iconKey': 'louvor', 'c1': 0xFFF57C00, 'c2': 0xFFFFA726, 'description': 'Louvor e adoração'},
  {'key': 'media', 'label': 'Mídia', 'iconKey': 'media', 'c1': 0xFF1976D2, 'c2': 0xFF64B5F6, 'description': 'Tecnologia e comunicação'},
  {'key': 'missionarios', 'label': 'Missionários', 'iconKey': 'missionarios', 'c1': 0xFF455A64, 'c2': 0xFF90A4AE, 'description': 'Evangelismo e missões'},
  {'key': 'mulheres', 'label': 'Mulheres', 'iconKey': 'mulheres', 'c1': 0xFFC2185B, 'c2': 0xFFF48FB1, 'description': 'Família e grupos'},
  {'key': 'obreiros', 'label': 'Obreiros', 'iconKey': 'obreiros', 'c1': 0xFF4E342E, 'c2': 0xFF795548, 'description': 'Estrutura e manutenção'},
  {'key': 'oracao', 'label': 'Oração', 'iconKey': 'oracao', 'c1': 0xFF558B2F, 'c2': 0xFFAED581, 'description': 'Recepção e apoio'},
  {'key': 'pastoral', 'label': 'Pastoral', 'iconKey': 'pastoral', 'c1': 0xFF2E7D32, 'c2': 0xFF81C784, 'description': 'Administração e liderança'},
  {'key': 'presbiteros', 'label': 'Presbíteros', 'iconKey': 'presbiteros', 'c1': 0xFF0D47A1, 'c2': 0xFF1565C0, 'description': 'Administração e liderança'},
  {'key': 'recepcao', 'label': 'Recepção', 'iconKey': 'recepcao', 'c1': 0xFFE64A19, 'c2': 0xFFFF8A65, 'description': 'Recepção e apoio'},
  {'key': 'secretarios', 'label': 'Secretários', 'iconKey': 'secretarios', 'c1': 0xFF283593, 'c2': 0xFF3949AB, 'description': 'Administração e liderança'},
  {'key': 'social', 'label': 'Social', 'iconKey': 'social', 'c1': 0xFF00695C, 'c2': 0xFF00897B, 'description': 'Assistência e cuidado'},
  {'key': 'tesouraria', 'label': 'Tesouraria', 'iconKey': 'tesouraria', 'c1': 0xFF1B5E20, 'c2': 0xFF2E7D32, 'description': 'Financeiro'},
  {'key': 'varoes', 'label': 'Varões', 'iconKey': 'varoes', 'c1': 0xFF0D47A1, 'c2': 0xFF1976D2, 'description': 'Família e grupos'},

  // —— 1. Administração e liderança ——
  {'key': 'adm_pastor_presidente', 'label': 'Pastor Presidente', 'iconKey': 'pastoral', 'c1': 0xFF1B5E20, 'c2': 0xFF2E7D32, 'description': 'Administração e liderança'},
  {'key': 'adm_pastor_auxiliar', 'label': 'Pastor Auxiliar', 'iconKey': 'pastoral', 'c1': 0xFF2E7D32, 'c2': 0xFF43A047, 'description': 'Administração e liderança'},
  {'key': 'adm_diaconos', 'label': 'Diáconos', 'iconKey': 'diaconal', 'c1': 0xFF5D4037, 'c2': 0xFF8D6E63, 'description': 'Administração e liderança'},
  {'key': 'adm_lideres_ministerio', 'label': 'Líderes de Ministério', 'iconKey': 'pastoral', 'c1': 0xFF33691E, 'c2': 0xFF558B2F, 'description': 'Administração e liderança'},
  {'key': 'adm_secretaria_igreja', 'label': 'Secretaria da Igreja', 'iconKey': 'secretarios', 'c1': 0xFF283593, 'c2': 0xFF3949AB, 'description': 'Administração e liderança'},
  {'key': 'adm_conselho', 'label': 'Conselho Administrativo', 'iconKey': 'presbiteros', 'c1': 0xFF0D47A1, 'c2': 0xFF1565C0, 'description': 'Administração e liderança'},

  // —— 2. Louvor e adoração ——
  {'key': 'louv_ministerio', 'label': 'Ministério de Louvor', 'iconKey': 'louvor', 'c1': 0xFFE65100, 'c2': 0xFFFF9800, 'description': 'Louvor e adoração'},
  {'key': 'louv_banda', 'label': 'Banda / Instrumentistas', 'iconKey': 'louvor', 'c1': 0xFFF57C00, 'c2': 0xFFFFB74D, 'description': 'Louvor e adoração'},
  {'key': 'louv_coral', 'label': 'Vocal / Coral', 'iconKey': 'louvor', 'c1': 0xFFFF6F00, 'c2': 0xFFFFCC80, 'description': 'Louvor e adoração'},
  {'key': 'louv_som', 'label': 'Equipe de Som', 'iconKey': 'media', 'c1': 0xFF1565C0, 'c2': 0xFF42A5F5, 'description': 'Louvor e adoração'},
  {'key': 'louv_midia_culto', 'label': 'Equipe de Mídia (telão / projeção)', 'iconKey': 'media', 'c1': 0xFF0D47A1, 'c2': 0xFF1976D2, 'description': 'Louvor e adoração'},
  {'key': 'louv_producao', 'label': 'Produção Musical', 'iconKey': 'louvor', 'c1': 0xFFEF6C00, 'c2': 0xFFFFA726, 'description': 'Louvor e adoração'},

  // —— 3. Ensino e discipulado ——
  {'key': 'ens_ebd', 'label': 'Escola Bíblica (EBD)', 'iconKey': 'pastoral', 'c1': 0xFF00695C, 'c2': 0xFF00897B, 'description': 'Ensino e discipulado'},
  {'key': 'ens_professores', 'label': 'Professores Bíblicos', 'iconKey': 'pastoral', 'c1': 0xFF00796B, 'c2': 0xFF26A69A, 'description': 'Ensino e discipulado'},
  {'key': 'ens_discipulado', 'label': 'Discipulado (novos convertidos)', 'iconKey': 'evangelismo', 'c1': 0xFF4527A0, 'c2': 0xFF7E57C2, 'description': 'Ensino e discipulado'},
  {'key': 'ens_formacao_lideres', 'label': 'Formação de Líderes', 'iconKey': 'pastoral', 'c1': 0xFF2E7D32, 'c2': 0xFF66BB6A, 'description': 'Ensino e discipulado'},
  {'key': 'ens_estudos', 'label': 'Estudos Bíblicos', 'iconKey': 'pastoral', 'c1': 0xFF004D40, 'c2': 0xFF00796B, 'description': 'Ensino e discipulado'},

  // —— 4. Família e grupos ——
  {'key': 'fam_casais', 'label': 'Ministério de Casais', 'iconKey': 'mulheres', 'c1': 0xFFAD1457, 'c2': 0xFFEC407A, 'description': 'Família e grupos'},
  {'key': 'fam_homens', 'label': 'Ministério de Homens', 'iconKey': 'varoes', 'c1': 0xFF0D47A1, 'c2': 0xFF42A5F5, 'description': 'Família e grupos'},
  {'key': 'fam_mulheres', 'label': 'Ministério de Mulheres', 'iconKey': 'mulheres', 'c1': 0xFFC2185B, 'c2': 0xFFF48FB1, 'description': 'Família e grupos'},
  {'key': 'fam_melhor_idade', 'label': 'Ministério da Melhor Idade', 'iconKey': 'pastoral', 'c1': 0xFF5D4037, 'c2': 0xFF8D6E63, 'description': 'Família e grupos'},
  {'key': 'fam_celulas', 'label': 'Pequenos Grupos / Células', 'iconKey': 'auxiliares', 'c1': 0xFF6A1B9A, 'c2': 0xFFAB47BC, 'description': 'Família e grupos'},

  // —— 5. Infantil e jovens ——
  {'key': 'inf_ministerio_infantil', 'label': 'Ministério Infantil', 'iconKey': 'criancas', 'c1': 0xFF00ACC1, 'c2': 0xFF4DD0E1, 'description': 'Infantil e jovens'},
  {'key': 'inf_bercario', 'label': 'Berçário', 'iconKey': 'criancas', 'c1': 0xFF0097A7, 'c2': 0xFF80DEEA, 'description': 'Infantil e jovens'},
  {'key': 'inf_adolescentes', 'label': 'Ministério de Adolescentes', 'iconKey': 'jovens', 'c1': 0xFF7B1FA2, 'c2': 0xFFBA68C8, 'description': 'Infantil e jovens'},

  // —— 6. Evangelismo e missões ——
  {'key': 'evg_local', 'label': 'Evangelismo Local', 'iconKey': 'evangelismo', 'c1': 0xFF6A1B9A, 'c2': 0xFF9C27B0, 'description': 'Evangelismo e missões'},
  {'key': 'evg_nacional', 'label': 'Missões Nacionais', 'iconKey': 'missionarios', 'c1': 0xFF37474F, 'c2': 0xFF78909C, 'description': 'Evangelismo e missões'},
  {'key': 'evg_internacional', 'label': 'Missões Internacionais', 'iconKey': 'missionarios', 'c1': 0xFF263238, 'c2': 0xFF546E7A, 'description': 'Evangelismo e missões'},
  {'key': 'evg_acoes_sociais', 'label': 'Ações Sociais (evangelismo)', 'iconKey': 'social', 'c1': 0xFF00695C, 'c2': 0xFF26A69A, 'description': 'Evangelismo e missões'},
  {'key': 'evg_visitas', 'label': 'Visitas e Acolhimento', 'iconKey': 'recepcao', 'c1': 0xFFD84315, 'c2': 0xFFFF8A65, 'description': 'Evangelismo e missões'},

  // —— 7. Recepção e apoio ——
  {'key': 'rec_boas_vindas', 'label': 'Recepção / Boas-vindas', 'iconKey': 'recepcao', 'c1': 0xFFE64A19, 'c2': 0xFFFFAB91, 'description': 'Recepção e apoio'},
  {'key': 'rec_apoio_culto', 'label': 'Apoio ao Culto', 'iconKey': 'auxiliares', 'c1': 0xFF5E35B1, 'c2': 0xFF9575CD, 'description': 'Recepção e apoio'},
  {'key': 'rec_ordem', 'label': 'Ordem / Organização', 'iconKey': 'obreiros', 'c1': 0xFF4E342E, 'c2': 0xFF8D6E63, 'description': 'Recepção e apoio'},

  // —— 8. Assistência e cuidado ——
  {'key': 'asst_social', 'label': 'Assistência Social', 'iconKey': 'social', 'c1': 0xFF004D40, 'c2': 0xFF00897B, 'description': 'Assistência e cuidado'},
  {'key': 'asst_aconselhamento', 'label': 'Aconselhamento', 'iconKey': 'pastoral', 'c1': 0xFF33691E, 'c2': 0xFF689F38, 'description': 'Assistência e cuidado'},
  {'key': 'asst_visitacao', 'label': 'Visitação (enfermos / membros)', 'iconKey': 'social', 'c1': 0xFF006064, 'c2': 0xFF00838F, 'description': 'Assistência e cuidado'},
  {'key': 'asst_apoio_espiritual', 'label': 'Apoio Espiritual', 'iconKey': 'oracao', 'c1': 0xFF33691E, 'c2': 0xFF7CB342, 'description': 'Assistência e cuidado'},

  // —— 9. Estrutura e manutenção ——
  {'key': 'est_limpeza', 'label': 'Limpeza', 'iconKey': 'obreiros', 'c1': 0xFF5D4037, 'c2': 0xFFA1887F, 'description': 'Estrutura e manutenção'},
  {'key': 'est_manutencao', 'label': 'Manutenção Predial', 'iconKey': 'obreiros', 'c1': 0xFF4E342E, 'c2': 0xFF795548, 'description': 'Estrutura e manutenção'},
  {'key': 'est_seguranca', 'label': 'Segurança', 'iconKey': 'obreiros', 'c1': 0xFF3E2723, 'c2': 0xFF6D4C41, 'description': 'Estrutura e manutenção'},
  {'key': 'est_patrimonio', 'label': 'Patrimônio', 'iconKey': 'finance', 'c1': 0xFF455A64, 'c2': 0xFF90A4AE, 'description': 'Estrutura e manutenção'},

  // —— 10. Tecnologia e comunicação ——
  {'key': 'tec_midias_sociais', 'label': 'Mídias Sociais', 'iconKey': 'comunicacao', 'c1': 0xFF00838F, 'c2': 0xFF00ACC1, 'description': 'Tecnologia e comunicação'},
  {'key': 'tec_design', 'label': 'Design / Artes', 'iconKey': 'media', 'c1': 0xFF0277BD, 'c2': 0xFF29B6F6, 'description': 'Tecnologia e comunicação'},
  {'key': 'tec_site_app', 'label': 'Site / Aplicativo', 'iconKey': 'comunicacao', 'c1': 0xFF006064, 'c2': 0xFF00BCD4, 'description': 'Tecnologia e comunicação'},
  {'key': 'tec_live', 'label': 'Transmissão ao vivo (live)', 'iconKey': 'media', 'c1': 0xFF0D47A1, 'c2': 0xFF42A5F5, 'description': 'Tecnologia e comunicação'},
  {'key': 'tec_foto_video', 'label': 'Fotografia / Vídeo', 'iconKey': 'media', 'c1': 0xFF01579B, 'c2': 0xFF039BE5, 'description': 'Tecnologia e comunicação'},

  // —— 11. Financeiro ——
  {'key': 'fin_dizimos', 'label': 'Dízimos e Ofertas', 'iconKey': 'tesouraria', 'c1': 0xFF1B5E20, 'c2': 0xFF43A047, 'description': 'Financeiro'},
  {'key': 'fin_controle', 'label': 'Controle Financeiro', 'iconKey': 'finance', 'c1': 0xFF37474F, 'c2': 0xFF78909C, 'description': 'Financeiro'},
  {'key': 'fin_prestacao_contas', 'label': 'Prestação de Contas', 'iconKey': 'secretarios', 'c1': 0xFF263238, 'c2': 0xFF546E7A, 'description': 'Financeiro'},

  // —— 12. Eventos ——
  {'key': 'evt_organizacao', 'label': 'Organização de Eventos', 'iconKey': 'auxiliares', 'c1': 0xFFFF8F00, 'c2': 0xFFFFCA28, 'description': 'Eventos'},
  {'key': 'evt_congressos', 'label': 'Congressos', 'iconKey': 'auxiliares', 'c1': 0xFFFF6F00, 'c2': 0xFFFFD54F, 'description': 'Eventos'},
  {'key': 'evt_conferencias', 'label': 'Conferências', 'iconKey': 'auxiliares', 'c1': 0xFFFFA000, 'c2': 0xFFFFE082, 'description': 'Eventos'},
  {'key': 'evt_festividades', 'label': 'Festividades', 'iconKey': 'louvor', 'c1': 0xFFF9A825, 'c2': 0xFFFFEE58, 'description': 'Eventos'},
];
