#!/usr/bin/env bash
# Copia um .ipa para um diretório. Se origem e destino forem o mesmo ficheiro (mesmo inode),
# não chama cp — no macOS `cp` falha: "are identical (not copied)" e quebra `set -e`.
set -eu
src="${1:?uso: $0 <ficheiro.ipa> <dir_destino>}"
destdir="${2:?}"
[ -f "$src" ] || { echo "ERRO: origem nao e ficheiro: $src" >&2; exit 1; }
mkdir -p "$destdir"
dest="$destdir/$(basename "$src")"
if [ -f "$dest" ] && [ "$src" -ef "$dest" ]; then
  echo "OK: IPA ja em $destdir (mesmo ficheiro) — saltar cp."
  exit 0
fi
cp -f "$src" "$destdir/"
