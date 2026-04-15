# Domínio autorizado para login Google (OAuth)

Se aparecer o erro **"This domain is not authorized for OAuth operations"** ao entrar com Google:

1. Acesse o [Firebase Console](https://console.firebase.google.com) do projeto (ex.: jimprod).
2. Vá em **Authentication** > **Settings** (engrenagem) > aba **Authorized domains**.
3. Clique em **Add domain** e adicione:
   - `gestaoyahweh.com.br`
   - `gestaoyahweh-21e23.web.app` (se usar hosting do Firebase)
   - Qualquer outro domínio em que o app for acessado (ex.: localhost para testes).

Sem isso, o login com Google na web não funciona e fluxos que dependem de OAuth no domínio podem falhar.
