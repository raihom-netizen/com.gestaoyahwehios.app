#!/usr/bin/env bash
# Remove .mobileprovision antigos que referenciam o bundle (força uso do perfil novo do secret).
set -euo pipefail

if [ "${CM_USE_CODEMAGIC_TEAM_SIGNING:-0}" = "1" ] || [ "${CM_USE_CODEMAGIC_TEAM_SIGNING:-}" = "true" ]; then
  echo "OK: saltar remoção de perfis (team_signing — perfis injetados pela Codemagic a partir do YAML)."
  exit 0
fi

if [ "${CM_SKIP_REMOVE_APPSTORE_PROFILES:-0}" = "1" ]; then
  echo "OK: CM_SKIP_REMOVE_APPSTORE_PROFILES=1 — não remover .mobileprovision locais."
  exit 0
fi

_signmode=""
if [ -f /tmp/cm_yw_signing_mode ]; then
  _signmode="$(tr -d '\r\n' < /tmp/cm_yw_signing_mode)"
fi
if [ "$_signmode" = "api_only" ]; then
  echo "OK: modo api_only — não remover perfis antes do fetch (evita pasta vazia se o CLI falhar; fallback REST repõe)."
  exit 0
fi

BUNDLE_ID="${IOS_BUNDLE_ID:-${BUNDLE_ID:-com.gestaoyahwehios.app}}"
WIDGET_BUNDLE_ID="${WIDGET_BUNDLE_ID:-com.gestaoyahwehios.app.GestaoYahwehWidget}"
PROFILES_HOME="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES_HOME"

shopt -s nullglob
for f in "$PROFILES_HOME"/*.mobileprovision; do
  decoded="$(security cms -D -i "$f" 2>/dev/null || true)"
  if printf '%s' "$decoded" | grep -qF "$BUNDLE_ID" || printf '%s' "$decoded" | grep -qF "$WIDGET_BUNDLE_ID"; then
    echo "Removendo perfil antigo: $(basename "$f")"
    rm -f "$f"
  fi
done
echo "OK: limpeza de perfis para bundles $BUNDLE_ID + $WIDGET_BUNDLE_ID"
