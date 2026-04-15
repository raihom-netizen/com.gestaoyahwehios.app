#!/usr/bin/env bash
# Remove .mobileprovision antigos que referenciam o bundle (força uso do perfil novo do secret).
set -euo pipefail

BUNDLE_ID="${IOS_BUNDLE_ID:-com.gestaoyahwehios.app}"
PROFILES_HOME="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES_HOME"

shopt -s nullglob
for f in "$PROFILES_HOME"/*.mobileprovision; do
  if security cms -D -i "$f" 2>/dev/null | grep -qF "$BUNDLE_ID"; then
    echo "Removendo perfil antigo: $(basename "$f")"
    rm -f "$f"
  fi
done
echo "OK: limpeza de perfis para bundle $BUNDLE_ID"
