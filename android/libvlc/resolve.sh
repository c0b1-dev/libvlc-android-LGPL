#!/bin/bash
#
# resolve.sh — what the libvlcjni pin in engine.env stands for, read from that commit's own files.
# Prints KEY=value lines (the workflow appends them to $GITHUB_OUTPUT):
#   vlc=<the VLC commit libvlcjni tests>
#   image=<the build image libvlcjni's CI uses>
#   abis=<the ABIs to build, as a JSON list for the workflow's matrix>
#
#   android/libvlc/resolve.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/engine.env"

fail() { echo "⚠ $*" >&2; exit 1; }

raw="${LIBVLCJNI_REPO%.git}/-/raw/$LIBVLCJNI_COMMIT"

# Exactly one value each: two lines would write a broken `$GITHUB_OUTPUT` (or build with the wrong one).
one() {
  local values
  values=$(sort -u)
  [ -n "$values" ] || fail "no $1 at $LIBVLCJNI_COMMIT"
  [ "$(wc -l <<<"$values")" -eq 1 ] || fail "more than one $1 at $LIBVLCJNI_COMMIT: $(tr '\n' ' ' <<<"$values")"
  echo "$values"
}

vlc=$(curl -fsSL "$raw/buildsystem/get-vlc.sh" | sed -n 's/^VLC_TESTED_HASH=\([0-9a-f]\{40\}\)$/\1/p' \
  | one "VLC_TESTED_HASH in libvlcjni's get-vlc.sh")

image=$(curl -fsSL "$raw/buildsystem/gitlab/.gitlab-ci.yml" \
  | sed -n 's/^  image: \(registry\.videolan\.org\/vlc-debian-android:[0-9]*\)$/\1/p' \
  | one "vlc-debian-android image in libvlcjni's CI file")

abis=$(printf '"%s",' $ABIS)

echo "vlc=$vlc"
echo "image=$image"
echo "abis=[${abis%,}]"
