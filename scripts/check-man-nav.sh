#!/usr/bin/env bash
# check-man-nav.sh — verify every synced man page has a nav entry in docs.json
#
# The man-page sync (scripts/sync-man-pages.sh) writes man/*.mdx, but nav
# entries in docs.json are maintained by hand, so a newly added command can
# ship live-but-invisible: reachable by URL and search, missing from the
# sidebar (this happened with flox-run and flox-deactivate).
#
# Fails when a page under man/ is not referenced anywhere in the docs.json
# `navigation` tree, unless it is deliberately excluded via ALLOWLIST below.
# Also warns when an ALLOWLIST entry is stale (file gone, or page now in nav).
#
# Usage:
#   ./scripts/check-man-nav.sh [docs-root]   # defaults to the repo root
#
# Requires: python3 (for JSON parsing)

set -euo pipefail

# Pages deliberately excluded from the sidebar. Keep in sync with curation
# decisions — e.g. c2f6538 removed the auto-activation pages from the nav
# because concepts/auto-activation covers that material.
ALLOWLIST=(
  flox-activate-allow
  flox-activate-deny
)

docs_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
docs_json="$docs_root/docs.json"
man_dir="$docs_root/man"

[ -f "$docs_json" ] || { echo "error: docs.json not found: $docs_json" >&2; exit 1; }
[ -d "$man_dir" ] || { echo "error: man dir not found: $man_dir" >&2; exit 1; }
command -v python3 > /dev/null || { echo "error: python3 not found on PATH" >&2; exit 1; }

# Every string in the docs.json `navigation` tree. Group/tab labels come
# along too, but they can't collide with "man/<name>" page paths.
nav_pages="$(python3 - "$docs_json" <<'EOF'
import json, sys

def walk(node, out):
    if isinstance(node, dict):
        for value in node.values():
            walk(value, out)
    elif isinstance(node, list):
        for value in node:
            walk(value, out)
    elif isinstance(node, str):
        out.append(node)

with open(sys.argv[1]) as f:
    data = json.load(f)
pages = []
walk(data.get("navigation", {}), pages)
print("\n".join(pages))
EOF
)"

in_nav() { grep -Fxq "man/$1" <<< "$nav_pages"; }

allowlisted() {
  local name entry
  name="$1"
  for entry in "${ALLOWLIST[@]}"; do
    [ "$entry" = "$name" ] && return 0
  done
  return 1
}

missing=()
for page in "$man_dir"/*.mdx; do
  name="$(basename "$page" .mdx)"
  allowlisted "$name" && continue
  in_nav "$name" || missing+=("$name")
done

# Stale allowlist entries are warnings, not failures
for entry in "${ALLOWLIST[@]}"; do
  if [ ! -f "$man_dir/$entry.mdx" ]; then
    echo "warning: allowlist entry '$entry' has no man/$entry.mdx (remove it from ALLOWLIST in $0)" >&2
  elif in_nav "$entry"; then
    echo "warning: allowlist entry '$entry' is in the docs.json nav (remove it from ALLOWLIST in $0)" >&2
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "error: man pages with no docs.json nav entry:" >&2
  for name in "${missing[@]}"; do
    echo "  man/$name" >&2
  done
  echo >&2
  echo "Add each page to the \"CLI reference\" tab in docs.json (see AGENTS.md)," >&2
  echo "or add it to ALLOWLIST in $0 if it is deliberately unlisted." >&2
  exit 1
fi

echo "ok: all man pages are in the docs.json nav (${#ALLOWLIST[@]} deliberately excluded)"
