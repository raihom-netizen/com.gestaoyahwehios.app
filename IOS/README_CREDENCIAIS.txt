Pasta IOS — credenciais Apple / App Store (Gestão YAHWEH)
=========================================================

SEGURANCA: NUNCA commite .p12, .p8 ou .mobileprovision no GitHub (repositorio publico).
  Use secrets na Codemagic: APP_STORE_CONNECT_* (API); opcional CM_CERTIFICATE + CM_PROVISIONING_PROFILE
  apenas se quiser override manual. Assinatura recomendada: identidades da equipa (ver abaixo).
  Se ja subiu estes ficheiros ao Git: apague do historico ou revogue certificado/chave na Apple.

Bundle ID da app na loja: com.gestaoyahwehios.app
App Store Connect — Apple ID do app: 6761656626
Team ID (Xcode / projeto): 82RC6YL7KL — ja definido em ios/Runner.xcodeproj (DEVELOPMENT_TEAM).

Codemagic — assinatura no CI (obrigatorio no YAML actual)
-----------------------------------------------------------
O codemagic.yaml NAO usa ios_signing por bundle na equipa (evita o erro
"No matching profiles found" quando a equipa nao tem perfil App Store registado).

No grupo appstore_credentials defina SEMPRE:
  CM_CERTIFICATE           — .p12 Apple Distribution em Base64 (uma linha)
  CM_PROVISIONING_PROFILE  — .mobileprovision App Store para com.gestaoyahwehios.app em Base64
  CM_CERTIFICATE_PASSWORD  — password do .p12 (opcional, secret)

Mais: APP_STORE_CONNECT_PRIVATE_KEY (.p8), KEY_IDENTIFIER, ISSUER_ID (TestFlight / API).

Alternativa futura: voltar a ios_signing na equipa quando Code signing identities
tiver perfil App Store + certificado com visto verde — ver doc Codemagic signing-ios.

Erro: "No matching profiles found for bundle identifier ... app_store"
-----------------------------------------------------------------------
Com o YAML actual este erro NAO deve aparecer (removido ios_signing por bundle).
Se ainda vir mensagem antiga, confirme que o build usa o commit mais recente do main.

Se falhar na fase de assinatura/export: verifique CM_PROVISIONING_PROFILE (tem de ser
perfil App Store, nao Development) e CM_CERTIFICATE (mesmo Apple Distribution do perfil).

Historico: com ios_signing + bundle na equipa, a Codemagic exigia perfil registado
em Code signing identities; sem isso, falhava antes dos scripts.

Ficheiros que pode manter AQUI (cópia de trabalho local; não são lidos automaticamente pelo Flutter):

1) Ficheiro .p8 da API App Store Connect
   - Nome tipico ao descarregar da Apple: AuthKey_XXXXXXXXXX.p8 (10 caracteres = Key ID).
   - Se renomeou (ex.: ApiKey_L9NVXSRXJZ0O.p8), tudo bem — o Key ID NAO se adivinha pelo nome
     do ficheiro: confira na tabela "Chaves ativas" em App Store Connect qual linha corresponde
     a ESTE .p8 e use esse Key ID em APP_STORE_CONNECT_KEY_IDENTIFIER na Codemagic.
   - Colar o CONTEUDO COMPLETO do .p8 em APP_STORE_CONNECT_PRIVATE_KEY (Secret).
   - Só pode ser descarregada UMA vez na Apple; guarde cópia segura (password manager / cofre).
   - NUNCA commite no Git — ignorado: IOS/*.p8 e **/AuthKey_*.p8 na raiz do repo.

2) *.mobileprovision  (ex.: gestaoyahwehiosapp.mobileprovision)
   - Perfil de provisionamento (App Store / Development) para o bundle id acima.
   - Uso opcional na Codemagic: Team settings > codemagic.yaml settings > Code signing identities >
     iOS provisioning profiles > Upload (Reference name à sua escolha).
   - O YAML atual prioriza ios_signing da equipa; override manual: secrets CM_CERTIFICATE + CM_PROVISIONING_PROFILE.
   - NUNCA commite no Git — perfis podem ser revogados/renovados; mantenha local ou na Codemagic.

