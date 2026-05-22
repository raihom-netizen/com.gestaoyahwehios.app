# TestFlight — «Binário inválido» (build 1601+)

## Causa corrigida no repositório

O `Info.plist` declarava `UIBackgroundModes` → `remote-notification`, mas o `Runner.entitlements` **não** inclui `aps-environment` (push desactivado para o perfil Codemagic assinar).

A Apple processa o IPA e marca **Binário inválido** quando o modo de fundo pede push sem o entitlement correspondente.

Também foram removidos `http` e `https` de `LSApplicationQueriesSchemes` (regra **ITMS-90048**).

## O que fazer agora

1. **Commit + push** destas alterações.
2. **Codemagic** → novo build iOS com build number **1603** (ou superior ao último no ASC).
3. Aguardar processamento no TestFlight — deve aparecer **Aprovado** (como a 1600).

## Ver o e-mail da Apple (opcional)

App Store Connect → utilizador → e-mail com código **ITMS-…** (confirma o motivo exacto).

## Push iOS (futuro)

Para voltar a notificações push:

1. Ativar Push no App ID + regenerar perfil App Store.
2. Adicionar em `Runner.entitlements`:
   ```xml
   <key>aps-environment</key>
   <string>production</string>
   ```
3. Voltar a incluir `remote-notification` em `UIBackgroundModes` no `Info.plist`.

## CI

O passo `Validar IPA (evitar Binário inválido no TestFlight)` corre `scripts/codemagic_ios_validate_ipa_before_upload.sh` antes do upload.
