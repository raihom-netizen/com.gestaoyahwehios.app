# Agentes Cursor — Gestão YAHWEH

Este repositório usa **regras persistentes** em `.cursor/rules/` e o manual **`prompt_mestre_cursor.md`**.

**Memória única (igual Controle Total):** `PONTO_BASE_MEMORIA_2026-08-02_11.2.305+2153.md` + regra `.cursor/rules/ponto-base-memoria-11-2-305-2153.mdc`. Não criar segunda memória; ao atualizar release, substituir este ficheiro e arquivar o anterior.

## Comportamento esperado do agente

1. Consultar primeiro o **ponto base de memória** (versão atual, painel igreja/master, regras, funções, índices, artefactos).
2. Ler e seguir **`prompt_mestre_cursor.md`** (arquitetura offline-first, Controle Total / WhatsApp, §0–22).
3. Aplicar sempre a regra **`prompt-mestre-arquitetura.mdc`** (`alwaysApply: true`).
4. Evoluir serviços existentes — **não** criar duplicatas (`regra-mestra-projeto.mdc`).
5. Responder em **português**; alterações **focadas** e mínimas.
6. **Build/deploy só com pedido explícito ao final** — não publicar nem rodar `deploy_completo.ps1` / hosting / regras por iniciativa própria (`sem-deploy-sem-pedido-explicito.mdc`, `deploy-so-ao-final.mdc`).

## Referência rápida

| Tema | Ficheiros |
|------|-----------|
| Offline-first | `offline_first_coordinator.dart`, `firestore_app_config.dart`, `optimistic_firestore_write.dart`, `tenant_offline_write.dart` |
| Auth + biometria | `auth_service.dart`, `auth_gate.dart`, `biometric_lock_page.dart` |
| Upload + fila BG | `storage_service.dart`, `background_upload_worker.dart`, `storage_upload_persistence_service.dart`, `mural_publish_outbox_service.dart` |
| Vídeo eventos | `media_video_compress_quality.dart`, `media_service.dart` (`prepareEventVideoForUpload`) |
| Dashboard stats | `church_tenant_dashboard_doc_service.dart`, `dashboard_stats_counter_service.dart` |
| Imagens UI + retry | `safe_network_image.dart`, `unavailable_media_widget.dart` |
| Chat paginação + retenção | `church_chat_service.dart` (20 msgs), `church_chat_storage_retention_service.dart` |
| Paginação listas | `yahweh_performance_v4.dart` (pageSize 20), `lazy_firestore_list_controller.dart` |
| Conflitos offline LWW | `firestore_last_write_wins.dart` |
| Partilha WhatsApp | `yahweh_share_service.dart`, `yahweh_share_button.dart` |
| Web uploads | `web_safe_media.dart`, `upload_bytes_core.dart` |
| Regras Firebase | `firestore.rules`, `storage.rules`, `FIREBASE_RULES_SECURITY.txt` |
| Deploy regras (GCP, autorizado) | `scripts/regras_gcp_automatico_forcado.ps1` |
| Deploy regras (detalhe) | `scripts/deploy_firebase_rules.ps1` |
| Deploy web | `scripts/deploy_web_hosting.ps1` |
| gcloud (auto) | `scripts/install_google_cloud_sdk.ps1` via `ensure_gestao_yahweh_toolchain_path.ps1` |
| GCP regras REST | `scripts/firebase_rules_gcp_publish.cjs` |

## Toolchain (antes de deploy)

```powershell
. .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
```

Instala **gcloud** automaticamente se faltar (winget / zip). Nao pedir instalacao manual.

## Regras Firebase (autorizado)

```powershell
.\scripts\regras_gcp_automatico_forcado.ps1
```

Publica em **firebaserules.googleapis.com** (nao no banco Firestore): preflight + `firebase_rules_gcp_publish.cjs` + `-ForcePublish`. Inclui `ensure_functions_node_for_gcp.ps1` (googleapis para IAM). Sem pedir confirmacao extra se o utilizador autorizou.

**Copiar para outros projetos:** `docs/GCP_TOOLCHAIN_COPIAR_OUTROS_PROJETOS.md` + scripts listados + `.cursor/rules/gcloud-toolchain-automatico.mdc` + `prompt_mestre_cursor.md`.

## Comando Composer (opcional)

Referencie `@prompt_mestre_cursor.md` ou peça implementação «alinhada ao manual arquitetural».

