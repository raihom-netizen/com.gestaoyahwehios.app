# Widget iOS — Gestão YAHWEH

## O que já está no código

- Extensão: `flutter_app/ios/GestaoYahwehWidget/`
- Bundle Extension: `com.gestaoyahwehios.app.GestaoYahwehWidget`
- App Group (Runner + Extension): `group.com.gestaoyahwehios.app.widget`
- Kind WidgetKit: `GestaoYahwehWidget`
- Deep link: `gestaoyahweh://module/{índice}`
- Push APNs no Runner: ver `IOS/apn/LEIA-ME-APNS.md` (Key ID `JRRNARK6KJ`)

## Perfil que você baixou

O ficheiro em `widget/` (`GestoYahwehlWidget_ios_app_store.mobileprovision`) é **App Store do app principal** (`com.gestaoyahwehios.app`).

**Não basta sozinho** para o Widget Extension. Falta:

1. **App Group** no Developer Portal  
   - Nome: `group.com.gestaoyahwehios.app.widget`  
   - Ligar no App ID do Runner **e** no App ID da Extension.

2. **App ID da Extension**  
   - `com.gestaoyahwehios.app.GestaoYahwehWidget`  
   - Capabilities: App Groups (+ o que o CodeMagic exigir).

3. **Provisioning Profile App Store da Extension**  
   - Guardar também nesta pasta `widget/`, ex.:  
     `GestaoYahwehWidget_ios_app_store.mobileprovision`

4. **Regenerar o profile do Runner** com:
   - Push Notifications  
   - Sign In with Apple  
   - App Groups  

## CodeMagic

- Continua **só iOS**.
- Assinar **dois** profiles: Runner + GestaoYahwehWidgetExtension (quando a extension estiver no IPA).
- Bundle Runner: `com.gestaoyahwehios.app`

## Android

Já está no projeto (3 tamanhos + AlarmManager 00:00/12:00 + rollover). Package: `com.gestaoyahweh.app`.
