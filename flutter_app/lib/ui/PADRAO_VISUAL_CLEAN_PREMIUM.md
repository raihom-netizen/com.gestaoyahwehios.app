# Padrão Visual Clean Premium — Gestão YAHWEH

Referência para manter consistência em todo o painel (Apple Style: limpo, espaçamento generoso, fontes elegantes).

## Cores (ThemeCleanPremium)

- **Primary:** `#1E40AF` (azul escuro)
- **Primary light:** `#3B82F6`
- **Surface:** `#F8FAFC`
- **Surface variant:** `#F0F4FF`
- **Sidebar:** `#0A3D91` (navSidebar), hover `#1565C0`, accent `#FFE082`
- **Card:** branco, bordas arredondadas (radiusMd 16)
- **Error:** `#DC2626`, **Success:** `#16A34A`

## Espaçamento

- `spaceXs`: 6, `spaceSm`: 12, `spaceMd`: 18, `spaceLg`: 24, `spaceXl`: 32
- Usar padding mínimo 18–24 em cards e listas.

## Raios

- `radiusSm`: 12, `radiusMd`: 16, `radiusLg`: 20, `radiusXl`: 24
- Cards e botões: radiusSm ou radiusMd.

## Tipografia

- Títulos de seção: 18px, fontWeight 800
- Subtítulos: 14px, fontWeight 600
- Corpo: 15px, onSurface / onSurfaceVariant
- Labels de input: onSurfaceVariant

## Componentes

- **AppBar:** fundo primary, título branco 18px w800
- **Cards:** elevation 0, shape RoundedRectangle(radiusMd), padding spaceLg
- **Botões:** FilledButton para ação principal; OutlinedButton secundário; TextButton para links
- **Inputs:** OutlineInputBorder(radiusSm), filled true, contentPadding generoso
- **Listas:** ListTile com shape arredondado; separadores 10px
- **Empty state:** ícone centralizado, texto explicativo, CTA quando fizer sentido

## Uso no código

- Importar `theme_clean_premium.dart`.
- Usar `ThemeCleanPremium.primary`, `radiusMd`, `spaceLg`, etc.
- Preferir `Theme.of(context).colorScheme` quando o tema já estiver aplicado pelo `MaterialApp`.
- Scaffold `backgroundColor: ThemeCleanPremium.surfaceVariant` ou `colorScheme.surface`.

## Firestore (painel igreja)

- Dados da igreja: `igrejas/{igrejaId}`.
- Subcoleções: `members`, `departamentos`, `event_templates`, `noticias`, `finance`, `patrimonio`, etc.
- Não usar a coleção `igrejas` para novos dados; usar sempre `tenants` para consistência.
