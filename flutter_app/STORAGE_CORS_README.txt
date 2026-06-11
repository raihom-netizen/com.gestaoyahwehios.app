Firebase Storage — CORS para painel Web (Gestão YAHWEH)
========================================================

Sintomas sem CORS correcto:
- Upload falha só na Web (F12: erro CORS / network)
- Imagens em branco ou downloadURL não carrega no browser
- PUT/POST bloqueado mesmo com regras Storage OK

Arquivo canónico (PUT/POST/GET + domínios produção):
  cors.json (raiz do repo)
  flutter_app/storage_cors.json (cópia alinhada)

Aplicar no bucket (requer gcloud + gsutil):
  gcloud auth login
  gcloud config set project gestaoyahweh-21e23
  .\scripts\apply_firebase_storage_cors.ps1

Ou manualmente:
  gsutil cors set cors.json gs://gestaoyahweh-21e23.firebasestorage.app
  gsutil cors get gs://gestaoyahweh-21e23.firebasestorage.app

Domínios incluídos:
- https://gestaoyahweh.com.br
- https://www.gestaoyahweh.com.br
- Firebase Hosting (*.web.app / *.firebaseapp.com)
- localhost (dev Flutter web)

Nota: CORS é configuração Google Cloud — não é corrigível só no código Flutter.
