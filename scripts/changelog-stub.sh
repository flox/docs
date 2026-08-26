#!/usr/bin/env bash
# Insert a pre-filled <Update> stub for a new release into the changelog.
#
# Usage: changelog-stub.sh <owner/repo> <tag> <release-name> <release-url> <YYYY-MM-DD>
#
# Layout: changelog.mdx is the CURRENT year's page — the stable /changelog
# URL and the perpetual RSS feed at /changelog/rss.xml, which always carries
# the newest entries so subscribers never resubscribe. Past years live at
# changelog/<year>.mdx. The page's frontmatter title names its year, which
# is what the left sidebar shows.
#
# Routing by release date:
#   - current year          -> insert into changelog.mdx
#   - older year            -> insert into changelog/<year>.mdx (created and
#                              registered in docs.json if missing)
#   - newer year (rollover) -> archive changelog.mdx to changelog/<year>.mdx,
#                              register the archive, and reset changelog.mdx
#                              for the new year. The stub is NOT inserted —
#                              rollover ships as its own mechanical PR so
#                              that concurrent new-year releases produce
#                              identical rollovers instead of conflicting
#                              ones; rerun after it lands to stub the
#                              release.
#
# Stubs are inserted in date order (pages run newest-first), so entries land
# correctly even when several stub PRs merge out of publish order. Each stub
# is followed by a {/* changelog-id: owner/repo@tag */} comment that the
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

# A malformed date would silently corrupt docs.json (the year names archive
# pages and their nav entries).
[[ "$date" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || {
  echo "error: date '$date' is not YYYY-MM-DD" >&2
  exit 1
}

[[ -f changelog.mdx ]] || { echo "error: changelog.mdx not found (run from the repo root)" >&2; exit 1; }

# Human-facing product name for the entry's heading, keyed off the source
# repo.
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
python3 - <<'PY'
import os, re, sys

repo, tag, name = os.environ["REPO"], os.environ["TAG"], os.environ["NAME"]
url, date, product = os.environ["URL"], os.environ["DATE"], os.environ["PRODUCT"]

MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]
year, month, day = (int(p) for p in date.split("-"))
# Labels omit the year — the page itself is the year (it appears in the
# title and left sidebar, so repeating it in every TOC entry is noise).
label = f"{MONTHS[month - 1]} {day}"

MARKER = "{/* changelog:insert */}"

def write(path, data):
    # Atomic: a killed run never leaves a truncated page behind.
    tmp = path + ".tmp"
    open(tmp, "w").write(data)
    os.replace(tmp, path)

def page_template(y):
    return f"""---
title: "{y}"
description: "What's new across the Flox CLI, FloxHub, and extensions"
rss: true
---

New releases, improvements, and fixes across Flox, in reverse-chronological
order. Subscribe to the [RSS feed](/changelog/rss.xml) to follow along.

{MARKER}
"""

def current_page_year():
    m = re.search(r'^title: "(\d{4})"', open("changelog.mdx").read(), re.M)
    if not m:
        print('error: changelog.mdx frontmatter has no title: "<year>"', file=sys.stderr)
        sys.exit(1)
    return int(m.group(1))

def register_archive(y):
    """Idempotently add changelog/<y> to the Changelog tab, archives sorted
    newest first after the stable "changelog" entry. Surgical string edits
    preserve docs.json formatting."""
    dj = open("docs.json").read()
    if f'"changelog/{y}"' in dj:
        return
    m = re.search(
        r'("tab": "Changelog",\s*\n\s*"pages": \[\n)((?:\s*"changelog(?:/\d{4})?",?\n)+)(\s*\])',
        dj)
    if not m:
        print("error: could not find the Changelog tab pages array in docs.json",
              file=sys.stderr)
        sys.exit(1)
    indent = re.match(r"\s*", m.group(2)).group(0)
    archives = sorted(set(re.findall(r'"changelog/(\d{4})"', m.group(2))) | {str(y)},
                      reverse=True)
    entries = f'{indent}"changelog",\n' if re.search(r'"changelog",?\n', m.group(2)) else ""
    entries += ",\n".join(f'{indent}"changelog/{a}"' for a in archives) + "\n"
    dj = dj[:m.start(2)] + entries + dj[m.end(2):]
    write("docs.json", dj)
    print(f"registered changelog/{y} in docs.json")

def valid_archive(path, y):
    if not os.path.exists(path):
        return False
    c = open(path).read()
    return MARKER in c and re.search(rf'^title: "{y}"$', c, re.M)

page_year = current_page_year()

# Heal: any archive present on disk is registered, whatever run or human
# created it.
import glob
for f in sorted(glob.glob("changelog/[0-9][0-9][0-9][0-9].mdx")):
    register_archive(int(re.search(r"(\d{4})\.mdx$", f).group(1)))

if year == page_year:
    page = "changelog.mdx"
elif year < page_year:
    # Backfill into an archive page, creating and registering it if needed.
    page = f"changelog/{year}.mdx"
    if not os.path.exists(page):
        write(page, page_template(year))
        print(f"created {page}")
    register_archive(year)
else:
    # Year rollover: archive the current page verbatim (its title already
    # names its year and its intro already links the stable feed), then
    # reset changelog.mdx for the new year. An existing archive is trusted
    # only if it looks complete (marker + matching title), so a run killed
    # mid-write is repaired, and the reset below never runs before a valid
    # archive exists.
    archive = f"changelog/{page_year}.mdx"
    if not valid_archive(archive, page_year):
        write(archive, open("changelog.mdx").read())
        print(f"archived {page_year} entries to {archive}")
    register_archive(page_year)
    write("changelog.mdx", page_template(year))
    print(f"reset changelog.mdx for {year}")
    print(f"rollover prepared for {year}; the release stub is deferred — "
          "run again once the rollover lands")
    sys.exit(0)

content = open(page).read()
if not content.endswith("\n"):
    content += "\n"
if MARKER not in content:
    print(f"error: marker {MARKER} missing from {page}", file=sys.stderr)
    sys.exit(1)

def label_to_iso(lbl, default_year):
    # "August 11" (year implied by the page) or "January 12, 2027" (explicit).
    m = re.fullmatch(r"([A-Z][a-z]+) (\d{1,2})(?:, (\d{4}))?", lbl.strip())
    if not m or m.group(1) not in MONTHS:
        return None
    y = int(m.group(3)) if m.group(3) else default_year
    return f"{y:04d}-{MONTHS.index(m.group(1)) + 1:02d}-{int(m.group(2)):02d}"

updates = [(m.start(), label_to_iso(m.group(1), year))
           for m in re.finditer(r'<Update label="([^"]+)"', content)]

# A same-date entry can't be auto-merged (its description belongs to a
# different release), so flag it for the human editor instead.
note = ""
if any(iso == date for _, iso in updates):
    note = ("\n\n  _Note: another entry shares this date — consider merging"
            "\n  this section into it._")
    print(f"warning: an entry dated {date} already exists; "
          "the draft asks the editor to merge by hand", file=sys.stderr)

# The changelog-id marker sits AFTER the closing tag, not inside the body:
# Mintlify's RSS generator renders MDX comments inside an <Update> as literal
# text in the feed item, while content between entries stays out of the feed.
stub = f"""<Update label="{label}" description="{tag}">
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
    content = content.replace(MARKER, MARKER + "\n\n" + stub.rstrip("\n"), 1)

write(page, content)
print(f"Inserted stub for {repo}@{tag} into {page}")
PY
