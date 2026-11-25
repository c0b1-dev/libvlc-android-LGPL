#!/bin/bash
#
# build.sh — builds libVLC 4 for Android, LGPL only, inside VideoLAN's build image (resolve.sh
# names it). The workflow .github/workflows/android-libvlc.yml runs it; it needs Linux, the NDK
# and the SDK of that image, and a few hours per ABI.
#
#   android/libvlc/build.sh natives <abi>   → out/libs/<abi>/*.so and out/modules-<abi>.txt
#   android/libvlc/build.sh aar             → out/libvlc.aar (needs out/libs/<abi> of every ABI)
#
# What it adds to VideoLAN's own build (libvlcjni's compile-libvlc.sh):
#   - `--license l`: LGPLv3 contribs (the LGPLv2.1 option has no TLS, so no https);
#   - zvbi out (GPL-2+): libvlcjni enables it, and VLC's LGPL switch does not keep it out;
#   - VLC's own GPL-2+ code out, which that switch does not reach either: its GPL modules and Lua
#     (patches/libvlcjni/0002, which also keeps VLC's Lua scripts out of the package) and FFmpeg's
#     yadif inside the deinterlace plugin (patches/vlc/9007). check.sh refuses a package with any;
#   - our fixes to libvlcjni (patches/libvlcjni/) and to VLC (patches/vlc/), each with its
#     reason in its header;
#   - libvlc.so and libvlcjni.so with their symbol table, for crash traces (see natives());
#   - the licences of the code built into libvlc.so, in the package's licenses/ (collect_licences);
#   - the checks that nothing of zvbi was built and that the VLC has the MP4 seek fix.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/engine.env"
work="$here/.build"
out="$here/out"

fail() { echo "⚠ $*" >&2; exit 1; }

# The VLC commit that fixed seeking in MP4 files (Apple's engine carries it as patch 0006).
MP4_SEEK_FIX=ae06c7155afa

# get-vlc.sh applies libvlcjni's patches with `git am`, which needs an identity. Set here, not
# in a git config, so a run outside the build image leaves the user's config alone.
export GIT_AUTHOR_NAME=build GIT_AUTHOR_EMAIL=build@localhost
export GIT_COMMITTER_NAME=build GIT_COMMITTER_EMAIL=build@localhost

