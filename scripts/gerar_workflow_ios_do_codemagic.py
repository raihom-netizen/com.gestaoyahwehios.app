# Gera .github/workflows/ios_testflight.yml a partir do workflow ios-release
# do codemagic.yaml, preservando cada script exatamente como esta.
import io, yaml, re

SRC = r'C:/gestao_yahweh_premium_final/codemagic.yaml'
DST = r'C:/gestao_yahweh_premium_final/.github/workflows/ios_testflight.yml'

cm = yaml.safe_load(io.open(SRC, encoding='utf-8'))
wf = cm['workflows']['ios-release']
vars_ = wf['environment'].get('vars', {}) or {}
scripts = wf['scripts']
flutter_ver = str(wf['environment'].get('flutter', 'stable'))

# Secrets vem do GitHub; as demais vars vao literais para o env do job.
SEGREDOS = [
    'APP_STORE_CONNECT_PRIVATE_KEY',
    'APP_STORE_CONNECT_KEY_IDENTIFIER',
    'APP_STORE_CONNECT_ISSUER_ID',
    'CERTIFICATE_PRIVATE_KEY',
    'CERTIFICATE_PASSWORD',
    'CM_CERTIFICATE',
    'CM_CERTIFICATE_PASSWORD',
    'CM_PROVISIONING_PROFILE',
    'CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM',
    'FIREBASE_SERVICE_ACCOUNT_JSON',
    'FIREBASE_TOKEN',
]

def esc(v):
    v = str(v)
    if v == '' or re.search(r'[:#{}\[\],&*?|<>=!%@`\'"]', v) or v.strip() != v:
        return "'" + v.replace("'", "''") + "'"
    return v

L = []
A = L.append

A('# iOS — build IPA assinado + TestFlight (Gestao YAHWEH)')
A('# GERADO a partir do workflow "ios-release" do codemagic.yaml: cada passo abaixo roda')
A('# exatamente o mesmo script que rodava no Codemagic. O motor tambem e o mesmo')
A('# (codemagic-cli-tools, open source), e os scripts em scripts/codemagic_ios_* leem')
A('# tudo por variavel de ambiente.')
A('#')
A('# Para regerar depois de mexer no codemagic.yaml:')
A('#   python scripts/gerar_workflow_ios_do_codemagic.py')
A('#')
A('# ---------------------------------------------------------------------------')
A('# Configuracao UNICA (rode: .\\scripts\\configurar_github_ios.ps1)')
A('# Secrets em: Settings > Secrets and variables > Actions')
A('#   APP_STORE_CONNECT_PRIVATE_KEY     conteudo do .p8 da chave App Store Connect API')
A('#   APP_STORE_CONNECT_KEY_IDENTIFIER  Key ID (ex.: 85X9UNAT43)')
A('#   APP_STORE_CONNECT_ISSUER_ID       Issuer ID (UUID)')
A('#   CERTIFICATE_PRIVATE_KEY           Base64 do .p12 Apple Distribution (modo manual)')
A('#   CM_PROVISIONING_PROFILE           Base64 do .mobileprovision App Store (modo manual)')
A('#   CM_CERTIFICATE_PASSWORD           senha do .p12, se tiver')
A('#   FIREBASE_SERVICE_ACCOUNT_JSON     (opcional) service account p/ subir o IPA ao site')
A('# ---------------------------------------------------------------------------')
A('# Disparo: manual (Actions > iOS TestFlight > Run workflow) ou push nas branches')
A('# codemagic-*-ready / ios-release-*.')
A('# Repo privado: runner macOS consome 10x os minutos gratuitos — por isso NAO dispara na main.')
A('')
A('name: iOS TestFlight (Gestao YAHWEH)')
A('')
A('on:')
A('  workflow_dispatch:')
A('    inputs:')
A('      setup_capabilities:')
A("        description: 'Ativar capabilities no App ID (Sign in with Apple, Push, App Groups, Associated Domains). Desmarque nos builds seguintes: economiza minutos de espera.'")
A('        type: boolean')
A('        default: true')
A('      enviar_testflight:')
A("        description: 'Enviar o IPA para o TestFlight'")
A('        type: boolean')
A('        default: true')
A('      subir_site:')
A("        description: 'Subir o IPA para o site (Firebase Storage)'")
A('        type: boolean')
A('        default: true')
A('  push:')
A('    branches:')
A("      - 'codemagic-*-ready'")
A("      - 'ios-release-*'")
A('')
A('concurrency:')
A('  group: ios-release')
A('  cancel-in-progress: false')
A('')
A('jobs:')
A('  build:')
A('    runs-on: macos-26')
A('    timeout-minutes: %d' % int(wf.get('max_build_duration', 120)))
A('    defaults:')
A('      run:')
A('        shell: bash')
A('')
A('    env:')
A('      # CM_BUILD_DIR: os scripts usam ${CM_BUILD_DIR:-...} para achar a raiz do repo.')
A('      CM_BUILD_DIR: ${{ github.workspace }}')
A('      # CM_ENV: arquivo por onde o Codemagic propaga variaveis entre passos.')
A('      # github.env e o equivalente do GitHub Actions (mesmo formato NOME=valor).')
A('      CM_ENV: ${{ github.env }}')
for k, v in vars_.items():
    if k in SEGREDOS:
        continue
    A('      %s: %s' % (k, esc(v)))
