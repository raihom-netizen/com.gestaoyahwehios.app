# Referência rápida — arquivos WISDOMAPP (performance)

Projeto origem: `C:\WISDOMAPP`

Use ao implementar padrões no Gestão YAHWEH (`docs/PADRAO_MESTRE_WISDOMAPP_YAHWEH_TOTAL.md`).

## Cache e boot

| Arquivo | Função |
|---------|--------|
| `lib/services/course_videos_cache_service.dart` | **Template principal** cache-first (prefs + Firestore + signature) |
| `lib/services/user_profile_startup_cache.dart` | Perfil instantâneo |
| `lib/services/app_session_cache.dart` | Reabertura otimista pós-login |
| `lib/services/home_start_module_cache.dart` | Módulo inicial salvo |
| `lib/main.dart` (~L262–307) | warmUp paralelo antes do runApp |

## Firestore Web (estabilidade)

| Arquivo | Função |
|---------|--------|
| `lib/utils/firestore_web_guard.dart` | `runFirestoreOpSafe`, `prepareForPublishWrite`, **sem terminate** no fluxo normal |
| `lib/services/google_calendar_sync_service.dart` | Exemplo de writes seguros |

## Upload mídia

| Arquivo | Função |
|---------|--------|
| `lib/services/course_video_image_service.dart` | Foto: resize + putData Storage |
| `lib/services/course_video_file_service.dart` | Vídeo MP4 + progresso |
| `lib/services/pending_storage_upload_service.dart` | Fila offline |
| `lib/utils/course_media_url_resolver.dart` | Paths Storage canônicos |
| `lib/utils/admin_course_firestore_bridge.dart` | CF bridge writes pesados |

## UI rápida

| Arquivo | Função |
|---------|--------|
| `lib/screens/home_shell.dart` | IndexedStack lazy, máx. 2 módulos |
| `lib/screens/cursos_videos_screen.dart` | ListenableBuilder + keepAlive + anti-flicker |
| `lib/widgets/course_video/course_photo_lightbox.dart` | Galeria ampliada in-module |

## Sites públicos

| Arquivo | Função |
|---------|--------|
| `lib/screens/landing_screen.dart` | Landing + restore silencioso |
| `lib/models/landing_public_content.dart` | Defaults + merge Firestore |
| `firestore.rules` | `landing_content` read público |

## Cloud Functions

| Arquivo | Função |
|---------|--------|
| `functions/index.js` | ctAdminUpsertCourseVideo, uploadReceipt |
| `functions/googleCalendarOAuth.js` | OAuth server-side (refresh token) |

## Deploy

| Comando | Uso |
|---------|-----|
| `.\deploy.ps1 -WebOnly` | Hosting web |
| `firebase deploy --only functions:...` | CFs específicas |

---

*Espelho para consulta offline dentro do repo YAHWEH.*
