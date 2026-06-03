# Padronização Multiplataforma — Gestão YAHWEH

**Escopo técnico fechado.** Toda correção ou funcionalidade só é **concluída** após validação em **Android, iOS e Web**.

## Regra absoluta

| Proibido | Obrigatório |
|----------|-------------|
| Funcionar só Android | Mesma experiência nos 3 |
| Funcionar só iPhone | Mesma experiência nos 3 |
| Funcionar só Web | Mesma experiência nos 3 |

**Se falhar numa plataforma → RELEASE BLOQUEADA.**

## Módulos — mesma experiência

| Módulo | Android | iOS | Web |
|--------|---------|-----|-----|
| Login | ✔ | ✔ | ✔ |
| Chat | ✔ | ✔ | ✔ |
| Avisos | ✔ | ✔ | ✔ |
| Eventos | ✔ | ✔ | ✔ |
| Membros | ✔ | ✔ | ✔ |
| Patrimônio | ✔ | ✔ | ✔ |
| Financeiro | ✔ | ✔ | ✔ |
| Uploads | ✔ | ✔ | ✔ |
| Sincronização | ✔ | ✔ | ✔ |
| Retornar onde parou | ✔ | ✔ | ✔ |

### Offline

| Plataforma | Comportamento |
|------------|---------------|
| **Android / iOS** | Offline First obrigatório (Hive + SyncEngine) |
| **Web** | Cache local + recuperação automática quando possível |

Mesma **lógica** de sync; diferença apenas na persistência nativa vs web.

## Regras de desenvolvimento

### NÃO usar para regras de negócio

```dart
// PROIBIDO — lógica de produto diferente por plataforma
if (Platform.isAndroid) { ... }
if (Platform.isIOS) { ... }
if (kIsWeb) { ... }
```

### PODE isolar apenas

- Câmera
- Notificações (FCM / web push)
- Biometria (`local_auth`)
- Compartilhamento
- Ficheiros / picker nativo

Encapsular em helpers existentes (`BiometricService`, upload pipeline, etc.) — **nunca** duplicar fluxo Firestore/publicação por plataforma.

## Checklist antes de cada release

1. Executar **Modo QA** (28 testes) em **Android**
2. Repetir em **iPhone**
3. Repetir em **Web** (https://gestaoyahweh-21e23.web.app — Ctrl+F5)
4. Preencher matriz em `docs/FASE_FINAL_QA.md`
5. Gate: `.\scripts\verify_production_checklist.ps1`

Código de referência: `lib/core/qa/multiplatform_qa_matrix.dart`

## Escopo fechado (visão geral)

| Área | Itens |
|------|-------|
| **Base** | Firebase, Firestore, Storage corrigidos |
| **Experiência** | Login permanente, biometria, retorno última tela, offline, sync auto |
| **Módulos** | Membros, eventos, avisos, chat, patrimônio, financeiro, cartões, cartas, agenda, relatórios |
| **Performance** | Dashboard rápido, Master rápido, upload rápido, cache, paginação |
| **Produção** | Backup, monitoramento, Crashlytics, Analytics, health check, auditoria |
| **Plataformas** | Android · iOS · Web alinhados |

Próximo passo: **CORRIGIR → TESTAR** nas três plataformas — sem novos requisitos arquiteturais.
