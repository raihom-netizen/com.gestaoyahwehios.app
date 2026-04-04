# Painel da Igreja — Lista geral de ferramentas

O usuário (gestor, líder ou membro) acessa o **painel da igreja** após login com CPF/e-mail da igreja. O painel completo é a **DashboardPage** (tela moderna com barra em gradiente, cards e gráficos).

---

## Tela moderna

- **Barra superior** em gradiente (azul), logo Gestão YAHWEH, nome do usuário e logout.
- **Dashboard inicial**: KPIs (membros ativos, novos membros, estatísticas por idade), gráficos (idade, evolução), **acessos rápidos** em cards.
- **Gráficos**: crescimento de membros, ofertas mensais, distribuição por idade (ex.: GraficoUltraModerno no IgrejaPainelPage; no DashboardPage, seções com gráficos e barras).

---

## Lista de ferramentas (o que o usuário pode usar)

### 1. **Membros**
- Cadastrar, editar e listar membros.
- Gerar **carteirinhas** a partir do cadastro de membros (link para Carteirinha por membro).

### 2. **Carteirinha (Carteira digital)**
- **Carteira digital** do membro com QR Code.
- **Emissão de certificado/cartão de membro**:
  - Visualização da carteirinha na tela.
  - **Impressão/PDF**: geração de PDF da carteirinha (foto, nome, CPF, nascimento, filiação, sexo, validade, QR Code).
  - Definição de **validade da carteira**: permanente ou por X anos (gestor).
- Configuração visual (título e subtítulo da igreja) em `config/memberCard` (ex.: "Carteira digital da igreja").

### 3. **Notificações**
- Avisos de escalas e comunicados do departamento.

### 4. **Minhas Escalas**
- Ver escalas do usuário por dia e horário.

### 5. **Mural**
- Avisos e eventos em formato tipo **feed (estilo Instagram)**.
- Integração com WhatsApp quando configurado.

### 6. **Eventos**
- Eventos fixos (recorrentes) e casuais.
- Gestão de datas e descrições (gestor/admin).

### 7. **Escalas**
- Gerar e gerenciar escalas: dia, semanal, mensal e anual (gestor/admin).

### 8. **Departamentos**
- Criar e editar departamentos.
- Imagens padrão (desenhos) por departamento.

### 9. **Receitas e Despesas (Financeiro)**
- Controle financeiro com **categorias e gráficos**.
- Lançamento de receitas e despesas.
- Relatórios e visão por período.

### 10. **Frota e Abastecimentos**
- Controle de veículos, abastecimentos e manutenção da igreja (gestor/admin).

### 11. **Assinatura (Plano)**
- Ver plano atual, pagamento e ativação.
- Renovação e upgrade (RenewPlanPage, Mercado Pago quando integrado).

### 12. **Usuários / Permissões**
- Gerenciar usuários e permissões da igreja (gestor/admin).
- Definir perfis (Líder, User, etc.).

### 13. **Aprovar Membros**
- Aprovar novos membros pendentes (gestor/admin).

### 14. **Relatórios**
- Relatório de membros.
- Relatório financeiro.
- Exportar dados (conforme implementação).

### 15. **Configurações**
- Ajustes gerais da igreja (conforme implementação).

### 16. **Downloads do app**
- Links para download Android, iOS e pasta de downloads (quando configurados em `config/appDownloads`).

### 17. **Busca global**
- Busca rápida (atalho Ctrl+K) no painel (IgrejaPainelPage).

### 18. **Aniversariantes**
- Lista de aniversariantes do dia (visível no dashboard do IgrejaPainelPage).

### 19. **Liderança / Líderes**
- Destaque de líderes (widget no dashboard).

### 20. **Avisos do painel**
- Avisos recentes exibidos no dashboard.

---

## Resumo por categoria

| Categoria        | Ferramentas                                                                 |
|-----------------|-----------------------------------------------------------------------------|
| **Pessoas**     | Membros, Carteirinha (carteira + emissão PDF), Departamentos, Usuários, Aprovar Membros, Aniversariantes, Liderança |
| **Comunicação** | Notificações, Mural (feed), Avisos                                         |
| **Calendário**  | Eventos, Escalas, Minhas Escalas                                           |
| **Financeiro**  | Receitas e Despesas (com gráficos), Assinatura/Plano                       |
| **Frota**       | Frota e Abastecimentos                                                     |
| **Relatórios**  | Relatório de Membros, Relatório Financeiro, Exportar Dados                 |
| **Sistema**     | Configurações, Permissões, Downloads do app, Busca global (Ctrl+K)         |

---

## Onde cada coisa está no código

- **Dashboard principal (tela moderna)**: `ui/pages/dashboard_page.dart` (acessado via AuthGate quando o usuário tem `igrejaId`).
- **Painel alternativo com menu lateral**: `ui/igreja_painel_page.dart` (rota `/painel`) — dashboard com KPIs, gráficos (GraficoUltraModerno), aniversariantes, líderes e avisos; menu lateral com Painel, Membros, Departamentos, Eventos, etc. (o conteúdo do body hoje não muda ao clicar no menu).
- **Carteirinha / Carteira / Emissão de certificado**: `ui/pages/member_card_page.dart` (MemberCardPage) — carteira digital, QR Code, PDF, validade (CARTEIRA_PERMANENTE, CARTEIRA_VALIDADE, CARTEIRA_ANOS).
- **Gráficos**: `ui/grafico_ultra_moderno.dart`; também `fl_chart` em dashboard e financeiro.

---

*Documento gerado para referência do painel da igreja (Gestão YAHWEH).*
