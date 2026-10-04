#!/bin/bash
# Write the latest GitHub release of every port listed in site/projects.json to
# site/releases.json (or to $1). The web site reads this snapshot first and then
# asks the GitHub API directly, so a page is never staler than the last deploy.
# Needs gh (authenticated, or GH_TOKEN set) and jq.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$here/site/releases.json}
owner=${SITE_OWNER:-issinoho}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
echo '{}' >"$tmp"
for repo in $(jq -r '.[].repo' "$here/site/projects.json"); do
    if rel=$(gh api "repos/$owner/$repo/releases/latest" 2>/dev/null); then
        jq --arg repo "$repo" --argjson rel "$rel" '.[$repo] = ($rel | {
            tag_name, name, published_at, html_url,
            assets: [.assets[] | {name, size, browser_download_url}] })' \
            "$tmp" >"$tmp.new" && mv "$tmp.new" "$tmp"
    fi
done
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{generated: $now, releases: .}' "$tmp" >"$out"
echo "wrote $out ($(jq '.releases | length' "$out") releases)"
