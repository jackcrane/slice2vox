#!/bin/sh

# Usage: ./count_px.sh input.png

# Get total number of pixels
TOTAL=$(magick "$1" -format "%[fx:w*h]" info:)

magick "$1" -format %c histogram:info:- \
| sed 's/:/ /' \
| awk -v TOTAL="$TOTAL" '
{
  count=$1
  $1=""
  sub(/^ +/, "", $0)
  pct = (count / TOTAL) * 100
  printf "%-8d %-25s  %.4f%%\n", count, $0, pct
}'