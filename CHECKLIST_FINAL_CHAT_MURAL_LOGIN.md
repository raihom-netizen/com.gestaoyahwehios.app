# Checklist final — Chat Igreja, Avisos, Eventos e Login

**Versão de referência:** `11.2.295` + build em `flutter_app/web/version.json`  
**Objetivo:** sem erros recorrentes, publicação rápida, login estável.

---

## Antes de testar

1. Regras Firebase em produção:
   ```powershell
   .\scripts\deploy_firebase_rules.ps1
   ```
2. Web (após alterações de código):
   ```powershell
   .\scripts\deploy_web_hosting.ps1
   ```
3. No browser: **Ctrl+F5** após deploy web.
4. Gate local (opcional):
   ```powershell
   .\scripts\verify_finalize_three_pillars.ps1
   ```

---

## Pilar 1 — Estabilidade

### Login / sessão

| # | Teste | Web | Android | iOS |
|---|--------|-----|---------|-----|
| L1 | App aberto com sessão → painel em &lt; 10 s (rede normal) | ☐ | ☐ | ☐ |
| L2 | Sair → login e-mail → painel sem tela presa | ☐ | ☐ | ☐ |
| L3 | Login Google (painel igreja) | ☐ | ☐ | ☐ |
| L4 | Login Apple (iOS) | ☐ | ☐ | — |
| L5 | Voltar do background → continua no painel (sem crash) | ☐ | ☐ | ☐ |

### Firebase

| # | Teste | OK |
|---|--------|-----|
| F1 | Master → **Saúde do Sistema** → Firebase tudo verde (ou reconectar) | ☐ |
| F2 | Publicar com rede cortada → mensagem clara (não «serviços não iniciaram») | ☐ |

---

## Pilar 2 — Velocidade (avisos + eventos)

| # | Teste | Web | Android | iOS |
|---|--------|-----|---------|-----|
| A1 | Novo aviso com 3 fotos → mural com imagens (não só texto) | ☐ | ☐ | ☐ |
| A2 | Novo evento com 1 foto → capa visível no feed | ☐ | ☐ | ☐ |
| A3 | Editar aviso (sem fotos novas) → guarda rápido | ☐ | ☐ | ☐ |
| A4 | Falha de rede no envio → **Saúde do Sistema → Uploads** ou reenvio | ☐ | ☐ | ☐ |
| A5 | Nenhum post público eterno em `uploading` após 5 min | ☐ | ☐ | ☐ |

**Regra de código:** publicação com fotos novas usa `FeedMediaPublishStrict` / `FeedMediaPublishService.publish` — Storage **antes** de `published`.

---

## Pilar 3 — Chat Igreja

| # | Teste | Web | Android | iOS |
|---|--------|-----|---------|-----|
| C1 | Texto instantâneo na bolha | ☐ | ☐ | ☐ |
| C2 | Foto → progresso → enviada | ☐ | ☐ | ☐ |
| C3 | Áudio (waveform Android / barra web) | ☐ | ☐ | ☐ |
| C4 | Modo avião → faixa «Reenviar» no hub/thread | ☐ | ☐ | ☐ |
| C5 | Conversa permanece na lista após nova mensagem | ☐ | ☐ | ☐ |
| C6 | Favoritar mensagem + lista no menu ⋮ | ☐ | ☐ | ☐ |

---

## Deploy de entrega

| Passo | Comando |
|--------|---------|
| Regras | `.\scripts\deploy_firebase_rules.ps1` |
| Web | `.\scripts\deploy_web_hosting.ps1` |
| Completo (autorizado) | `.\scripts\deploy_completo.ps1` |

**URL web:** https://gestaoyahweh-21e23.web.app

---

## Critério de «pronto»

- Todos os itens **críticos** (L1, L2, A1, A2, C1, C2, F1) marcados nas plataformas que a igreja usa.
- `dart analyze` sem `error` nos ficheiros alterados.
- Regras Firestore/Storage publicadas no projeto `gestaoyahweh-21e23`.

---

## Não fazer nesta fase (evita regressão)

- Refactor total da UI do chat (`church_chat_thread_page.dart`).
- Migrar objetos Storage antigos `igrejas/…` → `tenants/…` em massa.
- Novos posts no mural com `publishState: uploading` **antes** do upload (só reenvio/outbox legado).
