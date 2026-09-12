#!/usr/bin/env bash
# setup_assets.sh — unpack CraftPix zips from raw_assets/ into assets/
# Usage: put the 5 .zip files in raw_assets/, then: bash setup_assets.sh
set -euo pipefail

RAW="raw_assets"
OUT="assets"
TMP="$(mktemp -d)"

echo "==> extracting into temp: $TMP"
mkdir -p "$OUT"/{characters,animals,trees,bushes,tiles,objects,icons}

find_zip () { ls "$RAW"/*"$1"*.zip 2>/dev/null | head -n1 || true; }

CHAR=$(find_zip 555940)
ANIM=$(find_zip 789196)
TREE=$(find_zip 385863)
BUSH=$(find_zip 141354)
DUNG=$(find_zip 169442)

copy_glob () { # $1 = source glob (in TMP), $2 = dest dir
  shopt -s nullglob
  local files=( $1 )
  if (( ${#files[@]} )); then cp -f "${files[@]}" "$2"/ && echo "   + ${#files[@]} -> $2"; fi
  shopt -u nullglob
}

if [ -n "$CHAR" ]; then
  echo "==> character ($CHAR)"; unzip -o -q "$CHAR" -d "$TMP/char"
  copy_glob "$TMP/char/PNG/Unarmed/Without_shadow/Unarmed_*.png" "$OUT/characters"
  copy_glob "$TMP/char/PNG/Unarmed/Without_shadow/shadow_*.png"  "$OUT/characters"
  # also keep sword sheets for a placeholder harvest/chop swing
  copy_glob "$TMP/char/PNG/Sword/Without_shadow/Sword_attack_without_shadow.png" "$OUT/characters"
fi

if [ -n "$ANIM" ]; then
  echo "==> animals ($ANIM)"; unzip -o -q "$ANIM" -d "$TMP/anim"
  for a in Fox Boar Hare Deer Black_grouse; do
    mkdir -p "$OUT/animals/$a"
    copy_glob "$TMP/anim/PNG/Without_shadow/$a/*.png" "$OUT/animals/$a"
  done
fi

if [ -n "$TREE" ]; then
  echo "==> trees ($TREE)"; unzip -o -q "$TREE" -d "$TMP/tree"
  copy_glob "$TMP/tree/PNG/Assets_separately/Trees/*.png" "$OUT/trees"
  mkdir -p "$OUT/trees/shadow"
  copy_glob "$TMP/tree/PNG/Assets_separately/Trees_shadow/*.png" "$OUT/trees/shadow"
fi

if [ -n "$BUSH" ]; then
  echo "==> bushes ($BUSH)"; unzip -o -q "$BUSH" -d "$TMP/bush"
  copy_glob "$TMP/bush/PNG/Assets/*.png" "$OUT/bushes"
  mkdir -p "$OUT/bushes/shadow"
  copy_glob "$TMP/bush/PNG/Assets_shadow/*.png" "$OUT/bushes/shadow"
fi

if [ -n "$DUNG" ]; then
  echo "==> dungeon/objects ($DUNG)"; unzip -o -q "$DUNG" -d "$TMP/dung"
  copy_glob "$TMP/dung/PNG/fire_animation*.png"       "$OUT/objects"
  copy_glob "$TMP/dung/PNG/doors_lever_chest_*.png"   "$OUT/objects"
  copy_glob "$TMP/dung/PNG/Objects.png"               "$OUT/objects"
  copy_glob "$TMP/dung/PNG/Water_coasts_*.png"        "$OUT/tiles"
  copy_glob "$TMP/dung/PNG/water_*.png"               "$OUT/tiles"
  copy_glob "$TMP/dung/PNG/walls_floor.png"           "$OUT/tiles"
  copy_glob "$TMP/dung/PNG/decorative_cracks_*.png"   "$OUT/tiles"
fi

echo
echo "==> done. Now drop the 4 icon-sheet images into $OUT/icons/ manually."
echo "==> In Godot, select assets/ and set import Filter = Nearest, then Reimport."
rm -rf "$TMP"
