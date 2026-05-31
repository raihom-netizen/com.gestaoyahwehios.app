#!/usr/bin/env bash
# Envia dSYMs do Runner.xcarchive → Firebase Crashlytics (iOS).
# Obrigatório no CI (Codemagic): falha o build se não enviar — evita e-mail «Missing dSYM».
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
RUN_SCRIPT="$IOS_DIR/Pods/FirebaseCrashlytics/run"

if [ ! -f "$GSP" ]; then
  echo "ERRO: GoogleService-Info.plist ausente: $GSP"
  exit 1
fi

ensure_pods() {
  if [ -f "$UPLOAD" ]; then
    return 0
  fi
  echo "Pods/FirebaseCrashlytics ausente — a executar pod install..."
  (cd "$IOS_DIR" && pod install --repo-update)
}

ensure_pods

if [ ! -f "$UPLOAD" ]; then
  echo "ERRO: $UPLOAD nao encontrado apos pod install."
  exit 1
fi

read_google_app_id() {
  python3 - <<'PY' "$GSP"
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    p = plistlib.load(f)
print(p.get("GOOGLE_APP_ID", "").strip())
PY
}

find_xcarchive() {
  local cand arch
  for cand in \
    "$FLUTTER_DIR/build/ios/archive/Runner.xcarchive" \
    "$ROOT/build/ios/archive/Runner.xcarchive" \
    "$ROOT/flutter_app/build/ios/archive/Runner.xcarchive"; do
    if [ -d "$cand/dSYMs" ]; then
      echo "$cand"
      return 0
    fi
  done
  while IFS= read -r arch; do
    if [ -n "$arch" ] && [ -d "$arch/dSYMs" ]; then
      echo "$arch"
      return 0
    fi
  done < <(find "$ROOT" "$FLUTTER_DIR" -path "*/build/ios/archive/*.xcarchive" -type d 2>/dev/null | head -20)
  return 1
}

ARCH="$(find_xcarchive || true)"
if [ -z "$ARCH" ] || [ ! -d "$ARCH/dSYMs" ]; then
  echo "ERRO: Runner.xcarchive/dSYMs nao encontrado (flutter build ipa deve gerar o archive)."
  find "$ROOT" "$FLUTTER_DIR" -name "*.xcarchive" -type d 2>/dev/null | head -15 || true
  exit 1
fi

printf '%s\n' "$ARCH" > /tmp/cm_ios_xcarchive_path
echo "=== Firebase Crashlytics: upload dSYM (obrigatorio) ==="
echo "Archive: $ARCH"
echo "GSP: $GSP"
ls -la "$ARCH/dSYMs" || true

GOOGLE_APP_ID="$(read_google_app_id || true)"
if [ -z "$GOOGLE_APP_ID" ]; then
  echo "AVISO: GOOGLE_APP_ID nao lido do plist; upload-symbols usa -gsp."
fi

upload_one() {
  local path="$1"
  echo "→ upload-symbols: $(basename "$path")"
  "$UPLOAD" -gsp "$GSP" -p ios "$path"
}

shopt -s nullglob
count=0
fail=0

# Pasta inteira (Firebase aceita diretorio dSYMs).
set +e
upload_one "$ARCH/dSYMs"
dir_ok=$?
set -e
if [ "$dir_ok" -eq 0 ]; then
  count=$((count + 1))
  echo "OK: upload em lote da pasta dSYMs."
else
  echo "AVISO: upload da pasta dSYMs falhou — tentando cada .dSYM."
  for dsym in "$ARCH"/dSYMs/*.dSYM; do
    set +e
    upload_one "$dsym"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      count=$((count + 1))
    else
      fail=$((fail + 1))
      echo "ERRO: falha ao enviar $(basename "$dsym")"
    fi
  done
fi

# Fallback: firebase-tools (mesma conta do App Distribution).
if [ -n "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ] && [ -n "$GOOGLE_APP_ID" ]; then
  if command -v firebase >/dev/null 2>&1 || npm install -g firebase-tools@13 >/dev/null 2>&1; then
    printf '%s\n' "$FIREBASE_SERVICE_ACCOUNT_JSON" > /tmp/gcp-sa-crashlytics.json
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp-sa-crashlytics.json
    echo "→ firebase crashlytics:symbols:upload (fallback)"
    set +e
    firebase crashlytics:symbols:upload --app="$GOOGLE_APP_ID" "$ARCH/dSYMs"
    fb_rc=$?
    set -e
    if [ "$fb_rc" -eq 0 ]; then
      echo "OK: firebase crashlytics:symbols:upload"
      count=$((count + 1))
    else
      echo "AVISO: firebase crashlytics:symbols:upload exit=$fb_rc (upload-symbols ja tentado)."
    fi
  fi
fi

if [ "$count" -eq 0 ]; then
  echo "ERRO: nenhum dSYM enviado ao Firebase Crashlytics (falhas=$fail)."
  exit 1
fi

echo "Concluido: Crashlytics recebeu simbolos desta build ($count operacao(oes) OK; falhas parciais=$fail)."
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ) archive=$ARCH count=$count" > /tmp/cm_crashlytics_dsym_upload_ok