Codemagic — perfil sem certificado ("Certificate: Not uploaded")
-----------------------------------------------------------------
Se na Codemagic (Team settings > Code signing > iOS provisioning profiles) o perfil
aparece mas a coluna Certificate diz "Not uploaded" / icone vermelho:

  O .mobileprovision sozinho nao basta. E preciso o MESMO certificado Apple Distribution
  que foi usado na Apple ao criar esse perfil.

  Opcoes:
  (1) Na mesma pagina da Codemagic, separador de certificados iOS: fazer upload do
      .p12 do "Apple Distribution" (exportado do Keychain no Mac, com password).
  (2) Ou configurar ios_signing + identidades na equipa Codemagic (recomendado).
  (3) Legado: CERTIFICATE_PRIVATE_KEY + fetch-signing-files — ja nao e o fluxo principal
      deste repositorio; prefira Code signing identities ou CM_CERTIFICATE.

Resumo
------
- A Play Store gere assinatura Android à parte; isto é só Apple/iOS.
- O Xcode no Mac também pode usar o .mobileprovision ao abrir o projeto em flutter_app/ios.

Codemagic — dois layouts de repositorio
---------------------------------------
- Monorepo (esta pasta gestao_yahweh_premium_final na raiz do Git): codemagic.yaml
  na RAIZ do repo (faz cd flutter_app nos scripts).

- Repo so com Flutter na raiz (ex.: mirror iOS): use o ficheiro flutter_app/codemagic.yaml
  deste monorepo como codemagic.yaml na RAIZ desse outro repo (nao use o YAML da raiz
  do monorepo la — os caminhos cd flutter_app falham). O passo do keychain deve mostrar
  nome "API + automatico OU manual P12" ou a linha CM_IOS_SIGNING_REV=...

Codemagic — API App Store Connect SEM integracao nomeada (recomendado)
-----------------------------------------------------------------------
O projeto usa variaveis de ambiente (documentacao Codemagic). Na app / Team, grupo
appstore_credentials (ou o grupo que ligar ao workflow), defina:

  APP_STORE_CONNECT_PRIVATE_KEY   — texto completo do .p8 da API (AuthKey_... ou ApiKey_...)
  APP_STORE_CONNECT_KEY_IDENTIFIER — Key ID (10 caracteres)
  APP_STORE_CONNECT_ISSUER_ID     — Issuer ID (UUID)

Isto substitui integrations: app_store_connect: codemagic e evita o erro
"integration codemagic does not exist".

NOTA: Isto e independente de CERTIFICATE_PRIVATE_KEY (chave do certificado
Apple Distribution). Sao dois segredos diferentes.

Codemagic — CERTIFICATE_PRIVATE_KEY (fetch-signing-files --create)
------------------------------------------------------------------
Este secret e a CHAVE PRIVADA do certificado **Apple Distribution** da tua equipa,
em formato PEM (linhas -----BEGIN ... PRIVATE KEY----- e -----END ...-----).

  - NAO coloques aqui o ficheiro .p8 da API App Store Connect (isso e so para
    APP_STORE_CONNECT_PRIVATE_KEY).
  - Se colaste so o "miolo" base64 sem BEGIN/END, o script falha — usa o PEM completo.

Como obter o PEM a partir de um .p12 (exportado do Keychain no Mac, com password):

  openssl pkcs12 -in AppleDistribution.p12 -nocerts -nodes -out distribution_key.pem

Abre distribution_key.pem, copia TODO o bloco da chave (pode ser BEGIN RSA PRIVATE KEY
ou BEGIN PRIVATE KEY) e cola em CERTIFICATE_PRIVATE_KEY na Codemagic.

