#!/usr/bin/env bash
# push.sh <node> - upload the prepared tree (staging/) to <node>'s work directory.
#
# Uploads only what the VMS build needs (lib, src, vms, config.h) into
# <workdir>/<name>-<version with dots as underscores>, e.g. [.GREP-3_12].
# Re-pushing uploads new file versions; build.sh purges the old ones on VMS.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: push.sh <node>}
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
stage=$top/staging/$name
remote=$(echo "$name" | tr . _)
[ -d "$stage/vms" ] || { echo "push: run tools/prepare.sh first" >&2; exit 1; }

pack=$top/cache/push-$name
rm -rf "$pack"; mkdir -p "$pack/$remote"
cp -a "$stage/lib" "$stage/src" "$stage/vms" "$stage/config.h" "$pack/$remote/"
# Host build leftovers and files VMS cannot use.
find "$pack/$remote" \( -name 'Makefile*' -o -name '*.in.h' -o -name '*.o' \) -delete

echo "push: $(find "$pack/$remote" -type f | wc -l) files -> $node:[.$(echo "$remote" | tr a-z A-Z)]"
read -r _ _ HOST PORT USER WORKDIR SFTPDIR < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
# Explicit mkdir/put per path: 'put -r' into an existing directory nests a
# second copy inside it instead of updating the files.
batch=$pack/sftp.batch
{
    echo "cd $SFTPDIR"
    (cd "$pack" && find "$remote" -type d) | sed 's/^/-mkdir /'
    (cd "$pack" && find "$remote" -type f) | while read -r f; do echo "put $pack/$f $f"; done
} > "$batch"
sftp -P "$PORT" -i "${VMS_SSH_KEY:-$HOME/.ssh/vms_ed25519}" -o BatchMode=yes -b "$batch" "$USER@$HOST" \
    2>&1 >/dev/null | grep -vE '^ *Welcome to|^ *$|^remote mkdir .*: Failure$' >&2 || true
echo "push: done"
