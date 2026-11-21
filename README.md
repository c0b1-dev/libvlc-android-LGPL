# libVLC for Android, as Cobi Player ships it (GNU LGPL)

[Cobi Player](https://cobiplayer.app) for Android plays video with **libVLC**, VideoLAN's media library. The app
carries a build of its own (`libvlc.so` and `libvlcjni.so`), made from VideoLAN's sources. This repository holds
everything that build adds to those sources:

- **the patches** to libVLC (`android/libvlc/patches/vlc/`) and to libvlcjni, VideoLAN's Android bindings
  (`android/libvlc/patches/libvlcjni/`), each with its reason in its header;
- **the build script** (`android/libvlc/build.sh`, with `engine.env` and `resolve.sh`). It fetches libvlcjni at the
  pinned commit, the VLC 4 that commit is tested with and the libraries VLC's build compiles into libVLC, applies
  the patches, and builds LGPL only: every GPL-licensed part of VLC is left out;
- **the package check** (`android/libvlc/check.sh`, with `Scripts/check-engine-gpl-free.sh`), which the build's
  result has to pass.

The paths are those of the app's own (private) repository, so the scripts run here unchanged. Comments in them name
files of that repository; they are not needed to build.

## Licence

libVLC is licensed under the **GNU LGPL version 2.1 or later**. For secure (https) connections this build includes
GnuTLS, which relies on libraries licensed under the **LGPL version 3** (Nettle and GMP). libVLC as the app ships it
is therefore covered by the **GNU LGPL version 3**, which builds on the GNU GPL version 3. The patches modify VLC and
libvlcjni and are under their licence, the GNU LGPL 2.1 or later (`COPYING.LIB`); so are the scripts.

Licence texts: [GNU LGPL 3](https://www.gnu.org/licenses/lgpl-3.0.html) ·
[GNU GPL 3](https://www.gnu.org/licenses/gpl-3.0.html) ·
[GNU LGPL 2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html). The app's licences page:
[cobiplayer.app/licenses](https://cobiplayer.app/licenses/).

## Which version of the app ships which build

Each app release has a tag here, at the state of this folder that built the libVLC it ships.

| Tag | Cobi Player for Android | libVLC package (sha256) |
| --- | --- | --- |
| `v1.5.1-code1` | 1.5.1, version code 1 | `585f597d1e09c293d3f1aeadd9cf54b19ff61c6e80e3b4e7903e9e40db5ac24b` |
| `v1.5.1-code2` | 1.5.1, version code 2 | `8fdb55928e093a6a277f0b32a334b0eea5d1661d7740d6493e8716b3a81bf9bc` |
| `v1.5.1-code3` | 1.5.1, version code 3 | `8fdb55928e093a6a277f0b32a334b0eea5d1661d7740d6493e8716b3a81bf9bc` |

`main` is the state the next release will be built from.

## Building it

It needs Docker on an x86-64 Linux machine (GitHub's `ubuntu-24.04` runners build it) and a few hours per ABI. It
runs inside VideoLAN's own build image for VLC for Android, the one libvlcjni's pinned commit names.

```bash
android/libvlc/resolve.sh        # prints the VLC commit, the build image and the ABIs
chmod -R a+rwX android/libvlc    # the image runs as its own user
IMAGE=<the image resolve.sh printed>
docker run --rm -v "$PWD:/work" -w /work "$IMAGE" android/libvlc/build.sh natives arm64-v8a
docker run --rm -v "$PWD:/work" -w /work "$IMAGE" android/libvlc/build.sh natives armeabi-v7a
docker run --rm -v "$PWD:/work" -w /work "$IMAGE" android/libvlc/build.sh aar
android/libvlc/check.sh android/libvlc/out/libvlc.aar
```

The package is `android/libvlc/out/libvlc.aar`; the libraries the app ships are inside it under `jni/<abi>/`.

## Using a modified libVLC with the app

The app loads `libvlc.so` and `libvlcjni.so` as shared libraries (in the APK under `lib/<abi>/`). A modified
build that keeps their interface works in their place; the APK then has to be signed again. Nothing in Cobi Player's
terms restricts modifying the libVLC in your copy of the app for your own use, or reverse engineering the app to
debug such modifications.

Upstream: [code.videolan.org/videolan/vlc](https://code.videolan.org/videolan/vlc) ·
[code.videolan.org/videolan/libvlcjni](https://code.videolan.org/videolan/libvlcjni)