for s in SEGREDOS:
    A('      %s: ${{ secrets.%s }}' % (s, s))
A('')
A('    steps:')
A('      - uses: actions/checkout@v4')
A('')
A('      - name: Conferir secrets obrigatorios')
A('        run: |')
A('          faltou=0')
A('          for v in APP_STORE_CONNECT_PRIVATE_KEY APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_ISSUER_ID; do')
A('            if [ -z "${!v}" ]; then echo "::error::Secret ausente: $v"; faltou=1; fi')
A('          done')
A('          if [ "$faltou" != "0" ]; then')
A('            echo "Rode scripts/configurar_github_ios.ps1 para preencher os secrets."')
A('            exit 1')
A('          fi')
A('          echo "Secrets OK."')
A('')
A('      - uses: actions/setup-python@v5')
A('        with:')
A("          python-version: '3.12'")
A('')
A('      - name: Instalar codemagic-cli-tools')
A('        run: pip install --upgrade codemagic-cli-tools PyJWT cryptography')
A('')
A('      - uses: subosito/flutter-action@v2')
A('        with:')
if re.match(r'^\d+\.\d+', flutter_ver):
    A("          flutter-version: '%s'" % flutter_ver)
    A('          channel: stable')
else:
    A('          channel: %s' % flutter_ver)
A('          cache: true')
A('')
A('      # A Apple so aceita upload de app construido com o SDK do iOS 26 (Xcode 26+).')
A('      # A imagem traz varios Xcode 26.x, mas nem todos tem a plataforma iOS instalada')
A('      # (o build morre em "iOS 26.0 is not installed"). Pega o mais novo que TENHA o SDK.')
A('      - name: Selecionar Xcode 26+ com SDK iOS instalado')
A('        run: |')
for linha in '''set -e
LISTA=$(for app in /Applications/Xcode*.app; do
  [ -d "$app" ] || continue
  v=$(/usr/bin/defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
  [ -n "$v" ] && echo "$v|$app"
done | sort -t'|' -k1,1 -Vr)
if [ -z "$LISTA" ]; then echo "::error::nenhum Xcode encontrado no runner"; exit 1; fi
ESCOLHIDO=""
SDK_VER=""
while IFS='|' read -r v app; do
  [ -n "$app" ] || continue
  case "${v%%.*}" in ''|*[!0-9]*) continue ;; esac
  [ "${v%%.*}" -ge 26 ] || continue
  sdk=$(DEVELOPER_DIR="$app/Contents/Developer" xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo "")
  echo "Xcode $v -> SDK iphoneos: ${sdk:-<plataforma iOS nao instalada>}"
  if [ -n "$sdk" ] && [ "${sdk%%.*}" -ge 26 ]; then ESCOLHIDO="$app"; SDK_VER="$sdk"; break; fi
done <<< "$LISTA"
if [ -z "$ESCOLHIDO" ]; then
  echo "::error::nenhum Xcode 26+ com SDK iOS 26 instalado neste runner."
  exit 1
fi
sudo xcode-select -s "$ESCOLHIDO/Contents/Developer"
echo "DEVELOPER_DIR=$ESCOLHIDO/Contents/Developer" >> "$GITHUB_ENV"
echo "Usando: $ESCOLHIDO (SDK iOS $SDK_VER)"'''.split('\n'):
    A('          ' + linha if linha else '')
