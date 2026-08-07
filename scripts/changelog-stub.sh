#!/usr/bin/env bash
# Insert a pre-filled <Update> stub for a new release into changelog.mdx.
#
# Usage: changelog-stub.sh <owner/repo> <tag> <release-name> <release-url> <YYYY-MM-DD>
#
# The stub is inserted in date order (the page runs newest-first), so entries
# land correctly even when several stub PRs merge out of publish order. Each
# stub is followed by a {/* changelog-id: owner/repo@tag */} comment that the
# changelog-stubs workflow greps to avoid opening duplicate PRs for the same
# release.
#
# Requires: python3 (same as scripts/check-man-nav.sh)

set -euo pipefail

repo="${1:?owner/repo required}"
tag="${2:?tag required}"
name="${3:-$tag}"
url="${4:?release url required}"
date="${5:?date (YYYY-MM-DD) required}"

# Tags are interpolated into MDX attributes, headings, and markdown links;
# refuse characters that would break the page (or smuggle JSX expressions).
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "error: tag '$tag' contains characters unsafe for MDX interpolation" >&2
  exit 1
}

page="changelog.mdx"

[[ -f "$page" ]] || { echo "error: $page not found (run from the repo root)" >&2; exit 1; }
grep -qF '{/* changelog:insert */}' "$page" || {
  echo "error: marker {/* changelog:insert */} missing from $page" >&2; exit 1
}

# Human-facing product name for the entry, keyed off the source repo. Keep in
# sync with the tags already used in changelog.mdx.
case "$repo" in
  flox/flox)         product="Flox CLI" ;;
  flox/floxhub)      product="FloxHub" ;;
  flox/floxenvs)     product="Example environments" ;;
  flox/flox-plugins) product="Flox plugins" ;;
  flox/flox-skills)  product="Flox skills" ;;
  flox/flox-vscode)  product="VS Code extension" ;;
  *)                 product="$repo" ;;
esac

REPO="$repo" TAG="$tag" NAME="$name" URL="$url" DATE="$date" PRODUCT="$product" \
python3 - "$page" <<'PY'
import os, re, sys

page = sys.argv[1]
repo, tag, name = os.environ["REPO"], os.environ["TAG"], os.environ["NAME"]
url, date, product = os.environ["URL"], os.environ["DATE"], os.environ["PRODUCT"]

MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]
year, month, day = (int(p) for p in date.split("-"))
label = f"{MONTHS[month - 1]} {day}, {year}"

def label_to_iso(lbl):
    m = re.fullmatch(r"([A-Z][a-z]+) (\d{1,2}), (\d{4})", lbl.strip())
    if not m or m.group(1) not in MONTHS:
        return None
    return f"{int(m.group(3)):04d}-{MONTHS.index(m.group(1)) + 1:02d}-{int(m.group(2)):02d}"

content = open(page).read()
if not content.endswith("\n"):
    content += "\n"

updates = [(m.start(), label_to_iso(m.group(1)))
           for m in re.finditer(r'<Update label="([^"]+)"', content)]

# A same-date entry can't be auto-merged (its description/tags belong to a
# different release), so flag it for the human editor instead.
note = ""
if any(iso == date for _, iso in updates):
    note = ("\n\n  _Note: another entry shares this date — consider merging"
            "\n  this section into it and combining tags._")
    print(f"warning: an entry dated {date} already exists; "
          "the draft asks the editor to merge by hand", file=sys.stderr)

# The changelog-id marker sits AFTER the closing tag, not inside the body:
# Mintlify's RSS generator renders MDX comments inside an <Update> as literal
# text in the feed item, while content between entries stays out of the feed.
stub = f"""<Update label="{label}" description="{tag}" tags={{["{product}"]}}>
  ## {product} {tag}

  _Draft: summarize what changed in [{name}]({url}), leading with what it lets
  users do rather than what was merged._{note}
</Update>
{{/* changelog-id: {repo}@{tag} */}}
"""

# Newest-first: insert before the first strictly-older entry; append after
# the last entry when this one is the oldest; fall back to the insert marker
# on an empty page.
insert_at = next((pos for pos, iso in updates if iso is not None and iso < date), None)
if insert_at is not None:
    content = content[:insert_at] + stub + "\n" + content[insert_at:]
elif updates:
    content = content + "\n" + stub
else:
    marker = "{/* changelog:insert */}"
    content = content.replace(marker, marker + "\n\n" + stub.rstrip("\n"), 1)

open(page, "w").write(content)
print(f"Inserted stub for {repo}@{tag} into {page}")
PY
