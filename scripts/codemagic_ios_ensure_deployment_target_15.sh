#!/usr/bin/env bash
# Antes de pod install — Firebase Apple SDK 12.x exige platform :ios, '15.0' no Podfile.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"
case "$(cat /tmp/cm_yw_layout)" in
  mono) IOS_DIR="$ROOT/flutter_app/ios" ;;
  root) IOS_DIR="$ROOT/ios" ;;
  *) echo "ERRO: layout"; exit 1 ;;
esac

PODFILE="$IOS_DIR/Podfile"
PBX="$IOS_DIR/Runner.xcodeproj/project.pbxproj"
PLIST="$IOS_DIR/Flutter/AppFrameworkInfo.plist"

[ -f "$PODFILE" ] || { echo "ERRO: Podfile ausente: $PODFILE"; exit 1; }

if ! grep -qE "platform :ios, '15(\.0)?'" "$PODFILE"; then
  echo "AVISO: Podfile sem platform 15 — a corrigir..."
  sed -i '' "s/platform :ios, '[0-9.]*'/platform :ios, '15.0'/" "$PODFILE" || true
  sed -i '' "s/IPHONEOS_DEPLOYMENT_TARGET'] = '[0-9.]*'/IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'/" "$PODFILE" || true
fi

if [ -f "$PBX" ]; then
  sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 1[0-4]\.0;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' "$PBX" || true
fi

if [ -f "$PLIST" ]; then
  sed -i '' 's/<string>1[0-4]\.0<\/string>/<string>15.0<\/string>/' "$PLIST" || true
fi

if ! grep -qE "platform :ios, '15(\.0)?'" "$PODFILE"; then
  echo "ERRO: Podfile ainda sem platform :ios, '15.0' — cloud_firestore (Firebase 12) vai falhar."
  grep "platform :ios" "$PODFILE" || true
  exit 1
fi

echo "OK: iOS deployment target 15.0 confirmado (Podfile + Runner + AppFrameworkInfo)."
