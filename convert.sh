#!/bin/sh
set -eu

# Usage: ./convert.sh <profile.icc|icm> <input_image> <output_image>
# Converts an sRGB input into the given printer profile, emitting a PNG
# in a "compatible" 8-bit, non-interlaced, RGBA format.

PROFILE="$1"
INPUT="$2"
OUTPUT="$3"

if [ -z "${PROFILE:-}" ] || [ -z "${INPUT:-}" ] || [ -z "${OUTPUT:-}" ]; then
  echo "Usage: $0 <profile.icc|icm> <input_image> <output_image>" >&2
  exit 1
fi

magick "$INPUT" \
  -profile "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
  -profile "$PROFILE" \
  -strip -alpha on -depth 8 -interlace none \
  -define png:color-type=6 \
  "$OUTPUT"