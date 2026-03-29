#!/bin/sh
set -euo pipefail

# matrix.sh — 1×N CMY bump matrix for a given HEX color (POSIX sh)
#
# Usage:
#   ./matrix.sh <out_root> <hex_rgb> [--layers=N] [--vary=cm|my|cy]
# Defaults:
#   out_root=blue_matrix   hex_rgb=0000FF   layers=100   vary=cm
#
# Env:
#   PROFILE=../shared/profiles/Stratasys_J750_Vivid_CMY_1mm.icm
#   HALFTONE_JS=./index.js
#   GENCOLOR=./gencolor.sh
#   # Sequences (applied to the two channels selected by --vary). Must yield equal counts.
#   SWEEP_A_SEQ="0:0.5:0.05"   # first channel in --vary (e.g., c in cm)
#   SWEEP_B_SEQ="0.5:0:-0.05"  # second channel in --vary (e.g., m in cm)
#   FIXED_VAL="0"              # the third channel (not in --vary)
#   KEEP_WORK=1                # keep temp workspace

OUT_ROOT="${1:-blue_matrix}"
HEX_RGB="${2:-0000FF}"

LAYERS=100
VARY_PAIR="cm" # default: cyan↔magenta
# consume flags after the two positionals
set -- ${3+"$@"}
for arg in "$@"; do
  case "$arg" in
    --layers=*) LAYERS="${arg#--layers=}" ;;
    --vary=*) VARY_PAIR="$(printf '%s' "${arg#--vary=}" | tr '[:upper:]' '[:lower:]')" ;;
  esac
done

PROFILE="${PROFILE:-../shared/profiles/Stratasys_J750_Vivid_CMY_1mm.icm}"
HALFTONE_JS="${HALFTONE_JS:-./index.js}"
GENCOLOR="${GENCOLOR:-./gencolor.sh}"

SWEEP_A_SEQ="${SWEEP_A_SEQ:-0:0.5:0.05}"
SWEEP_B_SEQ="${SWEEP_B_SEQ:-0.5:0:-0.05}"
FIXED_VAL="${FIXED_VAL:-0}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need magick
need awk
[ -f "$PROFILE" ] || { echo "Profile not found: $PROFILE" >&2; exit 1; }
[ -f "$HALFTONE_JS" ] || { echo "Halftone JS not found: $HALFTONE_JS" >&2; exit 1; }
[ -f "$GENCOLOR" ] || { echo "gencolor script not found: $GENCOLOR" >&2; exit 1; }

# validate vary pair
case "$VARY_PAIR" in
  cm|mc|my|ym|cy|yc) : ;;
  *) echo "Invalid --vary=$VARY_PAIR (use: cm, my, cy)" >&2; exit 1 ;;
esac
# normalize to canonical order we will iterate in (keep user order important: first = A, second = B)
VARY_A="$(printf '%s' "$VARY_PAIR" | cut -c1)"
VARY_B="$(printf '%s' "$VARY_PAIR" | cut -c2)"

mkws() { mktemp -d -t matrix.XXXXXX 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/matrix.XXXXXX"; }
WORK_ROOT="$(mkws)"
if [ "${KEEP_WORK:-0}" -eq 0 ]; then trap 'rm -rf "$WORK_ROOT"' EXIT; else echo "KEEP_WORK=1 → $WORK_ROOT"; fi

# --- sequences into files (one value per line)
seq_file() {
  awk -v spec="$1" '
    BEGIN{
      n=split(spec,a,":"); if(n!=3){print "Bad seq: "spec >"/dev/stderr"; exit 1}
      start=a[1]+0; end=a[2]+0; step=a[3]+0; if(step==0){print "Zero step" >"/dev/stderr"; exit 1}
      eps=1e-9
      if(step>0){ for(x=start; x<=end+eps; x+=step) printf "%.10g\n", x }
      else      { for(x=start; x>=end-eps; x+=step) printf "%.10g\n", x }
    }'
}

A_FILE="$WORK_ROOT/A.txt";  B_FILE="$WORK_ROOT/B.txt"
seq_file "$SWEEP_A_SEQ" > "$A_FILE"
seq_file "$SWEEP_B_SEQ" > "$B_FILE"
NC=$(wc -l < "$A_FILE" | tr -d ' ')
NB=$(wc -l < "$B_FILE" | tr -d ' ')
[ "$NC" -eq "$NB" ] || { echo "Sweep length mismatch: A=$NC vs B=$NB" >&2; exit 1; }

echo "==> Columns: $NC (vary=$VARY_A sw $VARY_B)"
echo "==> Layers:  $LAYERS"
echo "==> Profile: $(basename "$PROFILE")"
echo "==> Color:   #$HEX_RGB"
echo "==> Seqs:    A=$SWEEP_A_SEQ  B=$SWEEP_B_SEQ  fixed=$FIXED_VAL"

# 1) base 100x100 square with profile for HEX
PREPNG="$WORK_ROOT/pre.png"
"$GENCOLOR" "$PROFILE" "$PREPNG" "$HEX_RGB"
[ -f "$PREPNG" ] || { echo "Failed to create $PREPNG" >&2; exit 1; }

# 2) halftone each column (map A/B to C/M/Y according to VARY_A/VARY_B)
map_to_cmy() {
  # $1=A, $2=B → prints "c m y"
  A="$1"; B="$2"; F="$3"
  C="$F"; M="$F"; Y="$F"
  case "$VARY_A" in c) C="$A";; m) M="$A";; y) Y="$A";; esac
  case "$VARY_B" in c) C="$B";; m) M="$B";; y) Y="$B";; esac
  printf '%s %s %s\n' "$C" "$M" "$Y"
}

