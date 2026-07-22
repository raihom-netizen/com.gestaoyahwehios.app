# APNs — Gestão YAHWEH (paridade Controle Total)

## Chave Apple (já criada)

| Campo | Valor |
|-------|--------|
| Nome | Gestao Yahweh APNs |
| Key ID | `JRRNARK6KJ` |
| Team ID | `82RC6YL7KL` |
| Ficheiro | `AuthKey_JRRNARK6KJ.p8` (esta pasta) |
| Serviços | APNs + Sign in with Apple |

**Não partilhar o `.p8` em repositório público.** Firebase já tem a chave carregada (dev + prod) no projeto `gestaoyahweh-21e23` para o app iOS `com.gestaoyahwehios.app`.

## O que o app faz agora (código)

- `Runner.entitlements`: `aps-environment = production`
- `Info.plist`: `UIBackgroundModes` → `remote-notification`
- `AppDelegate.swift`: `registerForRemoteNotifications` + `willPresent` (banner/list/sound) + `Messaging.apnsToken`
- `FcmService`: `setForegroundNotificationPresentationOptions` + espera `getAPNSToken()`

## CodeMagic / perfil App Store (obrigatório)

O build IPA **só passa** se o `.mobileprovision` do Runner incluir:

1. Push Notifications  
2. Sign In with Apple  
3. App Groups (`group.com.gestaoyahwehios.app.widget`) — se o widget estiver no target  

Passos:

1. developer.apple.com → Identifiers → `com.gestaoyahwehios.app` → marcar **Push Notifications** → Save  
2. Profiles → regenerar App Store → Download  
3. Codemagic secret `CM_PROVISIONING_PROFILE` = Base64 do **novo** perfil (uma linha)  
4. Start build iOS  

Sem regenerar o perfil, o Xcode/Codemagic rejeita o entitlement `aps-environment`.
