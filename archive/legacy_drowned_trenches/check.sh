#!/bin/bash
# Verify the legacy Drowned Trenches archive and, optionally, the live tree.
#   archive/legacy_drowned_trenches/check.sh            # the archive's own copies are intact
#   archive/legacy_drowned_trenches/check.sh --live     # ...and the live tree still matches the legacy originals (code and art)
# Run from the project root (where project.godot is). Needs sha256sum or shasum.
set -u
cd "$(dirname "$0")/../.." || exit 2
A=archive/legacy_drowned_trenches
if command -v sha256sum >/dev/null; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
echo "== archive copies (SNAPSHOT.sha256)"
if (cd $A && $SUM -c SNAPSHOT.sha256 >/dev/null 2>&1); then
  echo "   ok: $(grep -c . $A/SNAPSHOT.sha256) files intact"
else
  (cd $A && $SUM -c SNAPSHOT.sha256 2>&1 | grep -v ': OK$' | sed 's/^/   /')
  echo "   FAILED: the archive itself has changed"; exit 1
fi
if [ "${1:-}" = "--live" ]; then
  echo "== live tree against the legacy originals (ORIGINALS.sha256)"
  out=$($SUM -c $A/ORIGINALS.sha256 2>&1 | grep -v ': OK$')
  if [ -z "$out" ]; then
    echo "   ok: every legacy file (code and art) in the live tree is byte-identical to the archived original"
  else
    echo "$out" | sed 's/^/   /'
    echo "   The live tree differs from the legacy originals (expected once Operation Drowned Front touches these files)."
    echo "   RESTORE.md says how to bring the originals back."
    exit 3
  fi
fi
