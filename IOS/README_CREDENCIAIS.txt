Pasta IOS — credenciais Apple / App Store (Gestão YAHWEH)
=========================================================

Bundle ID da app na loja: com.gestaoyahwehios.app
App Store Connect — Apple ID do app: 6761656626

Ficheiros que pode manter AQUI (cópia de trabalho local; não são lidos automaticamente pelo Flutter):

1) AuthKey_XXXXXX.p8  (ex.: AuthKey_2LLJKKUA62.p8)
   - Chave privada da API App Store Connect (Users and Access > Integrations > App Store Connect API).
   - Só pode ser descarregada UMA vez na Apple; guarde cópia segura (password manager / cofre).
   - Uso: colar na Codemagic em Team settings > Integrations > App Store Connect (ou variável de ambiente equivalente).
   - NUNCA commite no Git — está ignorado por IOS/*.p8 e **/AuthKey_*.p8 na raiz do repo.

2) *.mobileprovision  (ex.: gestaoyahwehiosapp.mobileprovision)
   - Perfil de provisionamento (App Store / Development) para o bundle id acima.
   - Uso opcional na Codemagic: Team settings > codemagic.yaml settings > Code signing identities >
     iOS provisioning profiles > Upload (Reference name à sua escolha).
   - Alternativa: deixar o workflow criar/obter perfis via app-store-connect fetch-signing-files (com API Key + CERTIFICATE_PRIVATE_KEY).
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
  (2) Ou usar assinatura automatica: variavel CERTIFICATE_PRIVATE_KEY (grupo
      appstore_credentials) + API App Store Connect; o script fetch-signing-files
      obtem/cria certificado e perfil — pode remover o perfil manual duplicado se
      passar tudo pelo CLI.

Resumo
------
- A Play Store gere assinatura Android à parte; isto é só Apple/iOS.
- O Xcode no Mac também pode usar o .mobileprovision ao abrir o projeto em flutter_app/ios.

Codemagic — integration "codemagic" does not exist
-----------------------------------------------
O codemagic.yaml usa por defeito:

  integrations:
    app_store_connect: codemagic

Isto NAO e um nome fixo da Codemagic: e o nome QUE VOCE deu (ou deve dar) a integracao
na Team. Se criou a API Key com outro nome (ex. "GestaoYahweh"), altere a linha no YAML
para esse nome exato, OU crie/edite a integracao na Codemagic para se chamar "codemagic".

Team settings > Integrations > lista de App Store Connect — o nome na lista = valor em app_store_connect.

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
