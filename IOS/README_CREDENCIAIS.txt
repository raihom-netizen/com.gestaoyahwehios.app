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

O QUE SAO (em linguagem simples)
--------------------------------
CM_CERTIFICATE
  E o teu certificado Apple de DISTRIBUICAO (nao e o de desenvolvimento), guardado
  num ficheiro .p12 no teu Mac. A Apple usa isso para provar que SO TU podes assinar
  a app para enviar a App Store. Na Codemagic nao se cola o ficheiro .p12 em bruto:
  converte-se o ficheiro para TEXTO Base64 (uma linha gigante) e esse texto e que
  colas no secret CM_CERTIFICATE.

CM_PROVISIONING_PROFILE
  E um ficheiro .mobileprovision que diz: "esta app (bundle com.gestaoyahwehios.app)
  pode ser assinada com ESTE certificado e ESTA team". Tambem se converte para Base64
  (uma linha) e cola-se no secret CM_PROVISIONING_PROFILE. Tem de ser perfil tipo
  App Store (distribuicao), nao so desenvolvimento.

O QUE FAZER — passo a passo
---------------------------
A) Obter / confirmar o .p12 (Apple Distribution)
   1. No Mac: abre "Keychain Access" (Acesso ao Keychain).
   2. Categoria "My Certificates" / "Os meus certificados".
   3. Procura algo como "Apple Distribution: Nome (Team ID)".
   4. Se existir: clica direito > Exportar > guarda como .p12 e define uma PASSWORD
      (anota-a — e o CM_CERTIFICATE_PASSWORD na Codemagic se o script pedir).
   5. Se NAO existir: em developer.apple.com > Account > Certificates > cria
      "Apple Distribution", instala no Mac, depois exporta .p12 como acima.

B) Obter o .mobileprovision (App Store, bundle com.gestaoyahwehios.app)
   1. Em developer.apple.com > Account > Profiles > + (novo perfil).
   2. Tipo: App Store Connect (distribuicao App Store).
   3. App ID: o que tem bundle com.gestaoyahwehios.app.
   4. Certificado: o Apple Distribution que corresponde ao .p12 de cima.
   5. Gera, descarrega o ficheiro .mobileprovision (nome tipo xxxxx.mobileprovision).

C) Transformar em "uma linha Base64" e colar na Codemagic
   No Mac (Terminal), na pasta onde estao os ficheiros:

     cat NomeDoFicheiro.p12 | base64 | pbcopy
     cat NomeDoPerfil.mobileprovision | base64 | pbcopy

   O pbcopy copia para a area de transferencia. Depois:
   1. Codemagic > Team > Environment variables > grupo appstore_credentials (ou o que
      o workflow usa).
   2. Cria/edita variavel CM_CERTIFICATE — cola o conteudo copiado do .p12 (e UMA linha).
   3. Cria/edita variavel CM_PROVISIONING_PROFILE — cola o conteudo copiado do .mobileprovision.
   4. Opcional: CM_CERTIFICATE_PASSWORD = password que definiste ao exportar o .p12.
   5. Guarda. Nomes tem de ser EXACTAMENTE CM_CERTIFICATE e CM_PROVISIONING_PROFILE.

   No Windows (PowerShell, na pasta dos ficheiros):

     [Convert]::ToBase64String([IO.File]::ReadAllBytes(".\AppleDistribution.p12")) | Set-Clipboard
     [Convert]::ToBase64String([IO.File]::ReadAllBytes(".\perfil.mobileprovision")) | Set-Clipboard

   Depois cola no browser da Codemagic nos mesmos nomes de variavel.

D) Nao colar o ficheiro binario nem "miolo" cortado — so o resultado completo do Base64.

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

Erro Codemagic: "base64: stdin: (null): error decoding base64 input stream"
        ou "CM_PROVISIONING_PROFILE nao decodifica em Base64 valido"
---------------------------------------------------------------------------
Quase sempre e o secret CM_PROVISIONING_PROFILE (por vezes CM_CERTIFICATE):

  - Valor NAO e Base64 do ficheiro .mobileprovision BINARIO (ex.: colou o XML/plist
    que aparece se abrires o ficheiro como texto no editor — isso NAO serve).
  - Secret cortado ou com aspas/linhas a mais; ou nome da variavel diferente de
    CM_PROVISIONING_PROFILE.
  - Grupo appstore_credentials nao ligado ao workflow da app na Codemagic.

Correcao: gera de novo o Base64 a partir do ficheiro descarregado (.mobileprovision).

  Mac:  base64 -i caminho/PerfilAppStore.mobileprovision | tr -d '\n' | pbcopy

  Windows (PowerShell — caminho completo ou .\\ficheiro):

    [Convert]::ToBase64String([IO.File]::ReadAllBytes("D:\temporarios\perfil.mobileprovision")) | Set-Clipboard

Cola UMA linha continua no secret CM_PROVISIONING_PROFILE (grupo appstore_credentials).
O codemagic.yaml valida P12 + provisioning no passo "Verificar variaveis Apple" antes
do CocoaPods para falhar mais cedo com mensagem clara.

No Windows (P12), mesmo padrao:

  [Convert]::ToBase64String([IO.File]::ReadAllBytes("AppleDistribution.p12")) | Set-Clipboard

Remove ou deixa vazio CERTIFICATE_PRIVATE_KEY quando usares este modo (o workflow
nao o exige se CM_CERTIFICATE estiver definido).

Erro Codemagic: "Multiline variable APP_STORE_CONNECT_PRIVATE_KEY is not closed with delimiter ..."
---------------------------------------------------------------------------------------------------
Causas corrigidas no codemagic.yaml: (1) newline antes do delimitador de fecho; (2) nao fazer
export da PEM multilinha no mesmo passo (o Codemagic regrava CM_ENV e partia o bloco); (3) gravar
a PEM normalizada em CM_ENV so no FIM do passo JWT, depois do keychain. Atualize o main e rebuild.

Se o build na UI ainda mostrar commit antigo (ex. c1492df), nao esta a usar o YAML novo —
inicie build explicitamente no ultimo commit do main.

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
