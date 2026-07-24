#!/usr/bin/env bash
# Download TDLib (libtdjson) prebuilt — Gestão YAHWEH
# Uso (raiz do repo):  ./scripts/download_tdlib.sh
#                      ./scripts/download_tdlib.sh --android-only
#                      ./scripts/download_tdlib.sh --ios-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter_app"
cd "$APP"
flutter pub get
exec dart run tool/download_tdlib.dart "$@"