Se ainda nao tens .p12: Keychain Access > My Certificates > Apple Distribution: ... >
botao direito > Export (define password), depois usa o comando openssl acima.
Se nunca criaste certificado de distribuicao, cria em developer.apple.com > Certificates
(Apple Distribution) e instala no Keychain antes de exportar.

Codemagic — modo MANUAL (P12 + perfil, sem CERTIFICATE_PRIVATE_KEY)
--------------------------------------------------------------------
Se nao quiseres extrair PEM ou o fetch --create falhar, o codemagic.yaml deteta
CM_CERTIFICATE e usa assinatura manual (documentacao Codemagic).

No mesmo grupo (ex. appstore_credentials), adiciona:

  CM_CERTIFICATE           — Apple Distribution em .p12 codificado em Base64 (uma linha)
  CM_PROVISIONING_PROFILE  — ficheiro .mobileprovision em Base64 (uma linha)
  CM_CERTIFICATE_PASSWORD  — password do .p12 (opcional; secret)

No Mac:

  cat AppleDistribution.p12 | base64 | pbcopy
  cat gestaoyahwehiosapp.mobileprovision | base64 | pbcopy

No Windows (PowerShell, na pasta dos ficheiros):

  [Convert]::ToBase64String([IO.File]::ReadAllBytes("AppleDistribution.p12")) | Set-Clipboard

Remove ou deixa vazio CERTIFICATE_PRIVATE_KEY quando usares este modo (o workflow
nao o exige se CM_CERTIFICATE estiver definido).

Alinhar .p8 da API com chaves ATIVAS na Apple
----------------------------------------------
Em App Store Connect > Integrations > App Store Connect API, o Key ID no secret
tem de ser uma linha da tabela "Ativas". Ex.: chave "gestaoyahwehiosapp" =
JLLQH77UF8 — o .p8 tem de ser o descarregado para ESSA chave (nao reutilizar
ficheiro cujo Key ID ja nao esta na lista). Chave com papel "Desenvolvedor" pode
falhar em criar certificados na UI da Codemagic; use chave "Administrador" ou
crie operacoes no developer.apple.com.

Codemagic — "Authentication credentials are missing or invalid" (API Key)
--------------------------------------------------------------------------
Ao gerar certificado ou usar fetch-signing-files, a Apple devolve isto quando o JWT
da API Key esta errado ou a chave nao corresponde ao Key ID / Issuer ID.

  Verificar na integracao Codemagic (Team settings > Integrations > App Store Connect):
  - Issuer ID: copiar de App Store Connect > Users and Access > Integrations >
    App Store Connect API (ID acima da tabela de chaves, formato UUID).
  - Key ID: tem de ser o da CHAVE API (ex.: nome do ficheiro AuthKey_ABC123XYZ.p8
    -> Key ID = ABC123XYZ), NAO confundir com SKU do app nem Apple ID numerico.
  - Private key: conteudo COMPLETO do ficheiro .p8, incluindo as linhas
    -----BEGIN PRIVATE KEY----- e -----END PRIVATE KEY----- (sem aspas, sem espacos a mais).
  - Se a Codemagic disser "not a valid PEM": nao coloque JSON em volta; nao misture com
    CERTIFICATE_PRIVATE_KEY (outra chave). O workflow normaliza: \\n literais (uma linha),
    CRLF, BOM, aspas externas, e tenta Base64 do .p8.
  - Se a chave foi revogada ou gerou de novo na Apple: tem de apagar a integracao
    antiga na Codemagic e criar outra com o NOVO .p8 (só se descarrega uma vez).

  Permissao da chave na Apple: "App Manager" ou "Admin" costuma ser necessario para
  certificados / perfis.

  Conta Apple Developer tem de estar ATIVA (129 USD/ano) e o mesmo Team da app.

Links úteis
-----------
App Store Connect: https://appstoreconnect.apple.com/
Apple Developer — Certificates, Identifiers & Profiles: https://developer.apple.com/account/resources/
Gerar tokens API: https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api
