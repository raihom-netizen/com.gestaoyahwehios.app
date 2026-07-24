#!/usr/bin/env bash
# Regista App Groups no portal via Xcode + ASC API key — SO o target Widget.
# Nao usa scheme Runner (Flutter/Pods ainda nao existem nesta fase do CI).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
KEY_ID="${APP_STORE_CONNECT_KEY_IDENTIFIER:-}"
ISSUER="${APP_STORE_CONNECT_ISSUER_ID:-}"
PEM="${APP_STORE_CONNECT_API_KEY_PATH:-/tmp/_asc_ok.pem}"
TEAM="${DEVELOPMENT_TEAM:-82RC6YL7KL}"
APP_GROUP="${APP_GROUP_ID:-group.com.gestaoyahwehios.app.widget}"
WIDGET_TARGET="${WIDGET_XCODE_TARGET:-GestaoYahwehWidgetExtension}"

if [ ! -f "$PEM" ]; then
  echo "ERRO: PEM ASC ausente ($PEM)."
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
cd "$IOS_DIR"

AUTH_KEY="/tmp/AuthKey_${KEY_ID}.p8"
cp -f "$PEM" "$AUTH_KEY"
chmod 600 "$AUTH_KEY"

echo "=== Registar App Groups (target $WIDGET_TARGET, sem Flutter) ==="
echo "  project: $PROJ"
echo "  team: $TEAM"
echo "  group: $APP_GROUP"

set +e
xcodebuild \
  -project Runner.xcodeproj \
  -target "$WIDGET_TARGET" \
  -configuration Release \
  -sdk iphoneos \
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
  2>&1 | tee /tmp/cm_register_app_groups_xcode.log | tail -n 100
XC_EXIT=${PIPESTATUS[0]}
set -e

if [ "$XC_EXIT" -eq 0 ]; then
  echo "OK: Widget target assinado — App Group deve estar no portal."
else
  echo "AVISO: xcodebuild Widget exit=$XC_EXIT"
  # Continua: o alinhamento de entitlements evita falha dura no CI.
fi

# Tenta tambem Runner se Generated.xcconfig ja existir (pos-pods).
if [ -f Flutter/Generated.xcconfig ] || [ -f Flutter/flutter_export_environment.sh ]; then
  echo "=== Registar App Groups no Runner (Flutter presente) ==="
  set +e
  xcodebuild \
    -project Runner.xcodeproj \
    -scheme Runner \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$AUTH_KEY" \
    -authenticationKeyID "$KEY_ID" \
    -authenticationKeyIssuerID "$ISSUER" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM" \
    REGISTER_APP_GROUPS=YES \
    build \
    2>&1 | tee -a /tmp/cm_register_app_groups_xcode.log | tail -n 40
  set -e
fi

echo "Propagacao portal 20s..."
sleep 20
echo "=== Fim registo App Groups ==="
exit 0
