# Análise mobile — Painel Master e Painel Igreja (Android / iPhone)

## Objetivo
Garantir que o sistema esteja configurado para acesso em celulares Android e iPhone (todas as versões), com SafeArea, padding responsivo, área de toque mínima e AppBar condicional.

---

## 1. Regras aplicadas no projeto

- **SafeArea**: Todas as telas do painel (master e igreja) usam `SafeArea` no `body` para respeitar notch, status bar e home indicator.
- **Padding responsivo**: Uso de `ThemeCleanPremium.pagePadding(context)` — em celular (< 600px) usa `spaceSm` horizontal e `spaceMd` vertical.
- **AppBar em mobile**: Quando a tela está embutida no shell (painel), em mobile a AppBar é escondida (`isMobile ? null : AppBar(...)`). Quando a tela é aberta sozinha (ex.: após Navigator.push), a AppBar é exibida; em telas com `Navigator.canPop(context)` mantém botão Voltar.
- **Área de toque mínima**: Botões e `IconButton` com **mínimo 48px** (`ThemeCleanPremium.minTouchTarget`) em mobile para acessibilidade (Android e iOS).
- **Breakpoints**: `breakpointMobile = 600`, `breakpointTablet = 900`, `breakpointDesktop = 1200`. `isMobile` = largura < 900; `isNarrow` = largura < 600.

---

## 2. Painel Master (Admin)

| Item | Status |
|------|--------|
| Scaffold com AppBar em mobile (isNarrow) | ✅ AppBar com menu e sair, IconButtons 48px |
| Drawer em mobile | ✅ drawer e drawerEdgeDragWidth quando isNarrow |
| SafeArea no body | ✅ SafeArea(top: !isNarrow, bottom: false) no conteúdo |
| Conteúdo das páginas (Dashboard, Usuários, Gestores, etc.) | ✅ Cada página usa SafeArea + pagePadding onde necessário |
| ListTile no drawer | ✅ minVerticalPadding 16 em mobile para toque confortável |
| Footer (VersionFooter) | ✅ Fora da SafeArea inferior para não duplicar padding |

---

## 3. Painel Igreja

| Item | Status |
|------|--------|
| Shell (IgrejaCleanShell) | ✅ SafeArea no body e no header; drawer em mobile |
| Header com menu/voltar | ✅ IconButton 48px no header mobile |
| Conteúdo (padding horizontal em phone) | ✅ Uso de pagePadding(context) para left/right em _isPhone (antes 0) |
| Drawer (menu lateral) | ✅ SafeArea no drawer; ListTile com minVerticalPadding 16 em phone |
| Páginas embutidas (Dashboard, Membros, Eventos, etc.) | ✅ SafeArea + pagePadding; AppBar condicional (isMobile ? null : AppBar) |
| Botões / IconButtons nas páginas | ✅ minTouchTarget aplicado em eventos, mural, patrimônio, departamentos, visitantes, etc. |

---

## 4. Páginas verificadas (Painel Igreja)

- **IgrejaDashboardModerno**: SafeArea, pagePadding ✅  
- **IgrejaCadastroPage**: SafeArea, pagePadding, appBar condicional ✅  
- **MembersPage**: SafeArea, pagePadding, showAppBar, RefreshIndicator ✅  
- **DepartmentsPage**: SafeArea, pagePadding, appBar condicional, IconButtons minTouchTarget ✅  
- **VisitorsPage**: SafeArea, pagePadding, showAppBar, minTouchTarget ✅  
- **CargosPage**: SafeArea, pagePadding, appBar condicional, barra mobile ✅  
- **MuralPage**: SafeArea, pagePadding, IconButton voltar com minTouchTarget ✅  
- **EventsManagerPage**: SafeArea, pagePadding, showAppBar, TabBar em mobile, minTouchTarget ✅  
- **PrayerRequestsPage**: SafeArea, pagePadding ✅  
- **CalendarPage**: SafeArea, pagePadding, showAppBar, leading IconButton minTouchTarget ✅  
- **MySchedulesPage**: SafeArea, pagePadding, appBar condicional, minTouchTarget ✅  
- **SchedulesPage**: SafeArea, pagePadding ✅  
- **CertificadosPage**: SafeArea, minTouchTarget ✅  
- **FinancePage**: SafeArea, showAppBar, minTouchTarget ✅  
- **PatrimonioPage**: SafeArea, pagePadding, appBar condicional, minTouchTarget ✅  
- **RelatoriosPage**: SafeArea, pagePadding, appBar condicional ✅  
- **ConfiguracoesPage**: SafeArea, pagePadding, appBar condicional ✅  
- **SistemaInformacoesPage**: SafeArea, pagePadding, appBar condicional ✅  

---

## 5. Páginas verificadas (Painel Master)

- **AdminDashboardPage**: pagePadding, Skeleton no loading ✅  
- **AdminUsuariosPage**: SafeArea, pagePadding, appBar isMobile ? null ✅  
- **AdminGestoresPage**: SafeArea, pagePadding, isMobile, minTouchTarget ✅  
- **AdminRecebimentosPage**: SafeArea, pagePadding, isMobile, minTouchTarget ✅  
- **AdminPlanosCobrancaPage**: SafeArea, pagePadding, appBar isMobile ? null ✅  
- **AdminMultiAdminPage**: SafeArea, pagePadding, minTouchTarget ✅  
- **AdminSugestoesPage**: SafeArea, pagePadding ✅  
- **AdminAvisoGlobalPage**: SafeArea, pagePadding, isMobile, minTouchTarget ✅  
- **AdminCustomizacaoPage**: SafeArea, pagePadding, minTouchTarget ✅  
- **AdminAuditoriaPage**: SafeArea, pagePadding, minTouchTarget ✅  
- **AdminForcarAtualizacaoPage**: SafeArea, pagePadding ✅  

---

## 6. Tema e comportamento global

- **MaterialTapTargetSize.padded**: Definido no `themeData` para aumentar área de toque dos botões Material.
- **Scaffold.resizeToAvoidBottomInset**: Padrão `true` — o conteúdo sobe quando o teclado abre (evita overflow em formulários).
- **Firestore persistence**: Habilitada para todas as plataformas (leitura offline).

---

## 7. Ajustes realizados nesta análise

1. **Painel Igreja – Shell**: Padding horizontal do conteúdo em phone passou de `0` para `ThemeCleanPremium.pagePadding(context).left/right`, evitando conteúdo colado nas bordas.
2. **MuralPage**: IconButton do leading (Voltar) passou a usar `minimumSize: Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)`.
3. **Painel Master – Drawer**: ListTile do drawer passou a usar `minVerticalPadding: isNarrow ? 16 : 14` para garantir altura de toque adequada em celular.

---

## 8. Recomendações para novas telas

Ao criar novas telas no painel master ou igreja:

1. Envolver o `body` do `Scaffold` em `SafeArea`.
2. Usar `ThemeCleanPremium.pagePadding(context)` no padding do conteúdo principal.
3. Em mobile, esconder AppBar quando a tela estiver dentro do shell: `appBar: ThemeCleanPremium.isMobile(context) ? null : AppBar(...)` (ou `showAppBar = !isMobile || Navigator.canPop(context)` e então `appBar: showAppBar ? AppBar(...) : null`).
4. Em todos os `IconButton` e botões de ação, usar `style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget))` (ou equivalente para outros botões).
5. Em listas longas, preferir `ListView.builder` e, quando fizer sentido, `RefreshIndicator` com `onRefresh`.

Com isso, o sistema fica configurado para acesso em celular Android e iPhone em todas as versões consideradas.
