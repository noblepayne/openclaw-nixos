#!/bin/sh
set -eu

path="${1:-}"
if [ -z "$path" ] || [ ! -f "$path" ]; then
  exit 0
fi

tmp="$(mktemp)"
jq 'del(.packageManager)' "$path" > "$tmp"
mv "$tmp" "$path"