A('')
A('      - name: Ambiente')
A('        run: |')
A('          xcodebuild -version')
A('          xcodebuild -showsdks | grep -i iphoneos || true')
A('          flutter --version')
A('          app-store-connect --version || true')
A('')

# --- passos portados do codemagic.yaml -------------------------------------
CAPABILITIES = (
    'Ativar Sign In with Apple',
    'Ativar Push Notifications',
    'Ativar App Groups',
    'Registar App Groups',
    'Ativar Associated Domains',
)
SITE = ('Subir IPA para o site',)
OPCIONAIS = ('Firebase App Distribution', 'Upload dSYM')

for st in scripts:
    nome = st.get('name', 'passo')
    corpo = st.get('script', '')
    if not isinstance(corpo, str):
        continue
    A('      - name: %s' % nome)
    if nome.startswith(CAPABILITIES):
        A('        if: inputs.setup_capabilities != false')
    elif nome.startswith(SITE):
        A('        if: inputs.subir_site != false')
        A('        continue-on-error: true')
    elif nome.startswith(OPCIONAIS):
        A('        continue-on-error: true')
    A('        run: |')
    for linha in corpo.rstrip('\n').split('\n'):
        A(('          ' + linha) if linha.strip() else '')
    A('')

# --- artefatos + TestFlight ------------------------------------------------
A('      - name: Guardar IPA como artefato do build')
A('        if: always()')
A('        uses: actions/upload-artifact@v4')
A('        with:')
A('          name: GestaoYahweh-ipa')
A('          path: |')
A('            flutter_app/build/ios/ipa/*.ipa')
A('            *.ipa')
A('          if-no-files-found: warn')
A('          retention-days: 30')
A('')
A('      # No Codemagic o envio ao TestFlight era a secao publishing.app_store_connect;')
A('      # aqui e o mesmo CLI, chamado explicitamente.')
A('      - name: Enviar para o TestFlight (App Store Connect)')
A('        if: inputs.enviar_testflight != false')
A('        run: |')
A('          set -e')
A('          IPA=$(ls -1 flutter_app/build/ios/ipa/*.ipa 2>/dev/null | head -1)')
A('          if [ -z "$IPA" ]; then IPA=$(ls -1 *.ipa 2>/dev/null | head -1); fi')
A('          if [ -z "$IPA" ]; then echo "::error::nenhum .ipa encontrado para enviar"; exit 1; fi')
A('          echo "Enviando: $IPA"')
A('          app-store-connect publish \\')
A('            --path "$IPA" \\')
A('            --testflight')
A('          echo "IPA enviado. Acompanhe em App Store Connect > TestFlight."')
A('')
A('      - name: Guardar piso de build number e PEM de bootstrap')
A('        if: always()')
A('        uses: actions/upload-artifact@v4')
A('        with:')
A('          name: GestaoYahweh-signing-output')
A('          path: |')
A('            flutter_app/ios/asc_build_number_floor.txt')
A('            bootstrap_signing_output/**')
A('          if-no-files-found: ignore')

texto = '\n'.join(L) + '\n'
io.open(DST, 'w', encoding='utf-8', newline='\n').write(texto)

d = yaml.safe_load(io.open(DST, encoding='utf-8'))
print('YAML valido -', len(d['jobs']['build']['steps']), 'passos ->', DST)
