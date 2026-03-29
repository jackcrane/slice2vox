#!/bin/bash
set -euo pipefail

# Usage: ./gencolor.sh <source_profile.icc> <icc_profile_path> <output_image> [hex_rgb]
# Example: ./gencolor.sh /usr/share/color/icc/ghostscript/srgb.icc ../shared/Tavor_Xrite_i1Profiler_VividCMYW.icc pre.png 0000FF

print_source_profile_help() {
  printf '%s\n' \
    "Usage: $0 <source_profile.icc> <icc_profile_path> <output_image> [hex_rgb]" \
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
ICC_PROFILE="${2:-}"
OUTPUT_IMAGE="${3:-}"
HEX_IN="${4:-0000FF}"

if [ -z "${SOURCE_PROFILE}" ] || [ -z "${ICC_PROFILE}" ] || [ -z "${OUTPUT_IMAGE}" ]; then
  print_source_profile_help
  exit 1
fi

[ -f "${SOURCE_PROFILE}" ] || {
  printf 'Source profile not found: %s\n\n' "${SOURCE_PROFILE}" >&2
  print_source_profile_help
  exit 1
}

# normalize hex (# optional)
HEX_UPPER="$(printf '%s' "${HEX_IN#\#}" | tr '[:lower:]' '[:upper:]')"
case "$HEX_UPPER" in
  ??????|??????) : ;;  # 3 or 6 nibbles accepted
  *) echo "Invalid hex color: ${HEX_IN}" >&2; exit 1 ;;
esac
if [ ${#HEX_UPPER} -eq 3 ]; then
  # expand short form RGB -> RRGGBB
  R="${HEX_UPPER%??}"; G="$(printf '%s' "${HEX_UPPER#?}" | head -c1)"; B="$(printf '%s' "${HEX_UPPER#??}")"
  HEX_UPPER="$(printf '%s%s%s%s%s%s' "$R" "$R" "$G" "$G" "$B" "$B")"
fi
COLOR="#${HEX_UPPER}"

mkdir -p "$(dirname "$OUTPUT_IMAGE")"

magick -size 500x100 xc:"$COLOR" \
  -profile "$SOURCE_PROFILE" \
  -profile "$ICC_PROFILE" \
  "$OUTPUT_IMAGE"
