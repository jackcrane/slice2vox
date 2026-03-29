#!/usr/bin/env bash
set -euo pipefail

# run_profiles.sh — convert → dither → scale
# - SINGLE image: produces a STACK (N layers)
# - DIRECTORY: produces ONE dithered PNG per source image (no stacks)
#
# Usage:
#   ./run_profiles.sh [source_path] [out_root] [--layers=100]
#
# Defaults:
#   source_path = input.png  (file or directory)
#   out_root    = out
#   --layers    = 100        (used only in SINGLE-image mode)
#
# Notes:
# - Paths for convert.sh, dither.sh, and the ICM profile are resolved
#   relative to this script’s location (not CWD).
# - Keeps PNGs sharp by using point filter, png24, no interlace.
# - Outputs are saved directly in OUT_ROOT (no profile-named subfolder).

# --- resolve script directory (portable) ---
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

# --- defaults ---
SOURCE_PATH="input.png"
OUT_ROOT="out"
LAYERS="100"

# --- parse args (now: INPUT first, then OUTPUT) ---
positional_count=0
for arg in "$@"; do
  case "$arg" in
    --layers=*)
      LAYERS="${arg#*=}"
      case "$LAYERS" in ''|*[!0-9]*) echo "Invalid --layers: $LAYERS" >&2; exit 1;; esac
      ;;
    --*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *)
      case $positional_count in
        0) SOURCE_PATH="$arg" ;;
        1) OUT_ROOT="$arg" ;;
        *) echo "Too many positional args: $arg" >&2; exit 1 ;;
      esac
      positional_count=$((positional_count+1))
      ;;
  esac
done

CONVERT="$SCRIPT_DIR/convert.sh"
DITHER="$SCRIPT_DIR/dither.sh"
PROFILE="$SCRIPT_DIR/./Stratasys_J750_Vivid_CMY_1mm.icm"

# --- sanity checks ---
[ -f "$CONVERT" ] || { echo "Missing: $CONVERT" >&2; exit 1; }
[ -f "$DITHER" ]  || { echo "Missing: $DITHER"  >&2; exit 1; }
[ -f "$PROFILE" ] || { echo "Profile not found: $PROFILE" >&2; exit 1; }
command -v magick >/dev/null 2>&1 || { echo "ImageMagick 'magick' not found in PATH." >&2; exit 1; }

# --- helpers ---
scale_png_in_place() {
  # scale a single PNG file in-place (2x in X)
  f="$1"
  [ -f "$f" ] || return 0
  tmp="${f}.tmp"
  magick "$f" -filter point -resize 200%x100% -define png:format=png24 -interlace none "$tmp"
  mv -f "$tmp" "$f"
}

scale_pngs_in_dir() {
  dir="$1"
  echo "==> Scaling PNGs in $dir"
  find "$dir" -type f -name '*.png' -print0 | while IFS= read -r -d '' f; do
    scale_png_in_place "$f"
  done
}

process_single_image() {
  src_img="$1"
  [ -f "$src_img" ] || { echo "Source image not found: $src_img" >&2; exit 1; }

  [ -d "$OUT_ROOT" ] && { echo "==> Clearing destination: $OUT_ROOT"; rm -rf "$OUT_ROOT"; }
  mkdir -p "$OUT_ROOT"

  PREPNG="$OUT_ROOT/pre.png"

  echo "==> Mode: SINGLE (convert → dither(stack:$LAYERS) → scale)"
  echo "==> Layers: $LAYERS"

  "$CONVERT" "$PROFILE" "$src_img" "$PREPNG"
  "$DITHER"  "$PREPNG" "$OUT_ROOT" "$LAYERS"

  scale_pngs_in_dir "$OUT_ROOT"
  echo "Done. Output in $OUT_ROOT"
}

process_directory() {
  src_dir="$1"
  [ -d "$src_dir" ] || { echo "Directory not found: $src_dir" >&2; exit 1; }

  [ -d "$OUT_ROOT" ] && { echo "==> Clearing destination: $OUT_ROOT"; rm -rf "$OUT_ROOT"; }
  mkdir -p "$OUT_ROOT"

  echo "==> Mode: DIRECTORY (per-image convert → dither(single) → scale)"
  echo "==> Note: ignores --layers; outputs ONE PNG per source"

  # find source images
  found_any=0
  while IFS= read -r -d '' img; do
    found_any=1
    basefile="$(basename "$img")"
    stem="${basefile%.*}"

    echo "----"
    echo "Processing: $basefile → $stem.png"

    # temp workspace per image
    tmpdir="$(mktemp -d)"
    prepng="$tmpdir/pre.png"
    outtmp="$tmpdir/out"
    mkdir -p "$outtmp"

    # convert to profiled pre.png
    "$CONVERT" "$PROFILE" "$img" "$prepng"

    # Dither to a SINGLE output by forcing 1 layer into a temp dir
    "$DITHER" "$prepng" "$outtmp" 1

    # Grab the first produced PNG (exclude pre.png if the ditherer copies it)
    single="$(find "$outtmp" -type f -name '*.png' ! -name 'pre.png' | sort | head -n 1)"
    if [ -z "$single" ]; then
      echo "No dithered PNG produced for: $img" >&2
      rm -rf "$tmpdir"
      continue
    fi

    # Move to final location with a clean name
    final="$OUT_ROOT/${stem}.png"
    mv -f "$single" "$final"

    # scale that single output (2x X)
    scale_png_in_place "$final"

    # cleanup tmp
    rm -rf "$tmpdir"
  done < <(find "$src_dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.tif' -o -iname '*.tiff' \) -print0)

  if [ "$found_any" -eq 0 ]; then
    echo "No images found in: $src_dir (png/jpg/jpeg/tif/tiff)" >&2
    exit 1
  fi

  echo "Done. Per-image outputs under $OUT_ROOT"
}

# --- dispatch ---
if [ -d "$SOURCE_PATH" ]; then
  process_directory "$SOURCE_PATH"
else
  process_single_image "$SOURCE_PATH"
fi