# libvlcjni at the pin, and in it the VLC it is tested with, with its Android patches.
fetch_sources() {
  rm -rf "$work"
  mkdir -p "$work" "$out"
  # VideoLAN's GitLab does not serve a bare commit: clone the branch, then check the pin out.
  git clone --quiet --branch master --single-branch "$LIBVLCJNI_REPO" "$work/libvlcjni"
  git -C "$work/libvlcjni" checkout --quiet "$LIBVLCJNI_COMMIT"
  local patch
  for patch in "$here"/patches/libvlcjni/*.patch; do
    git -C "$work/libvlcjni" apply "$patch" \
      || fail "$(basename "$patch") no longer applies to libvlcjni $LIBVLCJNI_COMMIT — read it: the fix may be upstream."
  done
  # Ours to VLC go with libvlcjni's own: get-vlc.sh applies every libvlc/patches/*.patch in name
  # order with `git am --message-id` (ours are 9xxx, after theirs). ⚠ It refuses a patch without
  # a `Message-Id:` header in exactly that spelling; git format-patch now writes `Message-ID:`.
  cp "$here"/patches/vlc/*.patch "$work/libvlcjni/libvlc/patches/"
  (cd "$work/libvlcjni" && ./buildsystem/get-vlc.sh)
  git -C "$work/libvlcjni/vlc" merge-base --is-ancestor "$MP4_SEEK_FIX" HEAD \
    || fail "this VLC lacks the MP4 seek fix $MP4_SEEK_FIX (Apple's patch 0006) — pin a newer libvlcjni."
  echo "libvlcjni $LIBVLCJNI_COMMIT, VLC $(git -C "$work/libvlcjni/vlc" rev-parse HEAD)"
}

# libvlcjni lists `--enable-zvbi \` twice: once for the contribs, once for VLC's configure.
# Both become `--disable-zvbi`; the configure line then carries it into libvlc.so, where
# Scripts/check-engine-gpl-free.sh looks for it.
keep_zvbi_out() {
  local script="$work/libvlcjni/buildsystem/build-libvlc.sh"
  local found
  found=$(grep -c -- '--enable-zvbi \\$' "$script" || true)
  [ "$found" -eq 2 ] || fail "expected --enable-zvbi twice in libvlcjni's build-libvlc.sh, found $found — its build script changed; read it before building."
  sed -i.orig 's/--enable-zvbi \\$/--disable-zvbi \\/' "$script"
  [ "$(grep -c -- '--disable-zvbi \\$' "$script")" -eq 2 ] || fail "zvbi could not be switched off in build-libvlc.sh."
}

# The licences of the code VLC's build compiles for libvlc.so, its contribs (BSD, MIT, LGPL … — every package it
# built, a few build-only ones among them), as their sources carry them at their top:
# out/licenses-<abi>/<package>/<file>, and out/licenses-<abi>/MISSING naming a package without such a file. aar()
# puts them into the package's licenses/; Scripts/gen-android-notices.py shows them on the app's licences page and
# refuses a package listed in MISSING that it has no text for. (The package's other file of VLC, its HRTF in
# assets/hrtfs, is VLC's own, under VLC's LGPL 2.1+: VLC commit 387c991a.)
collect_licences() {
  local abi=$1 vlc=$2 contrib dir file files licences
  licences="$out/licenses-$abi"
  contrib=$(find "$vlc/contrib" -mindepth 1 -maxdepth 1 -type d -name 'contrib-android-*')
  [ -n "$contrib" ] && [ "$(wc -l <<<"$contrib")" -eq 1 ] \
    || fail "expected one contrib-android-* folder under $vlc/contrib, found: ${contrib:-none}."
  rm -rf "$licences"
  mkdir -p "$licences"
  : > "$licences/MISSING"
  for dir in "$contrib"/*/; do
    # COPYING, COPYING.LIB, COPYINGv3, LICENSE.md, LICENCE-BSD.txt, Copyright, NOTICE …; not glslang's
    # license-checker.cfg nor a script.
    files=$(find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) | grep -iE '/(copying|licen[cs]e|copyright|notice|unlicense)[^/]*$' \
      | grep -viE '\.(cfg|py|sh|json|ya?ml|in|am|ac|c|h|cmake)$' || true)
    if [ -z "$files" ]; then
      basename "$dir" >> "$licences/MISSING"
      continue
    fi
    mkdir -p "$licences/$(basename "$dir")"
    while IFS= read -r file; do cp "$file" "$licences/$(basename "$dir")/"; done <<<"$files"
  done
  # As with zvbi: a search that finds nothing proves nothing. FFmpeg's and GnuTLS's must be there.
  [ -d "$licences/ffmpeg" ] && [ -d "$licences/gnutls" ] \
    || fail "no licence of FFmpeg or GnuTLS under $contrib — the contribs are not where collect_licences looks."
  echo "licences of $(find "$licences" -mindepth 1 -maxdepth 1 -type d | wc -l) contribs; without one: $(tr '\n' ' ' < "$licences/MISSING")"
}

