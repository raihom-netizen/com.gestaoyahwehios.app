# Testes de Security Rules — Cloud Firestore

Valida as regras **existentes** em `../firestore.rules` (não gera regras novas).

## Pré-requisitos

- Node.js 18+
- Firebase CLI (`firebase --version`)

## Executar testes (emulador automático)

Na raiz do repositório:

```powershell
cd security_rules_test_firestore
npm install
cd ..
firebase emulators:exec --only firestore "cd security_rules_test_firestore && npm test"
```

## Executar com emulador já aberto

Terminal 1:

```powershell
firebase emulators:start --only firestore
```

Terminal 2:

```powershell
cd security_rules_test_firestore
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
npm test
```

## Deploy (após testes OK)

```powershell
.\scripts\deploy_firebase_rules.ps1 -ForcePublish
# ou
firebase deploy --only firestore:rules --project gestaoyahweh-21e23
```
