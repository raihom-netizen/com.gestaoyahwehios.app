# Camada de dados — estabilidade (Gestão YAHWEH)

Alinhado ao **Controle Total**. Não criar ChatV2 / RepositoryV2 / filas paralelas.

## 1. Firebase — uma única inicialização

| O quê | Onde |
|-------|------|
| `Firebase.initializeApp` | **Só** `lib/core/firebase/firebase_bootstrap.dart` |
| Arranque completo | `main.dart` → `FirebaseBootstrapService.initialize()` |
| Acesso app | `firebaseDefaultFirestore` / `firebaseDefaultAuth` / `firebaseStorageRef` em `lib/core/firebase_bootstrap.dart` |
| Publicar / upload | `ensureFirebaseCore()` / `runFirebaseBackgroundTask()` |

**Proibido:** `FirebaseFirestore.instance` / `FirebaseAuth.instance` em código novo — usar getters `firebaseDefault*`.

## 2. Offline First

| Componente | Ficheiro |
|------------|----------|
| Fila Hive write-ahead | `TenantOfflineWrite` + `NeverLoseDataPolicy` |
| Sync | `SyncEngine` |
| Recuperação ao abrir | `AppFinalizeBootstrap.runAutomaticRecovery()` |

Fluxo: **utilizador → local (Hive/cache) → UI → sync background → Firestore**.

## 3. OOM — imagens

| Regra | Implementação |
|-------|----------------|
| Não `readAsBytes()` de foto 4K na UI | `SafeImageBytes` (`lib/core/media/safe_image_bytes.dart`) |
| Chat foto | `ChurchChatMediaPrepare` — `compressWithFile` no disco |
| Patrimônio | `SafeImageBytes.patrimonioFromPicker` |
| Limites | 1920px, quality 85%, WebP |

## 4. Chat — fluxo WhatsApp

```
Seleciona ficheiro → comprime → Storage (putFile/putData) → URL → Firestore (só URL)
```

- Stub: `beginMediaUploadMessage` — **sem bytes** no documento
- Upload: `OptimisticChatMediaUpload` → `completeMediaUploadMessage`
- Outbox: `ChurchChatMediaOutboxService` + recuperação em `AppFinalizeBootstrap`

## 5. Login permanente

- `PersistentAuthSessionService` + `AuthGate`
- Só desloga em **Configurações → Trocar conta**
- Biometria após sessão válida (`BiometricService`)

## 6. Performance / UI

- Imagens rede: `SafeNetworkImage` / `ChurchMediaDisplay` (regra imagens-rede-firebase)
- Shell igreja: `IndexedStack` (abas visitadas mantidas)
- Paginação: `YahwehPerformanceV4.defaultPageSize` (20) nos módulos críticos
- Monitoramento: Crashlytics + `YahwehObservability` + Saúde do Sistema (health 5 min)

## 7. Multiplataforma

Testar **Android + iOS + Web** antes de cada release — `docs/PADRONIZACAO_MULTIPLATAFORMA.md`.

## Ciclo atual

**CORRIGIR → TESTAR** nas 3 plataformas. Bugs restantes = tela / regra Firestore / caminho que ainda não usa `TenantOfflineWrite` ou `ensureFirebaseCore`.
