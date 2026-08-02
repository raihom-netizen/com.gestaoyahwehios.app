#!/usr/bin/env bash
# Remove apenas o registro nativo iOS do libtdjson 0.3.0 no CI.
# O pacote Dart e o plugin Android permanecem disponíveis.
#
# Uso:
#   bash scripts/codemagic_ios_apply_tdlib_fallback.sh <flutter_dir> [--force]
#
# --force / YAHWEH_TDLIB_FORCE_FALLBACK=1: remove o plugin mesmo se
# YAHWEH_TDLIB_IOS_ENABLED=1 (obrigatório no rebuild após falha de linker).
set -euo pipefail

FLUTTER_DIR="${1:?Informe a pasta Flutter}"
FORCE="${2:-}"

if [ "$FORCE" = "--force" ] || [ "${YAHWEH_TDLIB_FORCE_FALLBACK:-0}" = "1" ]; then
  FORCE=1
else
  FORCE=0
fi

# Preferir flag do auto-script no CI; env do workflow sozinho não bloqueia fallback.
ENABLED_FLAG="${YAHWEH_TDLIB_IOS_ENABLED:-0}"
if [ -f /tmp/cm_yw_tdlib_ios_enabled ]; then
  ENABLED_FLAG="$(tr -d '\r\n' < /tmp/cm_yw_tdlib_ios_enabled)"
fi

if [ "$FORCE" != "1" ] && [ "$ENABLED_FLAG" = "1" ]; then
  # Só mantém nativo se existir binário real (não só pasta vazia).
  BIN=""
  for cand in \
    "$FLUTTER_DIR/ios/Frameworks/libtdjson-static.xcframework" \
    "$FLUTTER_DIR/ios/Frameworks/libtdjson.xcframework"
  do
    if [ -d "$cand" ]; then
      BIN="$(find "$cand" \( -name 'libtdjson.a' -o -name 'libtdjson' \) 2>/dev/null | head -n 1 || true)"
      if [ -n "$BIN" ]; then
        break
      fi
    fi
  done
  if [ -n "$BIN" ]; then
    echo "TDLib iOS nativo mantido (binário: $BIN)."
    exit 0
  fi
  echo "AVISO: YAHWEH_TDLIB_IOS_ENABLED=1 mas sem libtdjson.a — aplicando fallback."
fi

cd "$FLUTTER_DIR"

python3 - <<'PY'
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse

flutter_dir = Path.cwd()
package_config = flutter_dir / '.dart_tool' / 'package_config.json'
manifest = flutter_dir / '.flutter-plugins-dependencies'
legacy_plugins = flutter_dir / '.flutter-plugins'

if not package_config.is_file():
    raise SystemExit('ERRO: .dart_tool/package_config.json ausente — rode flutter pub get antes')

config = json.loads(package_config.read_text(encoding='utf-8'))
package = next(
    (item for item in config.get('packages', []) if item.get('name') == 'libtdjson'),
    None,
)
if package is None:
    print('AVISO: pacote libtdjson não está no package_config — nada a remover no pubspec do plugin.')
else:
    root_uri = package['rootUri']
    parsed = urlparse(root_uri)
    if parsed.scheme == 'file':
        package_root = Path(unquote(parsed.path))
    else:
        package_root = (package_config.parent / unquote(root_uri)).resolve()

    plugin_pubspec = package_root / 'pubspec.yaml'
    if plugin_pubspec.is_file():
        pubspec_text = plugin_pubspec.read_text(encoding='utf-8')
        patched_text, replacements = re.subn(
            r'(?m)^      ios:\r?\n        pluginClass: LibtdjsonPlugin\r?\n',
            '',
            pubspec_text,
        )
        if replacements:
            plugin_pubspec.write_text(patched_text, encoding='utf-8')
            print(f'pubspec do plugin libtdjson: ios pluginClass removido ({replacements}).')
        else:
            print('pubspec do plugin libtdjson: bloco ios já ausente.')

removed_manifest = 0
if manifest.is_file():
    data = json.loads(manifest.read_text(encoding='utf-8'))
    ios_plugins = data.get('plugins', {}).get('ios', []) or []
    before = len(ios_plugins)
    data.setdefault('plugins', {})['ios'] = [
        plugin for plugin in ios_plugins
        if plugin.get('name') != 'libtdjson'
    ]
    removed_manifest = before - len(data['plugins']['ios'])
    manifest.write_text(
        json.dumps(data, separators=(',', ':')),
        encoding='utf-8',
    )
    remaining = [
        plugin for plugin in data['plugins']['ios']
        if plugin.get('name') == 'libtdjson'
    ]
    if remaining:
        raise SystemExit('ERRO: libtdjson ainda registrado em .flutter-plugins-dependencies')

if legacy_plugins.is_file():
    lines = legacy_plugins.read_text(encoding='utf-8').splitlines()
    kept = [ln for ln in lines if not ln.strip().startswith('libtdjson=')]
    if len(kept) != len(lines):
        legacy_plugins.write_text('\n'.join(kept) + ('\n' if kept else ''), encoding='utf-8')
        print(f'.flutter-plugins: removidas {len(lines) - len(kept)} linha(s) libtdjson.')

print(
    'TDLib iOS fallback aplicado: '
    f'manifesto_removido={removed_manifest}.'
)
PY

# Limpar restos CocoaPods / symlinks do pod nativo (evita XCFrameworkIntermediates fantasma).
IOS_DIR="$FLUTTER_DIR/ios"
if [ -d "$IOS_DIR" ]; then
  rm -rf \
    "$IOS_DIR/Pods/flutter_libtdjson" \
    "$IOS_DIR/Pods/libtdjson" \
    "$IOS_DIR/.symlinks/plugins/libtdjson" \
    2>/dev/null || true
  if [ -f "$IOS_DIR/Podfile.lock" ]; then
    # Força regeneração limpa no próximo pod install se o lock ainda cita o pod.
    if grep -Eiq 'flutter_libtdjson|libtdjson' "$IOS_DIR/Podfile.lock"; then
      echo "Podfile.lock ainda cita libtdjson — removendo para regenerar."
      rm -f "$IOS_DIR/Podfile.lock"
    fi
  fi
fi

echo "0" > /tmp/cm_yw_tdlib_ios_enabled
echo "iOS seguirá com Yahweh Chat Firebase; Android mantém TDLib."
