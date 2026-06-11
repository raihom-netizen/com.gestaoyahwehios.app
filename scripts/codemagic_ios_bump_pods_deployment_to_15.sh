#!/usr/bin/env bash
# Pós-pod-install: alguns pods fixam 13.x/14.x no .pbxproj gerado — Firebase 12+ exige 15.0.
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

find "$IOS_DIR/Pods" -name "*.pbxproj" 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 12\.0/IPHONEOS_DEPLOYMENT_TARGET = 15.0/g' "$f" || true
  sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 13\.0/IPHONEOS_DEPLOYMENT_TARGET = 15.0/g' "$f" || true
  sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 14\.0/IPHONEOS_DEPLOYMENT_TARGET = 15.0/g' "$f" || true
done

echo "OK: deployment target dos Pods reforçado para 15.0 (Firebase 12 / cloud_firestore)."
