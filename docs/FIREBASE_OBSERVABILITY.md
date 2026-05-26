# Firebase Observability — Gestão YAHWEH

**Importante:** Crashlytics, Analytics e Performance Monitoring **não aceleram** o app. Servem para **detectar** travamentos, telas lentas, uploads falhados e consultas pesadas — para corrigir a causa real no código.

## Serviços (Flutter)

| Serviço | Ficheiro | Uso |
|---------|----------|-----|
| `AnalyticsService` | `lib/services/analytics_service.dart` | `logScreen`, `logUpload`, `logMessage` |
| `PerformanceService` | `lib/services/performance_service.dart` | `track('nome', () async { ... })` |
| `CrashlyticsService` | `lib/services/crashlytics_service.dart` | `record(e, st, reason: '...')` |
| Atalho telas | `lib/core/yahweh_module_analytics.dart` | `logYahwehModuleScreen('chat')` no `initState` |

Inicialização: `YahwehObservability.ensureInitialized()` em `main.dart` (após `Firebase.initializeApp`).

## Telas com `logScreen` (painel)

- `dashboard`, `chat`, `chat_thread`, `avisos`, `eventos`, `membros`, `financeiro`, `escalas`

## Uploads (Performance + Analytics)

Centralizado em `MediaUploadService.uploadBytesWithRetry`:

- `upload_image`, `upload_image_chat`, `upload_image_aviso`, `upload_image_evento`, `upload_video`

## Publicação (Crashlytics)

- `mural_fast_publish_service.dart` — falhas de upload em background
- Editores aviso/evento — `catch` com `CrashlyticsService.record`

## Consultas

- Eventos: trace `load_events` no bootstrap do módulo

## Console Firebase

Ativar no projeto `gestaoyahweh-21e23`:

1. **Crashlytics** — crashes Android/iOS  
2. **Analytics** — eventos e ecrãs  
3. **Performance** — traces (após build nativo com plugin)

## Build nativo

Após adicionar `firebase_performance`, pode ser necessário:

```powershell
cd flutter_app
flutter pub get
# Se iOS falhar em pods: cd ios && pod install
```

Não executar `flutterfire configure` com overwrite de `firebase_options.dart` sem revisão.
