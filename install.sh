#!/usr/bin/env bash
# install.sh - symlink gebug-audit skills into ~/.claude/skills/
#
# Re-runnable. Replaces existing symlinks. Refuses to overwrite real
# (non-symlink) directories without --force.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"
SKILLS_DST="$HOME/.claude/skills"
FORCE="${1:-}"

if [ ! -d "$SKILLS_SRC" ]; then
  echo "FATAL: $SKILLS_SRC does not exist. Are you running this from the repo root?" >&2
  exit 1
fi

mkdir -p "$SKILLS_DST"

skills=(gebug-brainstorm gebug-work)

for skill in "${skills[@]}"; do
  src="$SKILLS_SRC/$skill"
  dst="$SKILLS_DST/$skill"

  if [ ! -d "$src" ]; then
    echo "SKIP: $src missing" >&2
    continue
  fi

  if [ -L "$dst" ]; then
    echo "REPLACING symlink: $dst"
    rm "$dst"
  elif [ -e "$dst" ]; then
    if [ "$FORCE" != "--force" ]; then
      echo "FATAL: $dst exists and is not a symlink. Re-run with --force to replace it (will be deleted)." >&2
      exit 2
    fi
    echo "REPLACING directory: $dst (--force passed)"
    rm -rf "$dst"
  fi

  ln -s "$src" "$dst"
  echo "linked: $dst -> $src"
done

echo
echo "Installed. Restart Claude Code (or start a new session) so the skill index picks up the new skills."
echo
echo "Try:"
echo "  /gebug-brainstorm"
