#!/usr/bin/env bash
# Regista App Groups dos entitlements no Developer Portal via Xcode + ASC API key.
# A Connect API NAO consegue marcar group.com… no App ID (APP_GROUP_IDS rejeitado;
# /appGroups 404). Sem esta associacao, perfis IOS_APP_STORE nascem com
# application-groups: [].
#
# Uso (Codemagic, apos /tmp/_asc_ok.pem):
#   bash scripts/codemagic_ios_register_app_groups_via_xcode.sh
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
KEY_ID="${APP_STORE_CONNECT_KEY_IDENTIFIER:-}"
ISSUER="${APP_STORE_CONNECT_ISSUER_ID:-}"
PEM="${APP_STORE_CONNECT_API_KEY_PATH:-/tmp/_asc_ok.pem}"
TEAM="${DEVELOPMENT_TEAM:-82RC6YL7KL}"
APP_GROUP="${APP_GROUP_ID:-group.com.gestaoyahwehios.app.widget}"

if [ ! -f "$PEM" ]; then
  echo "ERRO: PEM ASC ausente ($PEM). Rode «Preparar PEM» antes."
  exit 1
fi
if [ -z "$KEY_ID" ] || [ -z "$ISSUER" ]; then
  echo "ERRO: APP_STORE_CONNECT_KEY_IDENTIFIER / ISSUER_ID vazios."
  exit 1
fi

LAYOUT="$(cat /tmp/cm_yw_layout 2>/dev/null || echo mono)"
case "$LAYOUT" in
  mono) IOS_DIR="$ROOT/flutter_app/ios" ;;
  root) IOS_DIR="$ROOT/ios" ;;
  *)
    if [ -f "$ROOT/flutter_app/ios/Runner.xcodeproj/project.pbxproj" ]; then
      IOS_DIR="$ROOT/flutter_app/ios"
    else
      IOS_DIR="$ROOT/ios"
    fi
    ;;
esac

PROJ="$IOS_DIR/Runner.xcodeproj"
if [ ! -d "$PROJ" ]; then
  echo "ERRO: projeto Xcode nao encontrado: $PROJ"
  exit 1
fi

echo "=== Registar App Groups via xcodebuild (ASC API key) ==="
echo "  project: $PROJ"
echo "  team: $TEAM"
echo "  app group: $APP_GROUP"
echo "  key id: $KEY_ID"

cd "$IOS_DIR"

# Copia PEM para nome AuthKey_*.p8 (Xcode/xcodebuild prefere este formato).
AUTH_KEY="/tmp/AuthKey_${KEY_ID}.p8"
cp -f "$PEM" "$AUTH_KEY"
chmod 600 "$AUTH_KEY"

# build-for-testing / build leve com Automatic + REGISTER_APP_GROUPS:
# Xcode associa group.com… aos App IDs (Runner + Widget) no portal.
# Nao precisa de archive completo — falhas de compile tardias sao aceites
# desde que a assinatura/provisioning tenha corrido.
set +e
xcodebuild \
  -project Runner.xcodeproj \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -authenticationKeyPath "$AUTH_KEY" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM" \
  REGISTER_APP_GROUPS=YES \
  build \
  -quiet 2>&1 | tee /tmp/cm_register_app_groups_xcode.log | tail -n 80
XC_EXIT=${PIPESTATUS[0]}
set -e

if [ "$XC_EXIT" -eq 0 ]; then
  echo "OK: xcodebuild concluiu — App Groups devem estar associados no portal."
else
  echo "AVISO: xcodebuild exit=$XC_EXIT — a verificar se provisioning/App Groups avançou..."
  if grep -qiE "Provisioning|REGISTER_APP_GROUPS|application-groups|App Group|Signing|profile" /tmp/cm_register_app_groups_xcode.log 2>/dev/null; then
    echo "OK: log mostra atividade de assinatura/provisioning (associacao provavelmente feita)."
  else
    echo "AVISO: sem sinais claros de provisioning no log; perfil pode continuar sem group.com…"
    # Nao falhar aqui — o passo do perfil Widget valida de forma estrita depois.
  fi
fi

echo "Aguardando propagacao portal (30s)..."
sleep 30
echo "=== Fim registo App Groups via Xcode ==="
