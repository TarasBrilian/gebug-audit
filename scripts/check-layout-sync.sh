#!/usr/bin/env bash
# check-layout-sync.sh
#
# CLAUDE.md "Changing the output layout" lists 9 files that must all be
# updated together when the gebug-audit output tree changes. This script
# guards against the most common drift mode: subtree names diverging
# (e.g., one file renamed `finding/` to `findings/` while the rest kept
# the singular). It scans every layout-bearing file for known-wrong
# variants of the 5 canonical subtree names.
#
# What this does NOT cover:
#   - Adding a brand new subtree (the SUBTREES list below is the source
#     of truth; update it when the layout grows).
#   - Capitalization or path-prefix drift inside one file.
#
# Run from the repo root or anywhere inside the repo:
#   ./scripts/check-layout-sync.sh
#
# Exits 0 on clean tree, 1 on drift.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# The 9 files per CLAUDE.md "Changing the output layout".
FILES=(
  "skills/gebug-brainstorm/SKILL.md"
  "skills/gebug-brainstorm/references/brainstorm-pipeline.md"
  "skills/gebug-brainstorm/README.md"
  "skills/gebug-work/SKILL.md"
  "skills/gebug-work/references/work-pipeline.md"
  "skills/gebug-work/agents/vuln-hunter.md"
  "skills/gebug-work/agents/exploit-writer.md"
  "skills/gebug-work/README.md"
  "README.md"
)

# Known-wrong variants of the 5 canonical subtree names
# (definition, finding, fuzzing, exploit, report). If you rename one,
# add the OLD name to WRONG_VARIANTS for at least one release so stale
# references fail loudly.
# Format: "wrong_pattern  canonical_name" (tab-separated).
WRONG_VARIANTS=(
  $'findings/\tfinding/'
  $'exploits/\texploit/'
  $'reports/\treport/'
  $'fuzz/\tfuzzing/'
  $'definitions/\tdefinition/'
)

drift=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "MISSING FILE: $f"
    drift=1
    continue
  fi
  for entry in "${WRONG_VARIANTS[@]}"; do
    wrong="${entry%%$'\t'*}"
    canon="${entry##*$'\t'}"
    if grep -q -F "$wrong" "$f"; then
      echo "DRIFT: $f contains $wrong (canonical is $canon)"
      drift=1
    fi
  done
done

if [ "$drift" -eq 0 ]; then
  echo "PASS: no layout drift detected across ${#FILES[@]} files."
  exit 0
fi

echo ""
echo "Rename back to the canonical name in every flagged file, OR if"
echo "you are intentionally renaming, update SUBTREES + WRONG_VARIANTS"
echo "in this script + CLAUDE.md tree examples in the same commit."
exit 1
