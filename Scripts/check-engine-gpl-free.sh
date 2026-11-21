#!/bin/bash
#
# check-engine-gpl-free.sh — is this binary the GPL-free libVLC? ONE rule for both platforms:
#   • Scripts/check-release-package.sh (the Apple app binary, libVLC linked in)
#   • android/libvlc/check.sh (Android's libvlc.so, and the libraries shipped with it)
#
#   Scripts/check-engine-gpl-free.sh <engine binary> [<binary shipped with it> …]
#
# VLC's LGPL switch picks the contribs; VLC's own modules are compiled whatever it says. One GPL
# piece linked and the app cannot be in the App Store or on Google Play under the LGPL:
#   • the zvbi teletext library (GPL-2+; its contrib rule has no REQUIRE_GPL). Teletext comes from
#     VLC's own LGPL decoder (telx) instead;
#   • VLC's GPL-2+ modules (below), which each engine build leaves out by name;
#   • FFmpeg's GPL yadif line filter inside VLC's otherwise LGPL deinterlace plugin.
# Held by android/libvlc/check-test.sh.

set -euo pipefail

fail() { echo "  ⚠ $*"; exit 1; }

[ $# -ge 1 ] || { echo "usage: $0 <engine binary> [<binary shipped with it> …]"; exit 2; }
for binary in "$@"; do
  [ -f "$binary" ] || fail "not found: $binary"
done

strings=$(mktemp)
trap 'rm -f "$strings"' EXIT

# libVLC records its configure line in the binary ("configured with …", src/misc/messages.c).
# Requiring `--disable-zvbi` to be THERE is what makes the absence checks below meaningful:
# without it, a binary that simply did not contain the engine would pass them.
strings -a "$1" > "$strings"
grep -q -- '--disable-zvbi' "$strings" \
  || fail "libVLC's configure line (--disable-zvbi) is missing — not the GPL-free engine, or no engine at all."
if grep -q -- '--enable-gpl' "$strings"; then
  fail "the engine was configured with --enable-gpl."
fi

# VLC's GPL-2.0-or-later modules: every module both engines compiled in, scanned file by file
# (21.11.2026, docs/log/2026-11-21-08-libvlc-gpl-modules-out.md). Each build leaves them out: Apple
# in the SwiftVLC-LGPL fork's build-libvlc.sh, Android in android/libvlc/patches/libvlcjni/0002.
# Each module is found by its description, a whole string that every form of the engine keeps
# (the static library, the package, the linked app); measured in both engines of that day.
# ⚠ Whole strings only (grep -x): a description, not any longer string that happens to hold it.
gpl_modules=(
  "dummy:Dummy interface"                         # control/dummy.c
  "file_logger:File logger"                       # logger/file.c
  "hqdn3d:High Quality 3D Denoiser filter"        # video_filter/hqdn3d.h
  "lua:Lua interpreter"                           # modules/lua/
  "rc:Remote control interface"                   # control/cli/
  "rotate:Rotate video filter"                    # video_filter/rotate.c, control/motionlib.c
  "sap:Network streams (SAP)"                     # services_discovery/sap.c
  "stream_out_cycle:Cyclic stream output"         # stream_out/cycle.c
  "stream_out_rtp:RTP stream output"              # stream_out/rtp.c
  "syslog:System logger (syslog)"                 # logger/syslog.c
)
# Yadif (FFmpeg's deinterlace/yadif.h) is code without strings. The mode names that select it are
# strings: deinterlace's table and the core's lists, which fork patch 0008 / patches/vlc/9007 take
# out together with the code. Unstripped, also its functions' names.
# ⚠ Not "yadif" alone: libplacebo (LGPL) has a yadif shader of its own and names it
# (PL_DEINTERLACE_YADIF; in Apple's engine of 21.11.2026).
yadif=(-e 'yadif2x' -e 'Yadif (2x)' -e 'RenderYadif' -e 'yadif_filter_line')

# What a linked zvbi leaves, even stripped: VLC's zvbi module's description and its own options,
# FFmpeg's zvbi decoder's name; unstripped, also the library's function names.
# ⚠ Not "vbi-page" or "vbi-opaque": VLC 4's core uses them for every teletext decoder, telx
# included — both GPL-free engines carry them (measured 10.11.2026). The three module strings
# were measured in VLC 3's zvbi plugin, and in none of the GPL-free engines.
for binary in "$@"; do
  strings -a "$binary" > "$strings"
  zvbi=$(grep -c -e 'VBI and Teletext decoder' -e 'vbi-position' -e 'vbi-level' -e 'libzvbi_teletextdec' \
    -e 'vbi_decoder' -e 'vbi_capture' -e 'decoder_zvbi' "$strings" || true)
  [ "$zvbi" -eq 0 ] || fail "$zvbi zvbi strings in $(basename "$binary") — the GPL teletext decoder is linked."

  found=()
  for module in "${gpl_modules[@]}"; do
    grep -qxF -- "${module#*:}" "$strings" && found+=("${module%%:*}")
  done
  grep -qF "${yadif[@]}" "$strings" && found+=("yadif (in deinterlace)")
  [ ${#found[@]} -eq 0 ] || fail "GPL VLC code in $(basename "$binary"): $(printf '%s, ' "${found[@]}" | sed 's/, $//')."
done
echo "  ✓ engine GPL-free (--disable-zvbi; no zvbi, no GPL module, no yadif in $# $([ $# -eq 1 ] && echo binary || echo binaries))"
