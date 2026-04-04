Para as fotos carregarem na web (Firebase Storage), o bucket precisa ter CORS configurado.

1. Instale Google Cloud SDK (gsutil) se ainda não tiver.
2. Aplique o CORS no bucket do Firebase Storage:

   gsutil cors set storage_cors.json gs://SEU_PROJECT_ID.appspot.com

   (Substitua SEU_PROJECT_ID pelo ID do projeto Firebase, ex: gestaoyahweh-21e23)

3. Ou pelo Console Firebase: Storage > ... (menu) > Configurações do bucket (se disponível).

O arquivo storage_cors.json já permite origem "*" (qualquer domínio) para GET/HEAD,
necessário para o app web carregar imagens do Storage.
