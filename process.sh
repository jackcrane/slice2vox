for f in icc-bw/*.png; do magick "$f" -filter point -resize 50%x100% -define png:format=png24 -interlace none m.png && mv m.png "$f"; done
echo "icc-bw done"
for f in icc-fw/*.png; do magick "$f" -filter point -resize 50%x100% -define png:format=png24 -interlace none m.png && mv m.png "$f"; done
echo "icc-fw done"
for f in no-icc/*.png; do magick "$f" -filter point -resize 50%x100% -define png:format=png24 -interlace none m.png && mv m.png "$f"; done
echo "no-icc done"
