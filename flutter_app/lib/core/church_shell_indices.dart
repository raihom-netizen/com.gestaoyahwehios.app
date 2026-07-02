/// Índices do menu [IgrejaCleanShell] — alinhados a [kChurchShellNavEntries].
///
/// Configurações ficou no índice **2** (logo abaixo de Cadastro da Igreja).
abstract final class ChurchShellIndices {
  ChurchShellIndices._();

  static const int painel = 0;
  static const int cadastroIgreja = 1;
  static const int configuracoes = 2;
  static const int membros = 3;
  static const int departamentos = 4;
  static const int visitantes = 5;
  static const int cargos = 6;
  static const int muralAvisos = 7;
  static const int muralEventos = 8;
  static const int pedidosOracao = 9;
  static const int agenda = 10;
  static const int minhaEscala = 11;
  static const int escalaGeral = 12;
  static const int cartaoMembro = 13;
  static const int certificados = 14;
  static const int cartasTransferencias = 15;
  static const int relatorios = 16;
  static const int informacoes = 17;
  static const int aprovacoesRapidas = 18;
  static const int financeiro = 19;
  static const int patrimonio = 20;
  static const int fornecedores = 21;
  static const int doacao = 22;
  static const int chatIgreja = 23;
}

/// Compatibilidade com código que importava constantes soltas.
const int kChurchShellIndexPainel = ChurchShellIndices.painel;
const int kChurchShellIndexAprovacoes = ChurchShellIndices.aprovacoesRapidas;
const int kChurchShellIndexFinanceiro = ChurchShellIndices.financeiro;
const int kChurchShellIndexMembers = ChurchShellIndices.membros;
const int kChurchShellIndexMural = ChurchShellIndices.muralAvisos;
const int kChurchShellIndexEvents = ChurchShellIndices.muralEventos;
const int kChurchShellIndexAgenda = ChurchShellIndices.agenda;
const int kChurchShellIndexMySchedules = ChurchShellIndices.minhaEscala;
const int kChurchShellIndexPatrimonio = ChurchShellIndices.patrimonio;
const int kChurchShellIndexEscalaGeral = ChurchShellIndices.escalaGeral;
const int kChurchShellIndexFornecedores = ChurchShellIndices.fornecedores;
const int kChurchShellIndexChurchLetters = ChurchShellIndices.cartasTransferencias;
const int kChurchShellIndexChat = ChurchShellIndices.chatIgreja;
const int kChurchShellIndexConfiguracoes = ChurchShellIndices.configuracoes;
