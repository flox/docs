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
# under man/ without a nav entry — so a *man* page cannot reach the site
# without also reaching llms.txt.
#
# That guarantee stops at man/. check-man-nav.sh iterates man/*.mdx only, so
# an ordinary page can still ship out of the nav and therefore out of this
# file: concepts/flox-vs-containers-faq.mdx is live and linked today and is
# in neither. Generalizing nav coverage to every .mdx outside an allowlist
# belongs in check-man-nav.sh, not here.
#
# Structure:
#   - Preamble is copied verbatim from llms.txt.header (hand-written: summary,
#     agent instructions, command surface, skills install, glossary). It sits
#     ahead of the first H2 on purpose — strict llms.txt parsers extract only
#     link lists from H2 sections, so prose under a heading gets dropped.
#   - One H2 per nav group, in nav order.
#   - Link text is the page's frontmatter `title`. The description is its
#     frontmatter `description`, falling back to the `## NAME` line for man
#     pages, which is the canonical one-liner shipped with the command. Every
#     link must carry one: a page with neither is an error, not a bare link.
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


# A block-scalar indicator (`description: >`, `|-`, …) opens a value this
# one-line parser cannot read: the text lives on the following lines. Treat it
# as absent rather than emitting the indicator itself as a description.
BLOCK_SCALAR = re.compile(r"^[>|][+-]?\d*$")


def frontmatter(text):
    """Return the YAML frontmatter block's simple key/value pairs.

    Values written as block scalars are omitted, not returned verbatim.
    """
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    fields = {}
    for line in m.group(1).splitlines():
        km = re.match(r'^([A-Za-z_-]+):\s*(.*)$', line)
        if km:
            value = km.group(2).strip().strip('"').strip("'")
            if BLOCK_SCALAR.match(value):
                continue
            fields[km.group(1)] = value
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


# The nav containers this walker descends into. Mintlify has others —
# `anchors`, `dropdowns`, `versions`, `languages` — and a nav that grew one
# would silently drop every page beneath it, shrinking the published index with
# no error, while check-man-nav.sh (which recurses every dict value) kept
# reporting `ok` against the same docs.json. Rather than guess at the section
# semantics of containers this repo does not use, walk() refuses a nav it does
# not fully understand.
CONTAINER_KEYS = ("tabs", "groups", "pages")


def walk(node, crumbs, acc):
    """Collect (section-crumbs, page-path) into `acc`, in nav order.

    Raises on a container key this walker does not handle, so a nav
    restructure fails loudly instead of publishing a shorter index.
    """
    if isinstance(node, list):
        for item in node:
            walk(item, crumbs, acc)
    elif isinstance(node, dict):
        unhandled = sorted(
            key for key, value in node.items()
            if key not in CONTAINER_KEYS and isinstance(value, (list, dict))
        )
        if unhandled:
            raise ValueError(
                "unhandled docs.json nav container(s): "
                + ", ".join(unhandled)
                + " — teach walk() how to descend them (and what they contribute "
                  "to a section title) before adding them to the nav"
            )
        if "tab" in node:
            crumbs = crumbs if node["tab"] in DROP_TABS else crumbs + [node["tab"]]
        elif "group" in node:
            crumbs = crumbs + [node["group"]]
        for key in CONTAINER_KEYS:
            if key in node:
                walk(node[key], crumbs, acc)
    elif isinstance(node, str):
        acc.append((tuple(crumbs), node))


pages = []
with open(os.path.join(docs_root, "docs.json"), encoding="utf-8") as f:
    nav = json.load(f)["navigation"]
try:
    walk(nav, [], pages)
except ValueError as exc:
    print(f"error: {exc}", file=sys.stderr)
    sys.exit(1)

# Group by section, preserving first-seen nav order.
sections, order = {}, []
for crumbs, page in pages:
    title = ": ".join(SECTION_TITLES.get(c, c) for c in crumbs)
    if title not in sections:
        sections[title] = []
        order.append(title)
    sections[title].append(page)

with open(os.path.join(docs_root, "llms.txt.header"), encoding="utf-8") as f:
    chunks = [f.read().rstrip("\n"), ""]
missing, undescribed = [], []

for title in order:
    lines = []
    for page in sections[title]:
        path = os.path.join(docs_root, page + ".mdx")
        if not os.path.exists(path):
            missing.append(page)
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read()
        fm = frontmatter(text)
        label = fm.get("title") or os.path.basename(page)
        desc = fm.get("description") or name_line(text)
        if not desc:
            undescribed.append(page)
            continue
        url = f"{BASE}/{page}.md"
        lines.append(f"- [{label}]({url}): {desc}")
    if lines:
        chunks.append(f"## {title}")
        chunks.append("")
        chunks.extend(lines)
        chunks.append("")

# Validate before writing. A failed run must not leave a truncated llms.txt
# behind: the file is committed, so a partial one can be staged by a distracted
# `git add -A` and would then pass the drift check on the next run.
if missing:
    print("error: nav references pages with no .mdx file:", file=sys.stderr)
    for page in missing:
        print(f"  {page}", file=sys.stderr)
    sys.exit(1)

# "Every link carries a description" is the reason this file exists at all —
# Mintlify's own llms.txt leaves 40 of 100 bare. Without this the property was
# an observation about today's content, not an invariant: a page added later
# with neither `description:` frontmatter nor a `## NAME` line would emit a
# bare link and pass the drift check, since the check only compares the
# committed file against a fresh run.
if undescribed:
    print("error: nav pages with no description:", file=sys.stderr)
    for page in undescribed:
        print(f"  {page}", file=sys.stderr)
    print(
        "\nAdd `description:` frontmatter (a man page can instead carry a "
        "`## NAME` line, which the sync generates).",
        file=sys.stderr,
    )
    sys.exit(1)

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(chunks).rstrip("\n") + "\n")

total = sum(len(v) for v in sections.values())
print(f"wrote {out_path}: {total} pages in {len(order)} sections, all with descriptions")
EOF
