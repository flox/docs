#!/usr/bin/env bash
# sync-man-pages.sh — sync man pages from flox/flox (source of truth) to flox/docs
#
# Converts the pandoc man-page sources in <flox-repo>/cli/flox/doc/*.md into
# Mintlify .mdx pages in <docs-man-dir>, expanding shared ./include snippets.
#
# Usage:
#   ./sync-man-pages.sh <flox-repo-path> <docs-man-dir>
# Example:
#   ./sync-man-pages.sh ~/work/flox ~/work/docs/man
#
# Requires: pandoc >= 2.12 (e.g. `flox install pandoc`)

set -euo pipefail

sync_man_pages() {
  local flox_src_dir="${1?usage: sync-man-pages.sh <flox-repo-path> <docs-man-dir>}"
  local docs_man_pages_dir="${2?usage: sync-man-pages.sh <flox-repo-path> <docs-man-dir>}"

  local src_doc_dir="$flox_src_dir/cli/flox/doc"
  local lua_filter="$flox_src_dir/pkgs/flox-manpages/pandoc-filters/include-files.lua"

  [ -d "$src_doc_dir" ] || { echo "error: man page source dir not found: $src_doc_dir" >&2; return 1; }
  [ -f "$lua_filter" ] || { echo "error: pandoc include filter not found: $lua_filter" >&2; return 1; }
  command -v pandoc > /dev/null || { echo "error: pandoc not found on PATH" >&2; return 1; }

  # Clean the output dir so pages deleted upstream don't linger
  mkdir -p "$docs_man_pages_dir"
  rm -f "$docs_man_pages_dir"/*.mdx

  local page name title out
  for page in "$src_doc_dir"/*.md; do
    name="$(basename "$page" .md)"
    out="$docs_man_pages_dir/$name.mdx"

    # Page title: 'flox-services-start' -> 'flox services start';
    # file-format pages (manifest.toml, nix-builds.toml) keep their literal name
    case "$name" in
      *.toml) title="$name" ;;
      *)      title="${name//-/ }" ;;
    esac

    {
      printf -- '---\ntitle: "%s"\n---\n\n' "$title"
      # - include-files.lua expands the shared ./include/*.md snippets
      # - --shift-heading-level-by=1 demotes '# NAME' -> '## NAME'
      #   (the page title comes from frontmatter in Mintlify)
      ( cd "$src_doc_dir" &&
          pandoc --from markdown --to gfm \
            --lua-filter "$lua_filter" \
            --shift-heading-level-by=1 \
            "./$name.md" ) |
        # Rewrite cross-references: (./flox-push.md) -> (/man/flox-push)
        sed -E -e 's|\(\./([A-Za-z0-9._-]+)\.md\)|(/man/\1)|g' \
          -e 's|\[`([A-Za-z0-9._-]+)\([0-9]\)`\]|[`\1`]|g' \
          -e 's|^``` ([A-Za-z0-9_+-]+)$|```\1|' |
        # Drop pandoc's '<!-- -->' block separators (MDX cannot parse HTML
        # comments) along with the blank line that follows each one
        awk '{
          if ($0 == "<!-- -->") { skip_blank = 1; next }
          if (skip_blank && $0 == "") { skip_blank = 0; next }
          skip_blank = 0; print
        }'
    } > "$out"

    echo "  $name.md -> $out"
  done

  # Warn about constructs Mintlify/MDX may not render. Indented lines that
  # are list-item continuations are fine; indented CODE (from an untagged
  # source fence) is not. We can't reliably tell them apart here, so this is
  # informational only — `mint broken-links` / `mint dev` is the real check.
  local suspect
  suspect="$(grep -rln '^    [^ ]' "$docs_man_pages_dir"/*.mdx || true)"
  if [ -n "$suspect" ]; then
    echo
    echo "note: 4-space-indented lines found in the pages below. If these are" >&2
    echo "list continuations they're fine; if they're code blocks, add a" >&2
    echo "language tag (\`\`\`text, \`\`\`bash, ...) to the source fence." >&2
    echo "Verify rendering with 'mint dev' or 'mint broken-links'." >&2
    echo "$suspect" | sed -e "s|$docs_man_pages_dir/||" -e 's|^|  |' >&2
  fi

  echo
  echo "synced $(find "$docs_man_pages_dir" -name '*.mdx' | wc -l | tr -d ' ') pages to $docs_man_pages_dir"
}

sync_man_pages "$@"
