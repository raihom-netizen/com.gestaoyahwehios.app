#!/usr/bin/env bash
# Reforço pós-pod-install: alguns pods (ex.: home_widget) podem fixar 13.x no .pbxproj gerado.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"
case "$(cat /tmp/cm_yw_layout)" in
  mono) IOS_DIR="$ROOT/flutter_app/ios" ;;
  root) IOS_DIR="$ROOT/ios" ;;
  *) echo "ERRO: layout"; exit 1 ;;
esac

if [ ! -d "$IOS_DIR/Pods" ]; then
  echo "AVISO: Pods ausente em $IOS_DIR — execute pod install antes."
  exit 0
fi

# macOS sed (bash 3.2 compatível)
find "$IOS_DIR/Pods" -name "*.pbxproj" 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 13\.0/IPHONEOS_DEPLOYMENT_TARGET = 14.0/g' "$f" || true
  sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 12\.0/IPHONEOS_DEPLOYMENT_TARGET = 14.0/g' "$f" || true
done

echo "OK: deployment target dos Pods verificado/reforçado para 14.0 (home_widget e similares)."
