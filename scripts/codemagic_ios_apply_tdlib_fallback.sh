#!/usr/bin/env bash
# Remove apenas o registro nativo iOS do libtdjson 0.3.0 no CI.
# O pacote Dart e o plugin Android permanecem disponíveis.
set -euo pipefail

FLUTTER_DIR="${1:?Informe a pasta Flutter}"

if [ "${YAHWEH_TDLIB_IOS_ENABLED:-0}" = "1" ]; then
  echo "TDLib iOS explicitamente ativado; mantendo plugin nativo."
  exit 0
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

config = json.loads(package_config.read_text(encoding='utf-8'))
package = next(
    (item for item in config.get('packages', []) if item.get('name') == 'libtdjson'),
    None,
)
if package is None:
    raise SystemExit('ERRO: pacote libtdjson não encontrado em package_config.json')

root_uri = package['rootUri']
parsed = urlparse(root_uri)
if parsed.scheme == 'file':
    package_root = Path(unquote(parsed.path))
else:
    package_root = (package_config.parent / unquote(root_uri)).resolve()

plugin_pubspec = package_root / 'pubspec.yaml'
pubspec_text = plugin_pubspec.read_text(encoding='utf-8')
patched_text, replacements = re.subn(
    r'(?m)^      ios:\r?\n        pluginClass: LibtdjsonPlugin\r?\n',
    '',
    pubspec_text,
)
if replacements:
    plugin_pubspec.write_text(patched_text, encoding='utf-8')

data = json.loads(manifest.read_text(encoding='utf-8'))
ios_plugins = data.get('plugins', {}).get('ios', [])
before = len(ios_plugins)
data['plugins']['ios'] = [
    plugin for plugin in ios_plugins
    if plugin.get('name') != 'libtdjson'
]
manifest.write_text(
    json.dumps(data, separators=(',', ':')),
    encoding='utf-8',
)

remaining = [
    plugin for plugin in data['plugins']['ios']
    if plugin.get('name') == 'libtdjson'
]
if remaining:
    raise SystemExit('ERRO: libtdjson ainda registrado para iOS')

print(
    'TDLib iOS removido com persistência: '
    f'pubspec do plugin ajustado={bool(replacements)}, '
    f'manifesto removido={before - len(data["plugins"]["ios"])}.'
)
PY

echo "iOS seguirá com Yahweh Chat Firebase; Android mantém TDLib."
