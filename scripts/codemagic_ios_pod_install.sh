#!/usr/bin/env bash
# CocoaPods fiável no CI — garante Pods/FirebaseCrashlytics/run (evita falha no archive).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"

LAYOUT=""
if [ -f /tmp/cm_yw_layout ]; then
  LAYOUT="$(tr -d '\r\n' < /tmp/cm_yw_layout)"
elif [ -f flutter_app/pubspec.yaml ]; then
  LAYOUT=mono
elif [ -f pubspec.yaml ]; then
  LAYOUT=root
else
  echo "ERRO: layout monorepo nao detectado em $ROOT"
  exit 1
fi

case "$LAYOUT" in
  mono)
    FLUTTER_DIR="$ROOT/flutter_app"
    IOS_DIR="$ROOT/flutter_app/ios"
    ;;
  root)
    FLUTTER_DIR="$ROOT"
    IOS_DIR="$ROOT/ios"
    ;;
  *)
    echo "ERRO: layout invalido: $LAYOUT"
    exit 1
    ;;
esac

if [ ! -f "$IOS_DIR/Podfile" ]; then
  echo "ERRO: Podfile ausente: $IOS_DIR/Podfile"
  exit 1
fi

echo "=== pod install (Crashlytics) — $IOS_DIR ==="
bash "$ROOT/scripts/codemagic_ios_ensure_deployment_target_15.sh"
(cd "$FLUTTER_DIR" && flutter pub get)

# Respeitar decisão do passo TDLib auto (/tmp). Sem flag=1 com binário → fallback forçado.
TDLIB_FLAG=0
if [ -f /tmp/cm_yw_tdlib_ios_enabled ]; then
  TDLIB_FLAG="$(tr -d '\r\n' < /tmp/cm_yw_tdlib_ios_enabled)"
fi
if [ "$TDLIB_FLAG" = "1" ]; then
  echo "TDLib iOS nativo solicitado — pod install com flutter_libtdjson."
else
  echo "TDLib iOS fallback — removendo plugin nativo antes do pod install."
  export YAHWEH_TDLIB_FORCE_FALLBACK=1
  bash "$ROOT/scripts/codemagic_ios_apply_tdlib_fallback.sh" "$FLUTTER_DIR" --force
fi

(cd "$FLUTTER_DIR" && flutter config --no-enable-swift-package-manager 2>/dev/null || true)
rm -rf "$IOS_DIR/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm" 2>/dev/null || true

crashlytics_run() {
  [ -f "$IOS_DIR/Pods/FirebaseCrashlytics/run" ]
}

if [ -d "$IOS_DIR/Pods" ] && ! crashlytics_run; then
  echo "AVISO: Pods presentes mas FirebaseCrashlytics/run ausente — reinstalar Pods..."
  rm -rf "$IOS_DIR/Pods" "$IOS_DIR/Podfile.lock" "$IOS_DIR/.symlinks"
fi

# Se ainda houver restos do pod TDLib após fallback, limpar antes do install.
if [ "$TDLIB_FLAG" != "1" ]; then
  rm -rf "$IOS_DIR/Pods/flutter_libtdjson" "$IOS_DIR/.symlinks/plugins/libtdjson" 2>/dev/null || true
fi

(cd "$IOS_DIR" && pod install --repo-update)

# Fail-fast: fallback não pode deixar flutter_libtdjson nos Pods.
if [ "$TDLIB_FLAG" != "1" ] && [ -d "$IOS_DIR/Pods/flutter_libtdjson" ]; then
  echo "ERRO: Pods/flutter_libtdjson ainda presente após fallback — regenerando Pods…"
  rm -rf "$IOS_DIR/Pods" "$IOS_DIR/Podfile.lock" "$IOS_DIR/.symlinks"
  (cd "$FLUTTER_DIR" && flutter pub get)
  bash "$ROOT/scripts/codemagic_ios_apply_tdlib_fallback.sh" "$FLUTTER_DIR" --force
  (cd "$IOS_DIR" && pod install --repo-update)
fi
if [ "$TDLIB_FLAG" != "1" ] && [ -d "$IOS_DIR/Pods/flutter_libtdjson" ]; then
  echo "ERRO: flutter_libtdjson persiste após reinstall — abortando."
  exit 1
fi

if ! crashlytics_run; then
  echo "ERRO: apos pod install, falta $IOS_DIR/Pods/FirebaseCrashlytics/run"
  ls -la "$IOS_DIR/Pods" 2>/dev/null | head -30 || true
  ls -la "$IOS_DIR/Pods/FirebaseCrashlytics" 2>/dev/null || true
  exit 1
fi

if [ ! -f "$IOS_DIR/Pods/FirebaseCrashlytics/upload-symbols" ]; then
  echo "ERRO: falta upload-symbols em Pods/FirebaseCrashlytics"
  exit 1
fi

echo "OK: FirebaseCrashlytics/run e upload-symbols presentes."
