#!/bin/sh
set -e
mkdir -p "$out/lib/node_modules/node-addon-api"
tar -xf "$src" --strip-components=1 -C "$out/lib/node_modules/node-addon-api"
