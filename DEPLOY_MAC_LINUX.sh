#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

firebase use gestaoyahweh-21e23

echo "Building Flutter Web..."
( cd flutter_app && flutter pub get && flutter build web --release )

( cd functions && npm ci )

firebase deploy --only hosting,functions,firestore:rules

echo "OK! Deploy concluido."
