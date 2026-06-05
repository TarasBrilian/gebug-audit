#!/usr/bin/env bash
# uninstall.sh - remove gebug-audit symlinks from ~/.claude/skills/
#
# Only removes symlinks pointing back at this repo. Real directories
# (e.g., the user copied instead of symlinked) are left alone unless
# --force is passed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"
SKILLS_DST="$HOME/.claude/skills"
FORCE="${1:-}"

skills=(gebug-brainstorm gebug-work)

for skill in "${skills[@]}"; do
  dst="$SKILLS_DST/$skill"

  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "skip: $dst not installed"
    continue
  fi

  if [ -L "$dst" ]; then
    target="$(readlink "$dst")"
    case "$target" in
      "$SKILLS_SRC/$skill")
        rm "$dst"
        echo "removed symlink: $dst"
        ;;
      *)
        echo "skip: $dst is a symlink to $target (not managed by this repo)"
        ;;
    esac
    continue
  fi

  if [ "$FORCE" = "--force" ]; then
    rm -rf "$dst"
    echo "removed directory: $dst (--force passed)"
  else
    echo "skip: $dst is a real directory, not a symlink. Re-run with --force to delete it."
  fi
done

echo
echo "Uninstalled. Restart Claude Code so the skill index drops the removed skills."
