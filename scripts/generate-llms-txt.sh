#!/usr/bin/env bash
# generate-llms-txt.sh — build llms.txt from the docs.json navigation tree
#
# Committing an llms.txt at the repo root overrides the one Mintlify generates
# automatically. The generated one is a single flat alphabetical list with no
# preamble, and every man page lands in it without a description, because
# man/*.mdx carries no `description:` frontmatter.
#
# Rather than hand-maintain a curated file (which drifts the moment someone
# adds a page), this derives it from the nav. The nav is already the place
# curation happens, and check-man-nav.sh already fails PRs that add a page
# without a nav entry — so a page cannot reach the site without also reaching
# llms.txt.
#
# Structure:
#   - Preamble is copied verbatim from llms.txt.header (hand-written: summary,
#     agent instructions, command surface, skills install, glossary). It sits
#     ahead of the first H2 on purpose — strict llms.txt parsers extract only
#     link lists from H2 sections, so prose under a heading gets dropped.
#   - One H2 per nav group, in nav order.
#   - Link text is the page's frontmatter `title`. The description is its
#     frontmatter `description`, falling back to the `## NAME` line for man
#     pages, which is the canonical one-liner shipped with the command.
#
# Usage:
#   ./scripts/generate-llms-txt.sh [docs-root]   # defaults to the repo root
#
# Requires: python3

set -euo pipefail

docs_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
docs_json="$docs_root/docs.json"
header="$docs_root/llms.txt.header"
out="$docs_root/llms.txt"

[ -f "$docs_json" ] || { echo "error: docs.json not found: $docs_json" >&2; exit 1; }
[ -f "$header" ] || { echo "error: header not found: $header" >&2; exit 1; }
command -v python3 > /dev/null || { echo "error: python3 not found on PATH" >&2; exit 1; }

python3 - "$docs_root" "$out" <<'EOF'
import json, os, re, sys

docs_root, out_path = sys.argv[1], sys.argv[2]
BASE = "https://flox.dev/docs"

# The Documentation tab is the default surface; its group names stand alone.
# Other tabs prefix their groups, so "Packages" reads as "CLI reference: Packages".
DROP_TABS = {"Documentation"}

# Cosmetic section renames. Safe to extend: these only retitle a section, they
# can never drop a page, since pages still come from the nav tree.
SECTION_TITLES = {
    "Customer": "Enterprise and operations",
}


def frontmatter(text):
    """Return the YAML frontmatter block's simple key/value pairs."""
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    fields = {}
    for line in m.group(1).splitlines():
        km = re.match(r'^([A-Za-z_-]+):\s*(.*)$', line)
        if km:
            fields[km.group(1)] = km.group(2).strip().strip('"').strip("'")
    return fields


def name_line(text):
    """The `## NAME` one-liner from a man page, minus its `command - ` prefix.

    Pandoc hard-wraps these, so continuation lines are rejoined first.
    """
    m = re.search(r"^## NAME\s*\n(.*?)(?:\n\s*\n|\Z)", text, re.DOTALL | re.MULTILINE)
    if not m:
        return ""
    line = " ".join(part.strip() for part in m.group(1).strip().splitlines())
    _, sep, rest = line.partition(" - ")
    desc = (rest if sep else line).strip()
    if not desc:
        return ""
    desc = desc[0].upper() + desc[1:]
    return desc if desc[-1] in ".!?" else desc + "."


def walk(node, crumbs, acc):
    """Yield (section-crumbs, page-path) in nav order."""
    if isinstance(node, list):
        for item in node:
            walk(item, crumbs, acc)
    elif isinstance(node, dict):
        if "tab" in node:
            crumbs = crumbs if node["tab"] in DROP_TABS else crumbs + [node["tab"]]
        elif "group" in node:
            crumbs = crumbs + [node["group"]]
        for key in ("tabs", "groups", "pages"):
            if key in node:
                walk(node[key], crumbs, acc)
    elif isinstance(node, str):
        acc.append((tuple(crumbs), node))


pages = []
walk(json.load(open(os.path.join(docs_root, "docs.json")))["navigation"], [], pages)

# Group by section, preserving first-seen nav order.
sections, order = {}, []
for crumbs, page in pages:
    title = ": ".join(SECTION_TITLES.get(c, c) for c in crumbs)
    if title not in sections:
        sections[title] = []
        order.append(title)
    sections[title].append(page)

chunks = [open(os.path.join(docs_root, "llms.txt.header")).read().rstrip("\n"), ""]
missing, described = [], 0

for title in order:
    lines = []
    for page in sections[title]:
        path = os.path.join(docs_root, page + ".mdx")
        if not os.path.exists(path):
            missing.append(page)
            continue
        text = open(path).read()
        fm = frontmatter(text)
        label = fm.get("title") or os.path.basename(page)
        desc = fm.get("description") or name_line(text)
        if desc:
            described += 1
        url = f"{BASE}/{page}.md"
        lines.append(f"- [{label}]({url}): {desc}" if desc else f"- [{label}]({url})")
    if lines:
        chunks.append(f"## {title}")
        chunks.append("")
        chunks.extend(lines)
        chunks.append("")

with open(out_path, "w") as f:
    f.write("\n".join(chunks).rstrip("\n") + "\n")

total = sum(len(v) for v in sections.values()) - len(missing)
print(f"wrote {out_path}: {total} pages in {len(order)} sections, {described} with descriptions")
if missing:
    print("error: nav references pages with no .mdx file:", file=sys.stderr)
    for page in missing:
        print(f"  {page}", file=sys.stderr)
    sys.exit(1)
EOF
