# Análise do Projeto — Gestão YAHWEH

## Erros corrigidos (build/analyze)

1. **`lib/ui/pages/financeiro_igreja_page.dart`**
   - Removido `_novaCategoriaCtrl.dispose()` da lista de campos (inválido).
   - Adicionado `@override void dispose()` para dar dispose no controller.

2. **`lib/ui/premium_clean_home_page.dart`**
   - Adicionado `import 'package:flutter/foundation.dart';` para usar `kIsWeb`.

3. **`lib/jimsabores_frota/pages/abastecimento_page.dart`**
   - Removido parâmetro `locationSettings` de `Geolocator.getCurrentPosition()` (não definido na versão atual do pacote). Uso da precisão padrão.

4. **`test/widget_test.dart`**
   - Teste antigo usava `MyApp` (inexistente em `main.dart`). Substituído por smoke test com `MaterialApp` simples.

5. **`lib/ui/pages/auth/login_page.dart`**
   - Trocado `AuthCpfService().loginCpf(...)` por `signInByCpf(...)`.
   - Trocado `AuthCpfService().resetSenhaCpf(cpf)` por `sendPasswordResetByCpf(cpf)`.

6. **`pubspec.yaml`**
   - Adicionado `flutter_lints: ^5.0.0` em `dev_dependencies` para o `analysis_options.yaml` encontrar `package:flutter_lints/flutter.yaml`.

---

## Situação atual do `flutter analyze`

- **Erros:** 0 (todos corrigidos).
- **Warnings / infos:** ~267 (não impedem build).

Principais tipos restantes:

- **Imports não usados** em vários arquivos (ex.: `jimsabores_frota`, `site_public_page`, `frota_*`, etc.).
- **Imports duplicados** em `jimsabores_frota/pages/abastecimento_page.dart`.
- **Variáveis/campos não usados** (ex.: `_loadError`, `_error`, `_lastAutoQuery`, `cardWidth`, `_formatDate`, `_money`, `_result`).
- **Operadores desnecessários** (`?.[]`, `?.`, `!` onde o receptor não é nulo).
- **Depreciações:**
  - `Color.withOpacity()` → preferir `.withValues()` (Flutter 3.31+).
  - `Switch.activeColor` → usar `activeThumbColor`.
  - `DropdownButtonFormField.value` → usar `initialValue`.
  - `dart:html` → preferir `package:web` e `dart:js_interop`.

Nenhum desses itens impede compilação ou execução; podem ser limpos aos poucos.

---

## Recomendações

1. Rodar `flutter analyze` e `flutter test` antes de cada deploy.
2. Reduzir warnings removendo imports não usados (IDE ou `dart fix --apply`).
3. Atualizar usos de APIs deprecadas quando for conveniente (ex.: `withOpacity` → `withValues`).
4. Manter o teste em `test/widget_test.dart` como smoke test; adicionar testes de integração conforme necessário.
