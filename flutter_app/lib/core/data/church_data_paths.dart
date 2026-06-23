/// Paths canónicos — **única** árvore Firestore do Gestão YAHWEH.
///
/// Raiz: `igrejas/{churchId}/`
abstract final class ChurchDataPaths {
  ChurchDataPaths._();

  static const String rootCollection = 'igrejas';

  // ─── Subcoleções operacionais ─────────────────────────────────────────────
  static const String membros = 'membros';
  static const String departamentos = 'departamentos';
  static const String cargos = 'cargos';
  static const String eventos = 'eventos';
  static const String avisos = 'avisos';
  static const String chats = 'chats';
  static const String patrimonio = 'patrimonio';
  static const String patrimonioInventarioHistorico =
      'patrimonio_inventario_historico';
  /// Coleção real no Firestore (módulo «financeiro»).
  static const String financeiro = 'finance';
  /// Log canônico de alterações no módulo financeiro.
  static const String financeLogs = 'finance_logs';
  /// Notificações de pagamento Mercado Pago espelhadas no tenant.
  static const String financeMpNotifications = 'finance_mp_notifications';
  static const String fornecedores = 'fornecedores';
  static const String escalas = 'escalas';
  static const String escalaTemplates = 'escala_templates';
  static const String agenda = 'agenda';
  static const String lideres = 'lideres';
  static const String administrativo = 'administrativo';
  static const String doacoes = 'doacoes';
  static const String mercadopago = 'mercadopago';
  /// Subcoleções Mercado Pago — separar config, transações, assinaturas e webhooks.
  static const String mercadopagoConfig = 'config';
  static const String mercadopagoTransacoes = 'transacoes';
  static const String mercadopagoAssinaturas = 'assinaturas';
  static const String mercadopagoWebhooks = 'webhooks';
  /// Cartão membro — docs em `cartoes` ou `config/carteira` (legado).
  static const String cartoes = 'cartoes';
  static const String certificados = 'certificados_emitidos';
  static const String certificadosHistorico = 'certificados_historico';
  static const String certificadosProtocolIndex = 'certificados_protocol_index';
  static const String pedidosOracao = 'pedidosOracao';
  /// Transferências — coleção real `cartas_historico`.
  static const String transferencias = 'cartas_historico';
  /// Modelos/favoritos de cartas — `cartas_modelos`.
  static const String cartasModelos = 'cartas_modelos';
  /// Agenda de compromissos dos fornecedores/prestadores.
  static const String fornecedorCompromissos = 'fornecedor_compromissos';

  /// Legado — leitura só até migração CF concluir.
  static const String legacyEventosNoticias = 'noticias';
  /// Legado/en-US — alguns tenants antigos armazenaram eventos em `events`.
  static const String legacyEventosEn = 'events';

  static const String dashboardCache = '_dashboard_cache';
  static const String config = 'config';

  static String churchRoot(String churchId) => '$rootCollection/${churchId.trim()}';

  static String subcollection(String churchId, String sub) =>
      '${churchRoot(churchId)}/${sub.trim()}';

  /// Storage canônico: `igrejas/{churchId}/membros|eventos|avisos|…`
  static const storageFolders = <String>[
    'membros',
    'eventos',
    'avisos',
    'patrimonio',
    'certificados',
    'cartoes',
    'chat',
  ];

  static String storageRoot(String churchId) => 'igrejas/${churchId.trim()}';

  static String storageFolder(String churchId, String folder) =>
      '${storageRoot(churchId)}/${folder.trim()}';

  static const allSubcollections = <String>[
    membros,
    departamentos,
    cargos,
    eventos,
    avisos,
    chats,
    patrimonio,
    patrimonioInventarioHistorico,
    financeiro,
    financeLogs,
    financeMpNotifications,
    fornecedores,
    escalas,
    escalaTemplates,
    agenda,
    lideres,
    administrativo,
    doacoes,
    mercadopago,
    cartoes,
    certificados,
    certificadosHistorico,
    certificadosProtocolIndex,
    pedidosOracao,
    transferencias,
    cartasModelos,
    fornecedorCompromissos,
  ];
}
