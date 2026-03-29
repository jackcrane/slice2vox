#!/bin/bash
set -euo pipefail

# Usage: ./gencolor.sh <icc_profile_path> <output_image> [hex_rgb]
# Example: ./gencolor.sh ../shared/Tavor_Xrite_i1Profiler_VividCMYW.icc pre.png 0000FF

ICC_PROFILE="${1:-}"
OUTPUT_IMAGE="${2:-}"
HEX_IN="${3:-0000FF}"

if [ -z "${ICC_PROFILE}" ] || [ -z "${OUTPUT_IMAGE}" ]; then
  echo "Usage: $0 <icc_profile_path> <output_image> [hex_rgb]" >&2
  exit 1
fi

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
  -profile "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
  -profile "$ICC_PROFILE" \
  "$OUTPUT_IMAGE"