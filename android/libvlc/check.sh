#!/bin/bash
#
# check.sh — the rules Android's libVLC package must pass (design D11, task 6.3). The workflow
# runs it on every build; the Android release check (task 8.7) will run it on the package it ships.
#
#   android/libvlc/check.sh <libvlc.aar>
#
# Exits 1 at the first broken rule:
#   1. every ABI in engine.env has the libraries engine.env lists (LIBS: libvlc.so, libvlcjni.so,
#      libc++_shared.so) — and the package nothing else native: no other ABI, no other file (what
#      this script does not know, it cannot check);
#   2. the arm64-v8a libraries are aligned to 16 KB pages (Google Play requires it of 64-bit
#      code for Android 15+);
#   3. libvlc.so is the GPL-free engine, and no library shipped with it carries zvbi, a GPL VLC
#      module or yadif (the same rule as Apple's, Scripts/check-engine-gpl-free.sh); nor does the
#      package carry VLC's Lua scripts (mostly GPL-2+, and only the GPL lua module reads them);
#   4. libvlc.so carries our VLC fix (patches/vlc/9001): it loads ASurfaceTransaction_reparent;
#   5. libvlc.so carries the app's proxy (patches/vlc/9003): it reads the app's Java property
#      (the name EngineProxy.PROPERTY in the core; EngineProxyTest holds the three together);
#   6. libvlc.so carries the display's close fix (patches/vlc/9004): its time-out message;
#   7. libvlc.so carries the adaptive stop fix (patches/vlc/9005): its debug line;
#   8. libvlc.so carries the decoder's missing-window fix (patches/vlc/9006): its debug line;
#   9. libvlc.so carries the decoder's GPU-readable pictures (patches/vlc/9008): its debug line;
#  10. every library carries its symbol table (task 8.6): the app's build strips it from what ships
#      and puts it into the bundle, so Play Console names the functions in a native crash; locally,
#      ndk-stack reads it from this package;
#  11. the package carries the licences of the code built into libvlc.so, its contribs (licenses/, with
#      FFmpeg's and GnuTLS's at least; build.sh's collect_licences): the app's licences page shows them.
# Needs `readelf` (binutils on Linux; on a Mac: READELF=<the NDK's llvm-readelf>).
# Held by check-test.sh.

set -euo pipefail
shopt -s nullglob   # no jni folder: the per-ABI loop says what is missing

here=$(cd "$(dirname "$0")" && pwd)
. "$here/engine.env"

fail() { echo "  ⚠ $*"; exit 1; }

[ $# -eq 1 ] || { echo "usage: $0 <libvlc.aar>"; exit 2; }
[ -f "$1" ] || fail "not found: $1"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$1" -d "$work"

[ ! -e "$work/assets/lua" ] \
  || fail "the package carries VLC's Lua scripts (assets/lua: mostly GPL-2+, read only by the GPL lua module; patches/libvlcjni/0002 leaves them out)."

[ -f "$work/licenses/MISSING" ] && [ -d "$work/licenses/ffmpeg" ] && [ -d "$work/licenses/gnutls" ] \
  || fail "the package carries no licences of the code built into libvlc.so (licenses/ with FFmpeg's and GnuTLS's: build.sh collect_licences)."
echo "  ✓ the licences of $(find "$work/licenses" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') contribs (licenses/)"

for dir in "$work"/jni/*/; do
  abi=$(basename "$dir")
  case " $ABIS " in *" $abi "*) ;; *) fail "an ABI engine.env does not list: $abi." ;; esac
  for file in "$dir"*; do
    case " $LIBS " in *" $(basename "$file") "*) ;; *) fail "$abi: an unexpected file, $(basename "$file")." ;; esac
  done
done

for abi in $ABIS; do
  dir="$work/jni/$abi"
  for lib in $LIBS; do
    [ -f "$dir/$lib" ] || fail "$abi: $lib missing."
  done
  echo "  ✓ $abi: $LIBS (libvlc.so $(( $(wc -c < "$dir/libvlc.so") / 1048576 )) MB)"

  if [ "$abi" = arm64-v8a ]; then
    for lib in "$dir"/*.so; do
      aligns=$(${READELF:-readelf} -lW "$lib" | awk '$1 == "LOAD" { print $NF }')
      [ -n "$aligns" ] || fail "$abi: no LOAD segments read from $(basename "$lib")."
      for align in $aligns; do
        [ $((align)) -ge 16384 ] || fail "$abi: $(basename "$lib") has a LOAD segment aligned to $align, not 16 KB."
      done
    done
    echo "  ✓ $abi: every library aligned to 16 KB pages"
  fi

  # The engine first: its configure line is read from the first binary.
  shipped=("$dir/libvlc.so")
  for lib in $LIBS; do [ "$lib" = libvlc.so ] || shipped+=("$dir/$lib"); done
  "$here/../../Scripts/check-engine-gpl-free.sh" "${shipped[@]}"

  grep -qaF ASurfaceTransaction_reparent "$dir/libvlc.so" \
    || fail "$abi: libvlc.so lacks our display fix (patches/vlc/9001: no ASurfaceTransaction_reparent)."
  echo "  ✓ $abi: our display fix (patches/vlc/9001)"

  grep -qaF ch.codebits.cobiplayer.proxy "$dir/libvlc.so" \
    || fail "$abi: libvlc.so lacks the app's proxy (patches/vlc/9003: no ch.codebits.cobiplayer.proxy) — the own connection's streams would go direct."
  echo "  ✓ $abi: the app's proxy (patches/vlc/9003)"

  grep -qaF "still in a surface transaction" "$dir/libvlc.so" \
    || fail "$abi: libvlc.so lacks the display's close fix (patches/vlc/9004) — the player's close can crash."
  echo "  ✓ $abi: the display's close fix (patches/vlc/9004)"

  grep -qaF "ending the downloads in progress" "$dir/libvlc.so" \
    || fail "$abi: libvlc.so lacks the adaptive stop fix (patches/vlc/9005) — an HLS stop can hang."
  echo "  ✓ $abi: the adaptive stop fix (patches/vlc/9005)"

  grep -qaF "no surface: the video context goes before the decoder used it" "$dir/libvlc.so" \
    || fail "$abi: libvlc.so lacks the decoder's missing-window fix (patches/vlc/9006) — closing the player can crash on Android 9."
  echo "  ✓ $abi: the decoder's missing-window fix (patches/vlc/9006)"

  grep -qaF "AImageReader: pictures the GPU can read too" "$dir/libvlc.so" \
    || fail "$abi: libvlc.so lacks the decoder's GPU-readable pictures (patches/vlc/9008) — picture-in-picture and rotations show black."
  echo "  ✓ $abi: the decoder's GPU-readable pictures (patches/vlc/9008)"

  for lib in $LIBS; do
    # Read whole first: `grep -q` in a pipe can end readelf early, and pipefail would then refuse.
    sections=$(${READELF:-readelf} -SW "$dir/$lib")
    grep -qw SYMTAB <<<"$sections" \
      || fail "$abi: $lib carries no symbol table (stripped) — a crash inside it would show bare addresses in Play Console (build.sh keeps it, task 8.6)."
  done
  echo "  ✓ $abi: every library with its symbol table (function names in crash traces)"
done
