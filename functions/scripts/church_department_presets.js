/**
 * Lista base oficial: 11 departamentos (igual ao app Flutter:
 * lib/services/church_departments_presets_data.dart e lib/core/department_template.dart).
 * Scripts locais (ex.: reset-departamentos-igreja.js) não devem usar catálogo expandido.
 */
module.exports = [
  { key: "pastoral", label: "Pastoral", iconKey: "pastoral", c1: 0xff0d47a1, c2: 0xff1976d2, description: "Direção espiritual e pastoreio" },
  { key: "louvor", label: "Louvor", iconKey: "louvor", c1: 0xffff6f00, c2: 0xffffa726, description: "Adoração e ministério de música" },
  { key: "jovens", label: "Jovens", iconKey: "jovens", c1: 0xffff5722, c2: 0xffff7043, description: "Ministério com jovens" },
  { key: "criancas", label: "Crianças", iconKey: "criancas", c1: 0xff00acc1, c2: 0xff4dd0e1, description: "Ministério infantil" },
  { key: "evangelismo", label: "Evangelismo", iconKey: "evangelismo", c1: 0xff6a1b9a, c2: 0xffab47bc, description: "Alcance e novos convertidos" },
  { key: "intercessao", label: "Intercessão", iconKey: "intercessao", c1: 0xffe53935, c2: 0xffff5252, description: "Oração e intercessão" },
  { key: "media", label: "Mídia", iconKey: "media", c1: 0xff1565c0, c2: 0xff42a5f5, description: "Som, imagem e comunicação digital" },
  { key: "recepcao", label: "Recepção", iconKey: "recepcao", c1: 0xffff9800, c2: 0xffffb74d, description: "Boas-vindas e acolhimento" },
  { key: "finance", label: "Financeiro", iconKey: "finance", c1: 0xff37474f, c2: 0xff546e7a, description: "Recursos e tesouraria" },
  { key: "escola_biblica", label: "Escola Bíblica", iconKey: "escola_biblica", c1: 0xff00695c, c2: 0xff26a69a, description: "Ensino da Palavra e EBD" },
  { key: "varoes", label: "Varões", iconKey: "varoes", c1: 0xff283593, c2: 0xff3f51b5, description: "Ministério com homens" },
];
