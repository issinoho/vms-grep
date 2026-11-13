#!/bin/bash
# Write the recent GitHub releases (up to 10) of every port listed in
# site/projects.json to site/releases.json (or to $1). The web site reads this
# snapshot first and then asks the GitHub API directly, so a page is never
# staler than the last deploy. It combines each port's list itself (app.js,
# combineReleases): per architecture, the kit from the newest release that has
# one, so an Alpha-only release doesn't hide the other architectures' kits.
# Needs gh (authenticated, or GH_TOKEN set) and jq.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$here/site/releases.json}
owner=${SITE_OWNER:-issinoho}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
echo '{}' >"$tmp"
for repo in $(jq -r '.[].repo' "$here/site/projects.json"); do
    if rels=$(gh api "repos/$owner/$repo/releases?per_page=10" 2>/dev/null) &&
        [ "$(jq 'length' <<<"$rels")" -gt 0 ]; then
        jq --arg repo "$repo" --argjson rels "$rels" '.[$repo] = [$rels[] | {
            tag_name, name, published_at, html_url, draft, prerelease,
            assets: [.assets[] | {name, size, browser_download_url}] }]' \
            "$tmp" >"$tmp.new" && mv "$tmp.new" "$tmp"
    fi
done
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{generated: $now, releases: .}' "$tmp" >"$out"
echo "wrote $out ($(jq '.releases | length' "$out") releases)"
