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

4) Chave de UPLOAD do Google Play (Assinatura de apps)
   - No Play Console: Testar e lançar → Integridade do app → Assinatura de apps →
     «Certificado da chave de upload» (não confundir com a chave de assinatura da Play).
   - Estes valores devem estar em Firebase → Configurações → a sua app Android →
     Adicionar impressão digital, senão o login Google pode falhar na versão instalada pela loja / testes internos.
   - Depois de adicionar SHA-1 (e recomendado SHA-256), descarregue de novo o google-services.json
     e execute .\scripts\sync_android_google_services.ps1
   - Referência (Gestão Yahweh — chave de upload Play), para colar no Firebase:
     MD5:    58:73:E3:A5:D9:65:2B:26:07:77:61:C5:91:FC:0F:64
     SHA-1:  96:91:41:90:E3:D0:A2:91:20:75:A2:4F:63:1F:53:30:0E:43:A6:CD
     SHA-256: 32:B1:DF:79:52:83:16:D1:C0:BE:E2:19:AC:51:9B:00:36:3A:12:0D:64:89:BA:56:32:56:12:CC:09:87:17:00

Firebase Console (projeto gestaoyahweh-21e23):
https://console.firebase.google.com/project/gestaoyahweh-21e23/settings/general
