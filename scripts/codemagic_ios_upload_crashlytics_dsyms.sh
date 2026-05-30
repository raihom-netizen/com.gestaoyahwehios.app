#!/usr/bin/env bash
# Envia dSYMs do Runner.xcarchive → Firebase Crashlytics (iOS).
# Chamado após `flutter build ipa` no Codemagic (layout mono flutter_app/ ou raiz).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"

if [ -f flutter_app/pubspec.yaml ]; then
  FLUTTER_DIR="$ROOT/flutter_app"
elif [ -f pubspec.yaml ]; then
  FLUTTER_DIR="$ROOT"
else
  echo "ERRO: pubspec.yaml nao encontrado em $ROOT"
  exit 1
fi

IOS_DIR="$FLUTTER_DIR/ios"
GSP="$IOS_DIR/Runner/GoogleService-Info.plist"
UPLOAD="$IOS_DIR/Pods/FirebaseCrashlytics/upload-symbols"

if [ ! -f "$GSP" ]; then
  echo "ERRO: GoogleService-Info.plist ausente: $GSP"
  exit 1
fi

if [ ! -f "$UPLOAD" ]; then
  echo "AVISO: $UPLOAD nao encontrado (pod install / FirebaseCrashlytics)."
  exit 0
fi

ARCH=""
for cand in \
  "$FLUTTER_DIR/build/ios/archive/Runner.xcarchive" \
  "$ROOT/build/ios/archive/Runner.xcarchive" \
  "$ROOT/flutter_app/build/ios/archive/Runner.xcarchive"; do
  if [ -d "$cand/dSYMs" ]; then
    ARCH="$cand"
    break
  fi
done

if [ -z "$ARCH" ]; then
  ARCH="$(find "$ROOT" -path "*/build/ios/archive/Runner.xcarchive" -type d 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$ARCH" ] || [ ! -d "$ARCH/dSYMs" ]; then
  echo "AVISO: Runner.xcarchive/dSYMs nao encontrado — upload Crashlytics ignorado."
  exit 0
fi

echo "=== Firebase Crashlytics: upload dSYM ==="
echo "Archive: $ARCH"
echo "GSP: $GSP"

shopt -s nullglob
count=0
fail=0
for dsym in "$ARCH"/dSYMs/*.dSYM; do
  echo "→ $dsym"
  if "$UPLOAD" -gsp "$GSP" -p ios "$dsym"; then
    count=$((count + 1))
  else
    fail=$((fail + 1))
    echo "AVISO: falha ao enviar $(basename "$dsym")"
  fi
done

if [ "$count" -eq 0 ] && [ "$fail" -eq 0 ]; then
  echo "AVISO: pasta dSYMs vazia."
  exit 0
fi

echo "Concluido: $count dSYM(s) enviados; falhas=$fail."
if [ "$count" -eq 0 ]; then
  exit 1
fi
