# Estrutura de rotas — Gestão YAHWEH

## Resumo

- **Página divulgação (principal)** → acesso ao **Painel Master** e às **igrejas** (busca por CPF/e-mail). Login da igreja é **separado**.
- **Frota** → **separada**: página divulgação frotas + tela de login frota própria.
- **Painel Master** → controla **tudo**: licenças, Mercado Pago, igrejas, frotas, etc.

---

## Rotas

| URL | Conteúdo |
|-----|----------|
| **/** | Página de **divulgação** (planos, busca igreja por CPF/e-mail, links: Login, Cadastro, Ver planos, **Painel Master**) |
| **/login** | **Login da igreja** (após login → redireciona para /painel) |
| **/planos** | Página de planos (Landing) |
| **/admin** | **Painel Master** (licenças, Mercado Pago, usuários, cobrança, etc.) — acesso restrito |
| **/painel** | Painel da **igreja** (Menu Igreja: membros, departamentos, eventos, etc.) — após login igreja |
| **/cadastro** | Cadastro de usuário |
| **/igreja_&lt;slug&gt;** | Página **pública da igreja** (ex.: após buscar por CPF na divulgação) |
| **/frota** ou **/frota_total** | **Divulgação Frotas** (apresentação do sistema de frota) + **Login Frota** (próprio, separado da igreja) |
| **/frota_relatorios**, **/frota_dashboard** | Áreas internas da frota (com guarda de acesso) |

---

## Fluxos

1. **Igreja**  
   Divulgação (/) → Login (/login) → Painel Igreja (/painel).  
   Ou: Divulgação → busca por CPF → página pública da igreja (/igreja_xxx) → Acessar Sistema (login).

2. **Frota**  
   Divulgação Frotas (/frota) → Login Frota (na própria página) → uso do sistema de frota.

3. **Administração**  
   Divulgação (/) → Painel Master (/admin) → controle de licenças, Mercado Pago, planos, bloqueios, etc.

---

## Painel Master (/admin)

- Controla **licenças** (igrejas e frotas).
- **Mercado Pago** (credenciais, webhook, cobranças, modo Produção/Teste).
- Usuários, níveis de acesso, planos e cobrança, alertas, auditoria, etc.
