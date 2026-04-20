# Replicacao no projeto correto (Gestao Yahweh)

Data: 2026-04-20
Objetivo: aplicar no projeto `gestao_yahweh_premium_final` todas as melhorias solicitadas hoje.

## 1) Agenda
- Criar opcao de limpar calendario por:
  - mes
  - periodo
  - dia (ao clicar no dia)
- Simplificar filtros da Agenda:
  - remover filtros como "cultos" e similares
  - manter somente "origem"
  - manter abas: "Mes", "Semana" e "Agenda"

## 2) Modo Fornecedor (mobile)
- Corrigir travamento/dificuldade de rolagem para baixo no celular.
- Garantir scroll fluido, inclusive com teclado aberto.

## 3) Modulo Doacao / Historico
- Garantir que historico respeite a escolha real da doacao:
  - "Dizimo"
  - "Oferta Missionaria"
- Nao salvar/exibir como item generico unico.
- Obedecer modulo de doacao e site publico na classificacao.
- Incluir filtro rapido de conferencia mensal no Financeiro:
  - Todas
  - Dizimo
  - Oferta Missionaria

## 4) Assinaturas de documentos (padrao visual)
- Padronizar assinatura com destaque:
  - caixa cinza claro
  - texto em negrito
- Aplicar em:
  - carteira de membro
  - certificados
  - cartas de transferencia/mudanca/agradecimentos
  - relatorios financeiros
  - inventarios
  - patrimonio
- Permitir configuracao de quem assina.
- Regra da carteira de membro:
  - apenas 1 assinatura escolhida pelo gestor (Pastor, Gestor ou Secretario).
- Regra das Escalas:
  - assinaturas de Lideres de Departamento ou Pastor/Gestor.

## 5) Menus e icones (padrao premium)
- Modernizar icones do menu do usuario e painel master (coloridos e modernos).
- Alinhar estilo visual com atalhos de rodape.
- Corrigir tema/icone do departamento Escola Dominical.
- Garantir fallback visual para nenhum departamento ficar sem tema.

## 6) Microanimacoes premium (hover/pressed)
- Aplicar microanimacoes de escala/opacidade em elementos interativos.
- Aplicar em todo o sistema e tambem no painel master.
- Cobrir botoes principais (Novo, Exportar, Salvar).
- Cobrir botoes Salvar de sheets e formularios principais.

## 7) Modulo Membro (painel e numeros)
- Incluir contagens/cards bem definidos para:
  - Homens
  - Mulheres
  - Idosos
  - Criancas
  - Adolescentes
- Ao clicar em cada card, filtrar/exibir somente o grupo correspondente.
- Aplicar padrao visual super premium no modulo completo.

## 8) Cadastro publico de membro
- Atualizacao instantanea sem precisar sair e entrar novamente.
- Em aprovacao de cadastro:
  - enviar email automatico ao usuario
  - layout profissional, moderno, padrao super premium
  - informar liberacao de acesso ao sistema.

## 9) Diretriz de execucao
- Fazer alteracoes cirurgicas, sem regressao.
- Priorizar comportamento em tempo real (snapshot/stream) quando aplicavel.
- Validar no final com teste funcional dos fluxos acima.

