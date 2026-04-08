#!/usr/bin/env bash
# Build IPA para App Store / TestFlight — executar apenas em macOS (Xcode + CocoaPods).
# Raiz do repo: bash scripts/build_ios_ipa_macos.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter_app"
cd "$APP"
flutter pub get
cd ios
pod install
cd ..
flutter build ipa

echo ""
echo "IPA: ver saída do flutter build ipa (ex.: build/ios/ipa/*.ipa)"