i=0
paste "$A_FILE" "$B_FILE" | while IFS="$(printf '\t')" read -r AVAL BVAL; do
  set -- $(map_to_cmy "$AVAL" "$BVAL" "$FIXED_VAL")
  CVAL="$1"; MVAL="$2"; YVAL="$3"
  COL_DIR="$WORK_ROOT/col_$(printf '%02d' "$i")"
  rm -rf "$COL_DIR"; mkdir -p "$COL_DIR"
  echo "   -> col $(printf '%02d' "$i"): C=$(printf '%.2f' "$CVAL") M=$(printf '%.2f' "$MVAL") Y=$(printf '%.2f' "$YVAL")"
  node "$HALFTONE_JS" "$PREPNG" "$COL_DIR" "$LAYERS" --c="$CVAL" --m="$MVAL" --y="$YVAL" >/dev/null
  if ! find "$COL_DIR" -type f \( -name '*.png' -o -iname '*.tif' -o -iname '*.tiff' \) | grep -q .; then
    echo "No slices produced in $COL_DIR" >&2; exit 1
  fi
  i=$((i+1))
done

# 3) detect slice extension & height
REF_DIR="$WORK_ROOT/col_00"
if find "$REF_DIR" -type f -name '*.png' | grep -q .; then EXT='png'
elif find "$REF_DIR" -type f -iname '*.tif' | grep -q .; then EXT='tif'
elif find "$REF_DIR" -type f -iname '*.tiff' | grep -q .; then EXT='tiff'
else echo "Cannot detect slice extension in $REF_DIR" >&2; exit 1; fi
echo "==> Detected slice type: *.$EXT"

REF_LIST="$WORK_ROOT/ref_layers.txt"
find "$REF_DIR" -type f -name "*.$EXT" -print | sort > "$REF_LIST"
REF_COUNT=$(wc -l < "$REF_LIST" | tr -d ' ')
[ "$REF_COUNT" -gt 0 ] || { echo "No slices in ref column" >&2; exit 1; }

# get height from first ref image
FIRST_REF="$(head -n1 "$REF_LIST")"
HEIGHT="$(magick identify -format '%h' "$FIRST_REF")"

# 4) merge horizontally with 5px white spacers → OUT_ROOT
rm -rf "$OUT_ROOT"; mkdir -p "$OUT_ROOT"
echo "==> Merging into: $OUT_ROOT (5px white spacers)"
while IFS= read -r REF; do
  BASE="$(basename "$REF")"
  LST="$WORK_ROOT/list_$BASE.txt"; : > "$LST"
  idx=0
  while [ "$idx" -lt "$NC" ]; do
    COL_PATH="$(printf '%s/col_%02d/%s' "$WORK_ROOT" "$idx" "$BASE")"
    [ -f "$COL_PATH" ] || { echo "Missing $BASE in col_$(printf '%02d' "$idx")" >&2; exit 1; }
    printf '%s\n' "$COL_PATH" >> "$LST"
    idx=$((idx+1))
    if [ "$idx" -lt "$NC" ]; then
      printf 'xc:white[%sx%s]\n' "5" "$HEIGHT" >> "$LST"
    fi
  done
  OUT="$OUT_ROOT/$BASE"
  if [ "$NC" -gt 1 ]; then magick @"$LST" +append "$OUT"; else magick @"$LST" "$OUT"; fi
done < "$REF_LIST"

# 5) scale 2x in X with point filter
echo "==> Scaling (2x X, point)"
if [ "$EXT" = "png" ]; then
  find "$OUT_ROOT" -type f -name '*.png' -print0 | while IFS= read -r -d '' f; do
    t="$f.tmp"
    magick "$f" -filter point -resize 200%x100% -define png:format=png24 -interlace none "$t"
    mv -f "$t" "$f"
  done
else
  find "$OUT_ROOT" -type f \( -iname '*.tif' -o -iname '*.tiff' \) -print0 | while IFS= read -r -d '' f; do
    t="$f.tmp"
    magick "$f" -filter point -resize 200%x100% "$t"
    mv -f "$t" "$f"
  done
fi

COUNT=$(find "$OUT_ROOT" -type f -name "*.$EXT" | wc -l | tr -d ' ')
echo "Done. Wrote $COUNT merged layers to: $OUT_ROOT"