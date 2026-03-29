# ! /bin/sh

SOURCE_PROFILE="${1:-}"

if [ -z "$SOURCE_PROFILE" ]; then
  echo "Usage: $0 <source_profile.icc>" >&2
  echo "Example: $0 /usr/share/color/icc/ghostscript/srgb.icc" >&2
  exit 1
fi

./matrix.sh "$SOURCE_PROFILE" blue_matrix 0000FF --layers=100 --vary=cm
./matrix.sh "$SOURCE_PROFILE" red_matrix FF0000 --layers=100 --vary=my
./matrix.sh "$SOURCE_PROFILE" green_matrix 00FF00 --layers=100 --vary=cy
