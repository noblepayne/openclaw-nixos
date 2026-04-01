#!/bin/sh
set -e

log_step() {
  if [ "${OPENCLAW_NIX_TIMINGS:-1}" != "1" ]; then
    "$@"
    return
  fi

  name="$1"
  shift

  start=$(date +%s)
  printf '>> [timing] %s...\n' "$name" >&2
  "$@"
  end=$(date +%s)
  printf '>> [timing] %s: %ss\n' "$name" "$((end - start))" >&2
}

store_path_file="${PNPM_STORE_PATH_FILE:-.pnpm-store-path}"
store_path="$(mktemp -d)"

printf "%s" "$store_path" > "$store_path_file"

fetcherVersion=$(cat "$PNPM_DEPS/.fetcher-version" 2>/dev/null || echo 1)
if [ "$fetcherVersion" -ge 3 ]; then
  # tar --zstd uses libzstd; on some platforms it ends up single-threaded.
  # Use zstd directly to enable multi-threaded decompression.
  log_step "extract pnpm store (fetcherVersion=${fetcherVersion})" sh -c '
    zstd -d --threads=0 < "$1" | tar -xf - -C "$2"
  ' sh "$PNPM_DEPS/pnpm-store.tar.zst" "$store_path"
else
  log_step "copy pnpm store (fetcherVersion=${fetcherVersion})" cp -Tr "$PNPM_DEPS" "$store_path"
fi

log_step "chmod pnpm store writable" chmod -R +w "$store_path"

# pnpm --ignore-scripts marks tarball deps as "not built" and offline install
# later refuses to use them; if a dep doesn't require build, promote it.
log_step "promote pnpm integrity" "$PROMOTE_PNPM_INTEGRITY_SH" "$store_path"

export REAL_NODE_GYP="$(command -v node-gyp)"
wrapper_dir="$(mktemp -d)"
install -Dm755 "$NODE_GYP_WRAPPER_SH" "$wrapper_dir/node-gyp"
export PATH="$wrapper_dir:$PATH"
