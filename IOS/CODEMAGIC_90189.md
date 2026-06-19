# Codemagic — erro 90189 (Redundant Binary Upload)

## O que significa

A Apple já recebeu um build com o mesmo **CFBundleVersion** para a versão de marketing (ex. `11.2.305` + build `1781859109`).

**Não é bug do app Flutter** — é o **mesmo ficheiro .ipa** a ser enviado duas vezes.

## O que NÃO fazer

- **Retry** apenas no passo **Publishing** na Codemagic — o IPA é o mesmo; o erro **90189** repete-se.
- Não fazer upload manual do mesmo `.ipa` duas vezes no Transporter.

## O que fazer

1. **Commit + push** destas alterações (floor + scripts anti-90189).
2. Codemagic → **Start new build** (workflow completo) → **iOS Build - Gestao YAHWEH (TestFlight)**.
3. No log, confirme o passo **Versão iOS**:
   - `CFBundleVersion` deve ser **> 1781859109** (ex. `1781859160` ou superior).
4. Confirme os passos **Validar IPA** e **Gate final anti-90189** antes de Publishing.
5. Após **Publishing** com sucesso, confirme `flutter_app/ios/asc_build_number_floor.txt` no artefacto ou commit com o número enviado.

## Configuração Codemagic

Use **Configuration file from repository** → `codemagic.yaml` na **raiz** do repo (monorepo `flutter_app/`).

Se a app apontar só para `flutter_app/codemagic.yaml`, esse ficheiro também inclui validação + gate anti-90189.

## Ficheiros do pipeline

| Ficheiro | Função |
|----------|--------|
| `codemagic.yaml` | Workflow iOS (raiz do repo) |
| `scripts/codemagic_ios_sync_version_from_app_version_dart.sh` | Gera CFBundleVersion único (ASC + floor + BUILD_NUMBER) |
| `scripts/codemagic_ios_asc_latest_build_number.sh` | Consulta último build na ASC (3 tentativas + floor) |
| `scripts/codemagic_ios_validate_ipa_before_upload.sh` | Bloqueia upload se CFBundleVersion ≤ ASC |
| `scripts/codemagic_ios_pre_publish_90189_gate.sh` | Última barreira antes do Publishing |
| `scripts/codemagic_ios_stamp_asc_floor.sh` | Grava floor após validação (próximo build) |
| `flutter_app/ios/asc_build_number_floor.txt` | Último build conhecido: **1781859109** |

Marketing (nome visível): `lib/app_version.dart` → `11.2.305`.  
Android usa `pubspec` `+N` (ex. `+1998`). iOS na CI usa CFBundleVersion grande (ASC), não o `+N` do pubspec.
