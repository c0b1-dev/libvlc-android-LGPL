#!/bin/bash
#
# check-test.sh — the package check refuses what it must, on made-up packages: check.sh and the
# engine rule it shares with Apple's release check (Scripts/check-engine-gpl-free.sh). A check
# that passes a broken package is worse than none. The libVLC workflow runs it before building.
#
#   android/libvlc/check-test.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/engine.env"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A stand-in for `readelf -lW <lib>` (one LOAD segment, aligned to 4 KB where the library says so)
# and `readelf -SW <lib>` (a symbol table, unless the library says it was stripped; the line as
# llvm-readelf prints it for libc++_shared.so).
cat > "$work/readelf" <<'STUB'
#!/bin/sh
for lib; do :; done
case "$1" in
  -SW) grep -q 'STRIPPED' "$lib" || echo "  [29] .symtab           SYMTAB          0000000000000000 14efc8 033a50 18     31 6316  8" ;;
  *) if grep -q 'ALIGNED-4K' "$lib"; then align=0x1000; else align=0x4000; fi
     echo "  LOAD 0x000000 0x0000000000000000 0x0000000000000000 0x001000 0x001000 R E $align" ;;
esac
STUB
chmod +x "$work/readelf"
export READELF="$work/readelf"

# A package as the build makes it: every ABI's three libraries, the engine with its configure line.
good() {
  rm -rf "$work/pkg"
  for abi in $ABIS; do
    mkdir -p "$work/pkg/jni/$abi"
    echo "configured with ./configure '--host=x' '--disable-zvbi' '--enable-lua'" > "$work/pkg/jni/$abi/libvlc.so"
    echo "ASurfaceTransaction_reparent" >> "$work/pkg/jni/$abi/libvlc.so"
    echo "ch.codebits.cobiplayer.proxy" >> "$work/pkg/jni/$abi/libvlc.so"
    echo "%u picture(s) still in a surface transaction after %ld ms: leaking them" >> "$work/pkg/jni/$abi/libvlc.so"
    echo "stopping: ending the downloads in progress" >> "$work/pkg/jni/$abi/libvlc.so"
    echo "no surface: the video context goes before the decoder used it" >> "$work/pkg/jni/$abi/libvlc.so"
    echo "Java_org_videolan_libvlc_LibVLC_nativeNew" > "$work/pkg/jni/$abi/libvlcjni.so"
    echo "std::__ndk1::basic_string" > "$work/pkg/jni/$abi/libc++_shared.so"
  done
}

failures=0
# expect <pass | a fragment of the refusal> <case>, after good() and the case's own change: a
# refusal must name its own reason, or a case could pass on another rule's refusal.
expect() {
  local want=$1 name=$2 out status=0
  rm -f "$work/test.aar"
  (cd "$work/pkg" && zip -qr ../test.aar .)
  out=$("$here/check.sh" "$work/test.aar" 2>&1) || status=$?
  if [ "$want" = pass ] && [ $status -eq 0 ]; then echo "  ✓ $name"; return; fi
  if [ "$want" != pass ] && [ $status -eq 1 ] && grep -qF -- "$want" <<<"$out"; then echo "  ✓ $name"; return; fi
  echo "  ✗ $name — expected: $want; exit $status:"
  sed 's/^/      /' <<<"$out"
  failures=$((failures + 1))
}

arm64=$work/pkg/jni/arm64-v8a
arm32=$work/pkg/jni/armeabi-v7a
good; expect pass "a package as the build makes it passes"
good; rm "$arm64/libvlcjni.so"; expect "libvlcjni.so missing" "a missing library"
good; echo ALIGNED-4K >> "$arm64/libc++_shared.so"; expect "not 16 KB" "a 64-bit library aligned to 4 KB"
good; echo "no engine here" > "$arm64/libvlc.so"; expect "configure line" "no engine's configure line"
good; echo "'--enable-gpl'" >> "$arm64/libvlc.so"; expect "--enable-gpl" "an engine configured with --enable-gpl"
good; echo "VBI and Teletext decoder" >> "$arm64/libvlc.so"; expect "zvbi strings in libvlc.so" "VLC's zvbi module linked"
good; echo "vbi-level" >> "$arm32/libvlc.so"; expect "zvbi strings in libvlc.so" "the zvbi module's own option, 32-bit"
good; echo "libzvbi_teletextdec" >> "$arm64/libvlc.so"; expect "zvbi strings in libvlc.so" "FFmpeg's zvbi decoder linked"
good; echo "VBI and Teletext decoder" >> "$arm64/libvlcjni.so"; expect "zvbi strings in libvlcjni.so" "zvbi in a library shipped with the engine"
good; echo "vbi-page vbi-opaque" >> "$arm64/libvlc.so"; expect pass "the core's teletext options pass (telx uses them too)"
good; echo "Network streams (SAP)" >> "$arm64/libvlcjni.so"; expect "GPL VLC code in libvlcjni.so: sap" "a GPL module in a library shipped with the engine"
good; printf 'Lua interpreter\nDummy interface\n' >> "$arm32/libvlc.so"; expect "GPL VLC code in libvlc.so: dummy, lua" "two GPL modules, 32-bit: both named"
good; echo "yadif2x" >> "$arm64/libvlc.so"; expect "GPL VLC code in libvlc.so: yadif (in deinterlace)" "yadif's mode name (stripped engine)"
good; echo "RenderYadifSingle" >> "$arm32/libvlc.so"; expect "yadif (in deinterlace)" "yadif's function name (symbol table), 32-bit"
good; printf 'yadif\nPL_DEINTERLACE_YADIF\n' >> "$arm64/libvlc.so"; expect pass "libplacebo's own yadif shader passes"
good; echo "Remote control interface initialized. Type \`help' for help." >> "$arm64/libvlc.so"; expect pass "a longer string holding a description passes (whole strings only)"
good; mkdir -p "$work/pkg/assets/lua/playlist"; echo "-- youtube" > "$work/pkg/assets/lua/playlist/youtube.lua"; expect "carries VLC's Lua scripts" "a package with VLC's Lua scripts"
good; mkdir -p "$work/pkg/assets/hrtfs"; echo sofa > "$work/pkg/assets/hrtfs/x.sofa"; expect pass "the HRTF file passes"

