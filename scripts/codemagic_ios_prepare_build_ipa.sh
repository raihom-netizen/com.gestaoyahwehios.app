#!/usr/bin/env bash
# Antes de flutter build ipa: SPM off, limpar integracao SPM no ios/, pod install + Crashlytics.
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
  echo "ERRO: layout monorepo nao detectado"
  exit 1
fi

case "$LAYOUT" in
  mono) FLUTTER_DIR="$ROOT/flutter_app"; IOS_DIR="$ROOT/flutter_app/ios" ;;
  root) FLUTTER_DIR="$ROOT"; IOS_DIR="$ROOT/ios" ;;
  *) echo "ERRO: layout invalido: $LAYOUT"; exit 1 ;;
esac

echo "=== Preparar build IPA (SPM off + Pods Crashlytics) ==="
flutter config --no-enable-swift-package-manager

# SPM ja migrado no cache do CI: remover para nao apagar Pods/FirebaseCrashlytics no archive.
for spm_dir in \
  "$IOS_DIR/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm" \
  "$IOS_DIR/Runner.xcworkspace/xcshareddata/swiftpm" \
  "$IOS_DIR/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration" \
  ; do
  if [ -d "$spm_dir" ]; then
    echo "Remover SPM cache: $spm_dir"
    rm -rf "$spm_dir"
  fi
done

# PackageDependencies no pbxproj (FlutterGeneratedPluginSwiftPackage) — so se existir no projeto.
if [ -f "$IOS_DIR/Runner.xcodeproj/project.pbxproj" ]; then
  if grep -q 'FlutterGeneratedPluginSwiftPackage' "$IOS_DIR/Runner.xcodeproj/project.pbxproj" 2>/dev/null; then
    echo "AVISO: projeto tem FlutterGeneratedPluginSwiftPackage no pbxproj — flutter clean"
    (cd "$FLUTTER_DIR" && flutter clean)
  fi
fi

bash "$ROOT/scripts/codemagic_ios_pod_install.sh"

echo "OK: preparacao IPA concluida (pubspec SPM off + Pods Crashlytics)."
