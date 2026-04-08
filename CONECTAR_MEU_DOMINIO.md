# Conectar seu domínio ao sistema (Igrejas + Frotas)

O sistema já está no ar em:
- **https://gestaoyahweh-21e23.web.app** (Igrejas, Frotas e Painel ADM)

Para usar no **seu domínio** (ex.: `gestaoyahweh.com.br` ou `www.gestaoyahweh.com.br`):

## 1. Abrir o Firebase Console

1. Acesse: **https://console.firebase.google.com/project/gestaoyahweh-21e23/hosting**
2. Na seção **Hosting**, clique em **Adicionar outro domínio** (ou "Add custom domain").

## 2. Informar o domínio

1. Digite o domínio que você quer usar (ex.: `gestaoyahweh.com.br` ou `www.gestaoyahweh.com.br`).
2. Clique em **Continuar**.

## 3. Configurar DNS

O Firebase vai mostrar **registros DNS** para você criar no painel do seu provedor de domínio (Registro.br, GoDaddy, Cloudflare, etc.):

- **Tipo A**: dois endereços IP (ex.: `151.101.1.195` e `151.101.65.195`).
- Ou **CNAME** (se usar subdomínio como `www`): um host como `gestaoyahweh-21e23.web.app`.

Crie exatamente os registros que o Firebase indicar e salve.

## 4. Aguardar e concluir

1. A propagação do DNS pode levar de alguns minutos a 48 horas.
2. No Firebase, clique em **Verificar** quando estiver pronto.
3. Depois da verificação, o Firebase ativa o certificado SSL (HTTPS) no seu domínio.

Pronto: o mesmo sistema (igrejas e frotas) passará a responder no seu domínio com HTTPS.

---

**Resumo:** O app já está publicado. Para “subir no seu domínio”, basta adicionar o domínio no Hosting do Firebase e configurar o DNS conforme as instruções do console.
