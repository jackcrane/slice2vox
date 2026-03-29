#!/bin/sh
set -eu

# Usage: ./convert.sh <source_profile.icc> <profile.icc|icm> <input_image> <output_image>
# Converts an sRGB input into the given printer profile, emitting a PNG
# in a "compatible" 8-bit, non-interlaced, RGBA format.

print_source_profile_help() {
  printf '%s\n' \
    "Usage: $0 <source_profile.icc> <profile.icc|icm> <input_image> <output_image>" \
    "" \
    "Pass the path to the source RGB ICC profile explicitly." \
    "Common locations to try:" \
    "  macOS: /System/Library/ColorSync/Profiles/sRGB Profile.icc" \
    "  Ubuntu/Debian (Ghostscript): /usr/share/color/icc/ghostscript/srgb.icc" \
    "  Ubuntu/Debian (colord): /usr/share/color/icc/colord/sRGB.icc" \
    "" \
    "If you are unsure, try: find /usr/share/color -iname '*srgb*.icc' 2>/dev/null" >&2
}

SOURCE_PROFILE="${1:-}"
PROFILE="${2:-}"
INPUT="${3:-}"
OUTPUT="${4:-}"

if [ -z "${SOURCE_PROFILE}" ] || [ -z "${PROFILE}" ] || [ -z "${INPUT}" ] || [ -z "${OUTPUT}" ]; then
  print_source_profile_help
  exit 1
fi

[ -f "$SOURCE_PROFILE" ] || {
  printf 'Source profile not found: %s\n\n' "$SOURCE_PROFILE" >&2
  print_source_profile_help
  exit 1
}

magick "$INPUT" \
  -profile "$SOURCE_PROFILE" \
  -profile "$PROFILE" \
  -strip -alpha on -depth 8 -interlace none \
  -define png:color-type=6 \
  "$OUTPUT"
