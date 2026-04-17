Pasta ANDROID — credenciais Google / Firebase (Gestão YAHWEH)
============================================================

1) google-services.json
   - Para a APP Android (Flutter): copiar para flutter_app\android\app\google-services.json
   - Ou executar na raiz do repo: .\scripts\sync_android_google_services.ps1
   - Pode ser versionado no Git (contém API key limitada ao pacote; muitos projetos commitam).
   - Depois de adicionar SHA-1/SHA-256 no Firebase Console, volte a descarregar o ficheiro
     (Configurações do projeto → a sua app Android) e sincronize de novo.

2) client_secret_....json (OAuth)
   - Para servidores, scripts Node, Cloud Functions que precisem de fluxo OAuth com segredo.
   - NÃO colocar dentro do APK/AAB nem em pastas públicas do site.
   - Está no .gitignore desta pasta.

3) *-firebase-adminsdk-*.json (conta de serviço)
   - Acesso ADMIN ao Firebase (Firestore, Auth, etc.) — como root.
   - Só em ambiente seguro: PC do gestor, CI privado, ou variável GOOGLE_APPLICATION_CREDENTIALS.
   - NUNCA na app móvel, NUNCA em repositório público.
   - Está no .gitignore desta pasta.

Firebase Console (projeto gestaoyahweh-21e23):
https://console.firebase.google.com/project/gestaoyahweh-21e23/settings/general