natives() {
  local abi=$1
  case " $ABIS " in
    *" $abi "*) ;;
    *) fail "unknown ABI '$abi' — one of: $ABIS" ;;
  esac
  fetch_sources
  keep_zvbi_out
  (cd "$work/libvlcjni" && ./buildsystem/compile-libvlc.sh -a "$abi" --release --license l)

  local vlc="$work/libvlcjni/vlc"
  # ⚠ The search below proves nothing where it finds nothing at all: FFmpeg's own library must be
  # found there first, or the contribs are not where it looks (it would pass without looking).
  find "$vlc/contrib" -name 'libavcodec.a' | grep -q . \
    || fail "no libavcodec.a under $vlc/contrib — the contribs are not where the zvbi guard looks."
  # What a zvbi build leaves behind: its library, its pkg-config file, or FFmpeg's teletext
  # decoder built against it. ⚠ Not a bare `libzvbi*`: FFmpeg's source always carries
  # libavcodec/libzvbi-teletextdec.c, unbuilt — that name failed a clean build (09.11.2026).
  if find "$vlc/contrib" \( -name 'libzvbi.a' -o -name 'libzvbi.so*' -o -name 'zvbi-0.2.pc' \
      -o -name 'libzvbi-teletextdec.o' \) | grep -q .; then
    fail "the zvbi library (GPL) was built for $abi."
  fi
  # The modules linked into libvlc.so, as the build listed them for its static module table
  # (one build-android-<target> folder: fetch_sources starts from a fresh tree).
  grep -o 'vlc_entry__[A-Za-z0-9_]*' "$vlc"/build-android-*/ndk/libvlcjni-modules.c \
    | sed 's/^vlc_entry__//' | sort -u > "$out/modules-$abi.txt"
  if grep -qx 'zvbi' "$out/modules-$abi.txt"; then
    fail "the zvbi module (GPL) is linked into libvlc.so for $abi."
  fi
  echo "$(wc -l < "$out/modules-$abi.txt") modules, none of them zvbi"
  collect_licences "$abi" "$vlc"

  rm -rf "${out:?}/libs/$abi"
  mkdir -p "$out/libs/$abi"
  cp "$work/libvlcjni/libvlc/jni/libs/$abi/"*.so "$out/libs/$abi/"
  # The two libraries built here keep their symbol table (task 8.6): ndk-build strips what it puts
  # into libs/, and a crash inside them showed bare addresses. obj/local/ holds them as linked; only
  # their DWARF goes (Play Console and ndk-stack name functions from the symbol table). The app's
  # build strips the table from what ships and puts it into the bundle for Play (AGP's
  # `debugSymbolLevel`), as it already did for libc++_shared.so, which the NDK ships unstripped.
  local strip=("$ANDROID_NDK"/toolchains/llvm/prebuilt/*/bin/llvm-strip) lib
  for lib in libvlc.so libvlcjni.so; do
    "${strip[0]}" --strip-debug -o "$out/libs/$abi/$lib" "$work/libvlcjni/libvlc/jni/obj/local/$abi/$lib" \
      || fail "$lib with its symbol table: no $work/libvlcjni/libvlc/jni/obj/local/$abi/$lib, or no NDK llvm-strip."
  done
  ls -l "$out/libs/$abi"
}

aar() {
  local abi
  for abi in $ABIS; do
    [ -d "$out/libs/$abi" ] || fail "no $out/libs/$abi — build its natives first."
  done
  fetch_sources # the VLC tree gives the package its HRTF file (no Lua scripts: patches/libvlcjni/0002)
  mkdir -p "$work/libvlcjni/libvlc/jni/libs"
  cp -R "$out/libs/"* "$work/libvlcjni/libvlc/jni/libs/"
  (cd "$work/libvlcjni" && gradle --no-daemon :libvlc:assembleRelease)
  local built
  built=$(find "$work/libvlcjni/libvlc/build/outputs/aar" -name '*.aar' | head -1)
  [ -n "$built" ] || fail "gradle built no .aar."
  cp "$built" "$out/libvlc.aar"
  # The contribs' licences of every ABI (natives' collect_licences), one folder each: the same sources for both.
  rm -rf "$out/licenses"
  mkdir -p "$out/licenses"
  for abi in $ABIS; do
    [ -f "$out/licenses-$abi/MISSING" ] || fail "no $out/licenses-$abi — its natives ran without collect_licences."
    cp -R "$out/licenses-$abi/." "$out/licenses/"
  done
  sort -u "$out"/licenses-*/MISSING > "$out/licenses/MISSING"
  # Beside the package's own files; the app's build reads them from the package, nothing of them ships.
  (cd "$out" && python3 -c 'import sys, zipfile, pathlib
with zipfile.ZipFile(sys.argv[1], "a", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(pathlib.Path("licenses").rglob("*")):
        if f.is_file(): z.write(f)' libvlc.aar)
  echo "$(basename "$built") → $out/libvlc.aar, with the licences of $(find "$out/licenses" -mindepth 1 -maxdepth 1 -type d | wc -l) contribs"
}

case "${1:-}" in
  natives) [ $# -eq 2 ] || fail "usage: $0 natives <abi>"; natives "$2" ;;
  aar) aar ;;
  *) echo "usage: $0 natives <abi> | aar" >&2; exit 2 ;;
esac
