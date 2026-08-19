#!/usr/bin/env bash
# xbb-clean: mechanical accounting and deletion for /xbb's `clean` mode.
# Never runs unattended -- SKILL.md's `clean` mode always presents `measure`
# output to the user and asks before ever calling `delete`.
#
# Usage:
#   xbb-clean.sh measure
#   xbb-clean.sh delete
set -euo pipefail

usage() {
  echo "Usage: $0 {measure|delete}" >&2
  exit 1
}

cmd="${1:-}"
[ -n "$cmd" ] || usage

R="${TMPDIR:-${TEMP:-${TMP:-/tmp}}}"
[ -n "$R" ] || { echo "TEMP-ROOT-UNRESOLVED" >&2; exit 2; }

case "$cmd" in
  measure)
    if ! compgen -G "$R"/xbb-run-*/ > /dev/null; then
      echo "nothing to clean"
      exit 0
    fi
    du -sh "$R"/xbb-run-*/ 2>/dev/null | sort -h
    du -shc "$R"/xbb-run-*/ 2>/dev/null | tail -1
    ;;
  delete)
    if ! compgen -G "$R"/xbb-run-*/ > /dev/null; then
      echo "nothing to clean"
      exit 0
    fi
    freed=$(du -shc "$R"/xbb-run-*/ 2>/dev/null | tail -1 | awk '{print $1}')
    count=$(compgen -G "$R"/xbb-run-*/ | wc -l | tr -d ' ')
    rm -rf "$R"/xbb-run-*/
    echo "Deleted $count dir(s), freed $freed"
    ;;
  *) usage ;;
esac
