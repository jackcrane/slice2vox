#!/bin/bash
set -euo pipefail

# dither.sh — wraps index.js for dithering
#
# Usage:
#   ./dither.sh <input_png> <out_dir> [layers]
# Defaults:
#   input  = pre.png
#   out    = out/tavor
#   layers = 100
#
# Notes:
# - Resolves index.js relative to this script's directory.
# - Ensures all paths are handled safely.

INPUT="${1:-pre.png}"
OUTDIR="${2:-out/tavor}"
LAYERS="${3:-100}"

# Resolve this script’s directory
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

INDEX_JS="$SCRIPT_DIR/index.js"

[ -f "$INDEX_JS" ] || { echo "index.js not found at $INDEX_JS" >&2; exit 1; }

mkdir -p "$OUTDIR"

node "$INDEX_JS" "$INPUT" "$OUTDIR" "$LAYERS"