As regras `.mdc` com `alwaysApply: true` já carregam o essencial — **não é obrigatório** colar o comando mestre em cada sessão.

---

## Build iOS no GitHub Actions (02/09/2026)

Repo: `raihom-netizen/com.gestaoyahwehios.app`. O YAML e **gerado** por
`scripts/gerar_workflow_ios_do_codemagic.py` a partir do proprio `codemagic.yaml` — sao 30
passos, varios com blocos Python longos, e transcrever a mao seria pedir erro. Mexeu no
`codemagic.yaml`, rode o gerador. A assinatura ficou em API-only (a chave RSA), como nos
outros apps; o modo manual do Codemagic (P12 + `.mobileprovision` em Base64 nos secrets
`CM_CERTIFICATE` / `CM_PROVISIONING_PROFILE`) continua disponivel.

O build iOS saiu do Codemagic e roda no GitHub Actions, workflow **iOS TestFlight**
(`.github/workflows/ios_testflight.yml`). O `codemagic.yaml` continua no repo como plano B.

**Nao roda sozinho.** O gatilho e apenas `workflow_dispatch`: nenhum push inicia build.
Para rodar:

    gh workflow run ios_testflight.yml --ref <branch>

ou GitHub > Actions > iOS TestFlight > Run workflow. Motivo: runner macOS conta **10x**
na cota de minutos (um build de 50 min custa ~500), entao build iOS so acontece quando
alguem pede — normalmente no fim do deploy completo.

**Xcode 26 e obrigatorio.** Desde 2026 a Apple recusa upload de app compilado com SDK
menor que o do iOS 26: `Validation failed (409) SDK version issue`. O runner `macos-15`
usa Xcode 16.4 — por isso o job roda em `macos-26`. Pegadinha: essa imagem traz varios
Xcode 26.x e **nem todos tem a plataforma iOS instalada**; escolher pelo numero maior cai
num que nao tem e o build morre em `iOS 26.0 is not installed`. O passo "Selecionar Xcode
26+ com SDK iOS instalado" ordena por versao completa e so aceita um cujo
`xcrun --sdk iphoneos --show-sdk-version` responda 26+.

**Como o IPA e gerado** (`scripts/gha_ios_build_ipa.sh`, igual nos quatro apps):
`flutter build ios --release --no-codesign` -> `xcodebuild archive` -> `xcodebuild
-exportArchive` com o ExportOptions escrito a partir dos perfis instalados no keychain.
Nao usa `flutter build ipa`: ele monta o proprio ExportOptions e deixa o `.ipa` em
caminhos que variam com o layout do repo.

**Como e enviado** (`scripts/gha_ios_publish_testflight.sh`): `app-store-connect publish
--testflight`, com 3 tentativas — sao ~130 MB e uma queda de rede no fim derrubava o build
inteiro. Se a Apple responder **90189** ("build number ja usado"), o script trata como
sucesso: o binario ja chegou, nao ha o que reenviar.

**Se o build deu certo mas o envio nao:** workflow **Enviar IPA ao TestFlight**
(`ios_enviar_testflight.yml`) baixa o IPA daquele run e so publica — ~5 min de runner em
vez de recompilar. Informe o numero do run (esta na URL do run em Actions).

**Secrets** (Settings > Secrets and variables > Actions), gravados por
`.\scripts\configurar_github_ios.ps1`: `APP_STORE_CONNECT_PRIVATE_KEY` (.p8),
`APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_ISSUER_ID` e
`CERTIFICATE_PRIVATE_KEY` (chave RSA). Os quatro apps (Controle Total, WISDOMAPP,
MOOVAUP, Gestao YAHWEH) estao na **mesma conta App Store Connect** (Issuer
`77a1debb-...`), entao a mesma chave `.p8` e a mesma chave RSA servem para todos — e
reusar a RSA e o que evita estourar o limite de 3 certificados Apple Distribution da
conta. Chave `.p8` e credencial: quem roda o script e o dono da conta, nunca o assistente.

**Armadilha ja paga:** condicao de passo escrita como `if: inputs.X != false` e pulada
quando o build vem de push — em push o contexto `inputs` vem vazio, e no GitHub Actions
string vazia compara igual a `false`. O run fica verde sem ter enviado nada. A forma certa
e `if: ${{ github.event_name != 'workflow_dispatch' || inputs.X }}`.
