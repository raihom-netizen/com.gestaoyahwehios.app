# Controle de versão automático — Gestão YAHWEH

## Tudo automatizado (sem preocupação manual)

- **Subir versão:** execute um único comando. Ele atualiza **tudo** sozinho.
- **Usuário do app/web:** recebe aviso de nova versão e, na web, pode atualizar com um clique (ou recarga automática quando houver nova versão).

---

## Política atual (jun/2026)

| Campo | Valor fixo | Como subir |
|-------|------------|------------|
| **Marketing** (nome visível) | `11.2.305` | Só com pedido explícito (`-NewMarketing`) |
| **Build** (`+N` / versionCode) | incrementa a cada release | `.\scripts\bump_build.ps1` |

Produção Play (referência): **11.2.305 (1852)**. Próximo build no repo: **1853+**.

## Como subir o build (padrão)

### Windows (PowerShell)
```powershell
.\scripts\bump_build.ps1
```
Incrementa só o `+N` (ex.: `11.2.305+1853` → `11.2.305+1854`).

### Subir mais de um build de uma vez
```powershell
.\scripts\bump_build.ps1 -Increment 3
```

### Alias (mesma política)
```powershell
.\scripts\bump_version.ps1
```

### Mudar marketing (exceção — só se pedido)
```powershell
.\scripts\bump_version.ps1 -NewMarketing "11.2.306"
```

### O que o script altera sozinho

1. **`flutter_app/lib/app_version.dart`** — `appVersion` e `appVersionLabel`
2. **`flutter_app/pubspec.yaml`** — `version: X.Y.Z+BuildNumber`
3. **`flutter_app/web/version.json`** — usado na web para detectar nova versão e recarregar

Depois é só fazer **build** e **deploy** (ex.: `flutter build web` e publicar). Nada manual nos arquivos de versão.

---

## Onde a versão aparece (automático, não precisa mudar)

- **main.dart** — canto da tela
- **VersionFooter** — rodapé (site, app, web, ADM, frotas, igrejas)
- **UpdateChecker** — envolve o app; consulta Firestore (`config/appVersion`) e exibe “Atualização disponível” se houver versão mínima maior
- **Web** — `version.json` + checagem no `index.html` a cada 60s + `checkAndReloadIfNewVersion()` no início: usuário vê “Nova versão disponível” ou a página recarrega sozinha quando você faz deploy

---

## Firestore (opcional): forçar atualização para todos

No documento **`config/appVersion`** você pode definir:

- **minVersion** — ex.: `"9.0.2"` — quem estiver abaixo vê o aviso
- **forceUpdate** — `true` = obriga atualizar (diálogo não fecha)
- **message** — texto do aviso
- **storeUrlAndroid** / **storeUrlIos** — links das lojas
- **webRefresh** — `true` = na web, botão “Atualizar” recarrega a página

Assim o usuário não precisa se preocupar: o próprio app avisa e orienta a atualizar.

---

## Resumo

| O que você quer              | O que fazer                                  |
|-----------------------------|----------------------------------------------|
| Subir versão (tudo em um)   | Rodar `.\scripts\bump_version.ps1`           |
| Build e deploy              | `flutter build web` (e publicar); version.json já vai no build |
| Usuário ver nova versão     | Automático (UpdateChecker + version.json + index.html) |

Versão única no sistema: **app**, **web**, **painel admin**, **frotas**, **igrejas** — tudo sai de `app_version.dart` e do script.
