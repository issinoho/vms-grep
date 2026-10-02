#!/usr/bin/env bash
# vms.sh - run things on the VMS build nodes listed in tools/nodes.conf.
#
#   vms.sh <node> put    <local-file>... [-- <subdir>]  upload files (to workdir or workdir/subdir)
#   vms.sh <node> putdir <local-dir> <subdir>           upload every file in a directory (flat)
#   vms.sh <node> get    <remote-relpath> <local-file>  download a file relative to the workdir
#   vms.sh <node> dcl    '<dcl command>'                run one DCL command, print its output
#   vms.sh <node> run    <local.com> [params...]        upload + run a procedure interactively
#   vms.sh <node> batch  <local.com> [params...]        upload + SUBMIT, wait for the log, print it
#
# Output from `ssh host <cmd>` is unreliable on these nodes, so everything runs
# with /OUTPUT (or a batch log) into the workdir and the log is fetched by sftp.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
conf=$here/nodes.conf
key=${VMS_SSH_KEY:-$HOME/.ssh/vms_ed25519}

usage() { sed -n '2,12p' "$0" >&2; exit 2; }
[ $# -ge 2 ] || usage
node=$1 op=$2; shift 2

read -r _ ARCH HOST PORT USER WORKDIR SFTPDIR < <(awk -v n="$node" '$1==n' "$conf") || true
[ -n "${HOST:-}" ] || { echo "vms.sh: unknown node '$node' (see $conf)" >&2; exit 2; }

ssh_opts=(-i "$key" -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30)

sftp_batch() {  # sftp_batch <commands...>
    printf '%s\n' "$@" | sftp -P "$PORT" "${ssh_opts[@]}" -b - "$USER@$HOST" 2>&1 >/dev/null |
        { grep -vE '^ *Welcome to|^ *$' >&2 || true; }
    return "${PIPESTATUS[1]}"
}

# DISK$USER:[USERNAME.VMS_GREP] + sub/dir -> DISK$USER:[USERNAME.VMS_GREP.SUB.DIR]
vms_dir() {
    local sub=${1:-}
    if [ -z "$sub" ]; then echo "$WORKDIR"; return; fi
    echo "${WORKDIR%]}.$(echo "$sub" | tr '/' '.' | tr '[:lower:]' '[:upper:]')]"
}

# Run DCL command(s) with output captured to a log, then print the log.
dcl_logged() {
    local tag=vmsrun_$$_$RANDOM
    local com=$(mktemp) out=$(mktemp)
    { echo '$ set noon'; echo "\$ set default $WORKDIR"; printf '%s\n' "$@"; } > "$com"
    sftp_batch "cd $SFTPDIR" "put $com $tag.com"
    ssh -p "$PORT" "${ssh_opts[@]}" "$USER@$HOST" \
        "@${WORKDIR}${tag}.COM/OUTPUT=${WORKDIR}${tag}.LOG" >/dev/null 2>&1 || true
    sftp_batch "cd $SFTPDIR" "get $tag.LOG $out" "rm $tag.com" "rm $tag.LOG" || true
    tr -d '\r' < "$out"
    rm -f "$com" "$out"
}

case $op in
put)
    files=() sub=
    while [ $# -gt 0 ]; do
        if [ "$1" = -- ]; then sub=$2; break; fi
        files+=("$1"); shift
    done
    cmds=("cd $SFTPDIR")
    [ -n "$sub" ] && cmds+=("-mkdir $sub" "cd $sub")
    for f in "${files[@]}"; do cmds+=("put $f"); done
    sftp_batch "${cmds[@]}"
    ;;
putdir)
    [ $# -eq 2 ] || usage
    sftp_batch "cd $SFTPDIR" "-mkdir $2" "cd $2" "lcd $1" "mput *"
    ;;
get)
    [ $# -eq 2 ] || usage
    sftp_batch "cd $SFTPDIR" "get $1 $2"
    ;;
dcl)
    [ $# -ge 1 ] || usage
    cmds=()
    for c in "$@"; do cmds+=("\$ $c"); done
    dcl_logged "${cmds[@]}"
    ;;
run)
    [ $# -ge 1 ] || usage
    com=$1; shift
    sftp_batch "cd $SFTPDIR" "put $com"
    params=""
    for p in "$@"; do params+=" \"$p\""; done
    dcl_logged "\$ @${WORKDIR}$(basename "$com")$params"
    ;;
batch)
    [ $# -ge 1 ] || usage
    com=$1; shift
    name=$(basename "$com" .com)
    log=${name}_batch.log
    sftp_batch "cd $SFTPDIR" "put $com" "-rm $log"
    plist=""
    for p in "$@"; do plist+="${plist:+,}\"$p\""; done
    dcl_logged "\$ submit/noprint/log_file=${WORKDIR}${log}${plist:+/parameters=($plist)} ${WORKDIR}$(basename "$com")" >&2
    # The log is held open by the batch job until it ends; sftp cannot read it until then.
    out=$(mktemp)
    for _ in $(seq 1 ${VMS_BATCH_POLLS:-360}); do
        if sftp_batch "cd $SFTPDIR" "get $log $out" 2>/dev/null && [ -s "$out" ]; then
            tr -d '\r' < "$out"; rm -f "$out"; exit 0
        fi
        sleep ${VMS_BATCH_POLL_SECS:-20}
    done
    echo "vms.sh: timed out waiting for batch log $log" >&2; rm -f "$out"; exit 1
    ;;
*) usage ;;
esac
