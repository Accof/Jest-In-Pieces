#!/bin/bash
# Restore the legacy Drowned Trenches code from the archive into the live tree.
#   archive/legacy_drowned_trenches/restore.sh --dry-run   # show what would change
#   archive/legacy_drowned_trenches/restore.sh             # copy the legacy files back (asks first)
#   archive/legacy_drowned_trenches/restore.sh --shared    # also overwrite the shared files (game.gd, maze.gd...): see RESTORE.md first
#   archive/legacy_drowned_trenches/restore.sh --to DIR    # restore into another checkout (e.g. a scratch copy) instead of this one
# Run from anywhere; it works relative to its own location. Nothing is deleted.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DRY=0; SHARED=0; DEST="$ROOT"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1;;
    --shared) SHARED=1;;
    --to) shift; DEST="$1";;
    *) echo "unknown option $1"; exit 2;;
  esac; shift
done
if command -v sha256sum >/dev/null; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
(cd "$HERE" && $SUM -c SNAPSHOT.sha256 >/dev/null 2>&1) || { echo "the archive's own copies do not match SNAPSHOT.sha256: refusing to restore from a damaged archive"; exit 1; }
[ -f "$DEST/project.godot" ] || { echo "$DEST is not a Godot project root"; exit 2; }
n=0
while IFS=$'\t' read -r s o r; do
  case "$s" in \#*|"") continue;; esac
  if [ "$r" = "shared-reference" ] && [ $SHARED = 0 ]; then continue; fi
  src="$HERE/snapshot/$s"; dst="$DEST/$o"
  if cmp -s "$src" "$dst"; then continue; fi
  n=$((n+1))
  if [ $DRY = 1 ]; then echo "would restore  $o"; else mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; echo "restored  $o"; fi
done < "$HERE/files.tsv"
if [ $n = 0 ]; then echo "nothing to restore: the live files already match the legacy originals"; fi
if [ $DRY = 0 ] && [ $n -gt 0 ]; then
  echo "$n file(s) restored. Now re-import so Godot picks them up:"
  echo "   godot --headless --path \"$DEST\" --import"
  echo "then play:  godot --path \"$DEST\" res://scenes/legacy_drowned_trenches.tscn"
fi
