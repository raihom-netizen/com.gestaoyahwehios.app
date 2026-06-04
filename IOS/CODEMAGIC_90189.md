# Codemagic — erro 90189 (Redundant Binary Upload)

## O que significa

A Apple já recebeu um build com o mesmo **CFBundleVersion** para a versão de marketing (ex. `11.2.295` + build `1780456532`).

## O que NÃO fazer

- **Retry** apenas no passo **Publishing** — o IPA é o mesmo; o erro repete.

## O que fazer

1. **Commit** com as alterações de pipeline (floor + scripts) no GitHub.
2. Codemagic → **Start new build** → workflow **iOS Build - Gestao YAHWEH (TestFlight)**.
3. No log, confirme o passo **Versão iOS**:
   - `CFBundleVersion` deve ser **> 1780456532** (ex. `1780456545` ou superior).
4. Após **Publishing** com sucesso, atualize no repo:

   `flutter_app/ios/asc_build_number_floor.txt` → uma linha com o número que subiu (ex. `1780456545`).

## Ficheiros do pipeline

| Ficheiro | Função |
|----------|--------|
| `codemagic.yaml` | Workflow iOS (raiz do repo) |
| `scripts/codemagic_ios_sync_version_from_app_version_dart.sh` | Gera build number único |
| `scripts/codemagic_ios_asc_latest_build_number.sh` | Consulta último build na ASC |
| `scripts/codemagic_ios_validate_ipa_before_upload.sh` | Bloqueia upload duplicado |
| `flutter_app/ios/asc_build_number_floor.txt` | Último build conhecido no repo |

Marketing (nome visível): `lib/app_version.dart` → `11.2.295`.  
Android usa `pubspec` `+N` (ex. `+1767`). iOS na CI usa o esquema ASC acima, não o `+N` do pubspec.
