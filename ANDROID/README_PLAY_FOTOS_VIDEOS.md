# Google Play — política de fotos e vídeos (Gestão YAHWEH)

## O que a Play exige

- **Não** declarar `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_EXTERNAL_STORAGE` nem acesso amplo ao armazenamento.
- Seleção de mídia: **Android Photo Picker** (via plugin `image_picker` no Flutter).
- Câmera: permissão `CAMERA` apenas para captura pontual.

## O que o projeto faz

- `flutter_app/android/app/src/main/AndroidManifest.xml` remove permissões fundidas por plugins (`tools:node="remove"`).
- Uploads (membros, eventos, chat, etc.) usam `ImagePicker` / `pickMultiImage` / `pickVideo` sem permissões de leitura em massa.

## Gerar AAB para reenvio

Na raiz do repositório (PowerShell):

```powershell
.\scripts\build_android_play_store_aab.ps1
```

Saída: `flutter_app\build\app\outputs\bundle\release\app-release.aab` (cópia em `D:\Temporarios` por defeito).

## Play Console

1. Envie o **novo** `versionCode` (build `+N` maior que 1589 rejeitado).
2. Em **Política do app → Permissões de fotos e vídeos**, declare que o app **não** usa acesso persistente — só seletor pontual.
3. Remova versões antigas com `READ_MEDIA_*` das faixas de teste/produção se ainda estiverem no envio.