# Every module in the engine rule's list must be refused by its own entry: read from the rule itself,
# so a new entry is tested without anyone adding it here (and an entry the rule misreads fails).
modules=$(sed -n '/^gpl_modules=(/,/^)/p' "$here/../../Scripts/check-engine-gpl-free.sh" | sed -n 's/^  "\([^:]*\):\([^"]*\)".*/\1\t\2/p')
[ "$(wc -l <<<"$modules")" -ge 10 ] || { echo "  ✗ read fewer than 10 GPL modules from check-engine-gpl-free.sh"; failures=$((failures + 1)); }
while IFS=$'\t' read -r module description; do
  good; echo "$description" >> "$arm64/libvlc.so"
  expect "GPL VLC code in libvlc.so: $module." "the GPL module $module (\"$description\")"
done <<<"$modules"
good; mkdir -p "$work/pkg/jni/x86_64"; cp "$arm64/"* "$work/pkg/jni/x86_64/"; expect "does not list: x86_64" "an ABI engine.env does not list"
good; echo extra > "$arm64/libextra.so"; expect "unexpected file, libextra.so" "a library the check does not know"
good; grep -v reparent "$arm32/libvlc.so" > "$work/libvlc.so" && mv "$work/libvlc.so" "$arm32/libvlc.so"; expect "lacks our display fix" "an engine built without our VLC fix, 32-bit"
good; grep -v cobiplayer.proxy "$arm64/libvlc.so" > "$work/libvlc.so" && mv "$work/libvlc.so" "$arm64/libvlc.so"; expect "lacks the app's proxy" "an engine built without the app's proxy"
good; grep -v "surface transaction" "$arm64/libvlc.so" > "$work/libvlc.so" && mv "$work/libvlc.so" "$arm64/libvlc.so"; expect "lacks the display's close fix" "an engine built without the display's close fix"
good; grep -v "ending the downloads" "$arm32/libvlc.so" > "$work/libvlc.so" && mv "$work/libvlc.so" "$arm32/libvlc.so"; expect "lacks the adaptive stop fix" "an engine built without the adaptive stop fix, 32-bit"
good; grep -v "no surface" "$arm64/libvlc.so" > "$work/libvlc.so" && mv "$work/libvlc.so" "$arm64/libvlc.so"; expect "lacks the decoder's missing-window fix" "an engine built without the decoder's missing-window fix"
good; echo STRIPPED >> "$arm64/libvlc.so"; expect "libvlc.so carries no symbol table" "a stripped engine (bare addresses in crash traces)"
good; echo STRIPPED >> "$arm32/libvlcjni.so"; expect "libvlcjni.so carries no symbol table" "stripped bindings, 32-bit"

# Each patch rule's marker is a string the patch puts into libvlc.so: it must still be in that patch,
# or a reworded patch is refused only after the hours of building. Read from check.sh itself: every
# `grep -qaF <marker>` whose next line names patches/vlc/<number>.
markers=$(awk '/grep -qaF/ { match($0, /grep -qaF ("[^"]+"|[^ ]+)/); m = substr($0, RSTART + 10, RLENGTH - 10)
  gsub(/"/, "", m); getline next_line
  if (match(next_line, /patches\/vlc\/9[0-9][0-9][0-9]/)) print substr(next_line, RSTART + 12, 4) "\t" m }' "$here/check.sh")
[ "$(wc -l <<<"$markers")" -ge 4 ] || { echo "  ✗ read fewer than 4 patch markers from check.sh"; failures=$((failures + 1)); }
while IFS=$'\t' read -r number marker; do
  patch=("$here"/patches/vlc/"$number"-*.patch)
  if [ -f "${patch[0]}" ] && grep -qF -- "$marker" "${patch[0]}"; then
    echo "  ✓ patch $number holds the check's marker \"$marker\""
  else
    echo "  ✗ check.sh looks for \"$marker\", which patch $number does not hold"
    failures=$((failures + 1))
  fi
done <<<"$markers"

[ $failures -eq 0 ] || { echo "⚠ the package check passed or refused $failures made-up packages wrongly"; exit 1; }
echo "✓ the package check refuses what it must"
