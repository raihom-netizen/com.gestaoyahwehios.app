# Painel Admin — Controle Total (Gestão YAHWEH + Gestão Frotas)

O painel admin (`/admin`) centraliza o controle de **Gestão YAHWEH** (igrejas) e **Gestão Frotas** em um único lugar, no estilo **Controle Total**, com isolamento claro entre os dois módulos.

## Estrutura do menu (3 blocos isolados)

1. **IGREJAS** — Gestão YAHWEH  
   - Painel Igrejas, Lista Igrejas, Planos & Cobranças, Usuários, Mercado Pago, Recebimentos Licenças, **Ativar mais gestores**.  
   - Pagamentos/ativações (estilo Controle Total): **PIX**, **Cartão em 6x**, planos **mensais e anuais**; licenças atualizadas via webhook Mercado Pago.  
   - Dados: Firestore `igrejas`, `subscriptions`, `users` (por igreja), etc.

2. **FROTAS** — Gestão Frotas  
   - Dashboard Frotas, Frota Total / Abastecimentos, Relatórios Frotas.  
   - Dados: Firestore **frota** (via `firestore_frota`): `frota_abastecimentos`, `frota_manutencao`, `frota_veiculos`, etc.

3. **SISTEMA**  
   - Dashboard Geral, Alertas, Auditoria, Customização, Suporte, Multi-Admin, Editar Preços, Níveis de Acesso, Sugestões, **Acessos ao domínio** (gráficos de acessos), Voltar ao Início.

## Isolamento

- **Igrejas:** coleções em `igrejas/{id}`, `igrejas`, `subscriptions`, `users`. Uma igreja não acessa dados de outra; o admin vê todas.
- **Frotas:** uso do serviço `firestore_frota` (Firestore de frotas). Sem cruzamento com dados de igrejas (membros, planos, etc.).
- **Acesso:** apenas usuários com claim **ADMIN** (ou equivalente) acessam o painel; o restante é bloqueado.

## Rotas diretas (opcional)

- `/frota` ou `/frota_total` — Frota Total (também acessível pelo menu admin).  
- `/frota_dashboard` — Dashboard Frotas.  
- `/frota_relatorios` — Relatórios Frotas.  
- `/admin` — Painel admin completo (Igrejas + Frotas + Sistema).
