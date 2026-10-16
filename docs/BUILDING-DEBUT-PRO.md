# Building Debut Pro

Debut Pro is built in the cloud by GitHub Actions, for **macOS on Apple
Silicon** and for **Windows x64**. Nothing has to be installed on your own
computer to get a build.

## Getting a build

1. Open the repository on GitHub and click the **Actions** tab.
2. Pick **Build macOS** or **Build Windows** on the left, then click the
   newest run with a green check mark.
3. Scroll to **Artifacts** at the bottom of the run page and download:
   - `DebutPro-macos-arm64.dmg`: the Mac app (or `DebutPro-macos-arm64.zip`
     if creating the disk image failed; it contains the same app)
   - `DebutPro-windows-x64.zip`: the portable Windows folder

You must be signed in to GitHub to download artifacts. GitHub deletes them
after **14 days**; start a new run to get a fresh one.

A run starts automatically on every push to the `main` branch. To start one
by hand: Actions → pick the workflow → **Run workflow**. Tick **Ignore the
cached FFmpeg, MLT and other libraries** only when the libraries themselves
need rebuilding (see [the dependency cache](#the-dependency-cache)). A newer
push to the same branch cancels a run that is still in progress.

If the repository is private, GitHub counts macOS minutes at 10 times the
Windows rate against the account's monthly allowance. A first macOS build
can use most of a free account's monthly minutes. Public repositories build
for free.

## Installing on a Mac

Requirements: a Mac with Apple Silicon (M1 or newer) and **macOS 15 Sequoia
or newer**. The app bundles Homebrew libraries built for macOS 15, so it does
not start on macOS 14.

1. Open the `.dmg` and drag **Debut Pro** onto **Applications**.
2. Open Debut Pro. macOS will refuse, because the app is not notarized by
   Apple (that needs a paid Apple Developer account). Close the message
   (click **Done**, not **Move to Trash**).
3. Open **System Settings → Privacy & Security**, scroll down to the message
   about "Debut Pro" and click **Open Anyway**, then confirm with your
   password. Since macOS 15, right-clicking the app and choosing **Open** no
   longer offers this.

Alternatively, run this once in Terminal, then open the app normally:

```sh
xattr -dr com.apple.quarantine "/Applications/Debut Pro.app"
```

The Terminal command also helps if macOS says the app "is damaged and can't
be opened": that message usually means the download was quarantined, not
that it is broken.

## Installing on Windows

1. Right-click `DebutPro-windows-x64.zip` → **Extract All…**, and extract it
   somewhere you can write to, for example **Documents**. This is a
   portable build: there is no installer and nothing is written outside the
   folder except your settings.
2. Open the **Debut Pro** folder and run **Debut Pro.exe**.
3. The first time, Windows SmartScreen may say "Windows protected your PC",
   because the program is not signed with a paid certificate. Click
   **More info**, then **Run anyway**.

To uninstall, delete the folder.

GPU video: the Windows build's FFmpeg includes NVIDIA NVENC/NVDEC (CUDA),
AMD AMF, Intel Quick Sync (oneVPL) and Direct3D 11/DXVA2 decoding. They work
with any reasonably recent graphics driver; nothing extra needs installing.
The Mac build uses VideoToolbox.

## How the CI works

Two workflows in `.github/workflows/`:

| | `build-macos.yml` | `build-windows.yml` |
|---|---|---|
| Runner | `macos-15` (Apple Silicon M1, 3 cores) | `windows-latest` (x64, 4 cores) |
| Build script | `scripts/build-shotcut.sh` | `scripts/build-shotcut-msys2.sh` |
| Settings | `scripts/ci/macos.conf` | `scripts/ci/windows.conf` |
| Toolchain | Xcode clang, Homebrew tools | MSYS2 UCRT64 (GCC), like upstream Shotcut |
| Qt | 6.10.3 from `jurplel/install-qt-action` | MSYS2's Qt 6 packages (6.11 when this was written) |
| Packaging | `scripts/ci/package-macos.sh` | `scripts/ci/package-windows.sh` |
| Checks | `scripts/ci/verify-macos.sh` | inline PowerShell step |

The two scripts are Shotcut's own build scripts with a few additions (each
new setting is documented at the top of the script):

- `SHOTCUT_LOCAL_SOURCE`: build **this repository's checkout** instead of
  cloning `mltframework/shotcut`. The checkout is copied to
  `$SOURCE_DIR/shotcut`, because the build happens inside the source folder.
  (The upstream settings `SHOTCUT_HEAD`/`SHOTCUT_REVISION` only select which
  upstream commit to clone, so they are not used.) On Windows, Shotcut's
  FFmpeg patch (`scripts/ffmpeg9-hwcontext_d3d11va.patch`) is now applied
  from this checkout right after FFmpeg is downloaded.
- `SUBDIRS_EXCLUDE`: leave projects out of the build. CI first builds every
  dependency with `SUBDIRS_EXCLUDE="shotcut"`, then only the app with
  `SUBDIRS="shotcut"`.
- `MLT_ADDITIONAL_OPTIONS`: extra CMake options for MLT.
- `ENABLE_AOM` (Windows script): AOM can now be switched off like the other
  optional parts.
- macOS only: `MACOS_ARCHITECTURES` (upstream builds universal
  arm64+x86_64; CI builds arm64 only), `MACOS_DEPS_PREFIX` (upstream uses
  MacPorts in `/opt/local`; CI uses Homebrew in `/opt/homebrew`) and
  `MACOS_OPENMP_INCLUDE_DIR`/`MACOS_OPENMP_LIB_DIR` (Homebrew's `libomp` is
  in `/opt/homebrew/opt/libomp`).
- The packaging steps no longer fail when an optional part (Whisper, OpenCV,
  Glaxnimate, VMAF, AOM, GoPro2GPX) was not built, and the macOS bundling step
  also copies libraries that are referenced through `@rpath` or come from
  Homebrew.

Each workflow:

1. Installs build tools: Homebrew packages on macOS, MSYS2 packages on
   Windows.
2. Writes the settings file: build folders, version (`YY.M.D` of the build
   day), `SHOTCUT_LOCAL_SOURCE`, plus `scripts/ci/<os>.conf`.
3. Restores the dependency cache, or on a miss builds the dependencies and
   saves them to the cache.
4. Builds Debut Pro and runs the script's deploy step, which gathers every
   library, Qt plugin, QML module and MLT/frei0r/LADSPA plugin next to the
   app and rewrites library paths.
5. Packages:
   - **macOS**: copies `Shotcut.app` to `Debut Pro.app`, keeps only the arm64
     code in Qt's universal binaries, removes run paths that point at the
     build machine, signs every binary and then the whole app ad hoc
     (`codesign --force --sign -` on each file, then
     `codesign --force --deep --sign -` on the bundle; Apple Silicon refuses
     to run unsigned code, and the path rewriting invalidated the linker's
     signatures), and makes the disk image with `hdiutil` (falls back to
     `ditto -c -k --keepParent` into a zip). Not notarized.
   - **Windows**: moves the deployed folder to `Debut Pro/`, renames
     `shotcut.exe` to `Debut Pro.exe`, adds a README and zips it.
6. Uploads the package (uploaded as is, not zipped again).
7. Checks the package: no library may be missing or point outside the app,
   FFmpeg must have the expected encoders, decoders and hardware
   acceleration, `melt -query` must list the main MLT services (this loads
   every MLT module), and the app must answer `--version`. A failed check
   marks the run red, but the package has already been uploaded.
8. On failure, uploads `build-logs-macos-arm64` or `build-logs-windows-x64`
   with the build logs, the settings files and the configure logs.

Internal names stay as in Shotcut: the CMake target, `Shotcut.app` during
the build, `Contents/MacOS/Shotcut` inside the Mac bundle, and
`share/shotcut`, `lib/mlt` and so on. Only what users see is renamed. Renaming
the Windows executable is safe: the code finds `melt`, `ffmpeg` and `ffprobe`
and its data through `QCoreApplication::applicationDirPath()`, restarts itself
through `applicationFilePath()`, Qt reads `qt.conf` from the executable's
folder, settings are stored under the organization and application names set
in `main.cpp`, and the Dr. Mingw crash handler is only linked into debug
builds. The portable zip registers no file associations.

### What is built, and what is left out

Built from source by the scripts (both platforms unless noted): FFmpeg 9.0
(release branch), MLT (pinned commit, see below), frei0r, Movit, dav1d (AV1
decoding), rnnoise, and the SWH LADSPA plugins. Windows also builds
nv-codec-headers and the AMF headers. macOS also builds x264, x265, libvpx,
Opus, SVT-AV1 (AV1 encoding), libwebp, zimg, vid.stab and Rubber Band. On
Windows those come from MSYS2 packages, as upstream does it.

From the package manager: SoX, FFTW, libsamplerate, LAME, Vorbis/Theora,
GLib, lilv, cairo, libepoxy and others (Homebrew on macOS, MSYS2 on Windows).

Left out on purpose, to keep the build faster and the app smaller:
whisper.cpp (speech to text) and OpenBLAS, OpenCV and opencv_contrib (motion
tracking), Glaxnimate and MLT's Glaxnimate module (vector animations),
gopro2gpx, libspatialaudio (360° audio), bigsh0t (360° video filters), VMAF
and AOM. The features in the app that rely on them will not work. The scripts
never bundled Kokoro, Docker or Chrome; the small `voices` folder is
installed by the app's own CMake rules, not by the scripts.

On macOS, MLT's SDL2 module and FFmpeg's `ffplay` are also left out:
Homebrew's `sdl2` is now sdl2-compat, which aborts the program when SDL3 is
not next to it. The app plays audio through RtAudio (CoreAudio), which
Shotcut already uses when SDL is not available. Windows keeps SDL2 (the real
SDL2 package is named explicitly).

### The dependency cache

Building the dependencies is the slow part, so the result (the
`$RUNNER_TEMP/dp/build` folder on macOS, `$RUNNER_TEMP/dp/Shotcut` on
Windows) is stored with `actions/cache` before the app is built. Debut Pro
itself is always rebuilt. The cache key changes, causing a full rebuild,
when any of these change:

- the build script or `scripts/ci/<os>.conf` (for example a new MLT pin)
- the Qt version or deployment target (macOS)
- the file names of the package manager's libraries, i.e. a new major
  version of one of them (Homebrew dylibs on macOS, every DLL in
  `/ucrt64/bin` on Windows), or the macOS/Xcode SDK or GCC major version
- `CACHE_VERSION` at the top of the workflow file (bump it to throw the
  cache away by hand), or the **Ignore the cached …** option of a manual run

Projects that follow their main branch (frei0r, rnnoise, zimg) are updated
only when the cache is rebuilt. GitHub keeps up to 10 GB of caches per
repository and drops caches that have not been used for 7 days.

### MLT version

Both settings files pin MLT to commit `a5639e5efc52` (MLT 7.43.0, 15 October
2026), the newest commit when the Shotcut sources were imported. Debut Pro
needs mlt++ 7.36.0 or newer. Pinning keeps builds reproducible and the cache
valid. To update MLT, change `MLT_REVISION` in both
`scripts/ci/macos.conf` and `scripts/ci/windows.conf` (or set `MLT_HEAD=1`
to follow MLT's main branch like Shotcut's nightly builds; the cache would
then not notice MLT changes).

### Expected durations

These are estimates; check the first runs.

| | First run or cache rebuild | With cache |
|---|---|---|
| macOS | 60–100 min | 25–40 min |
| Windows | 70–120 min | 35–55 min |

Each job stops after 300 minutes (GitHub's maximum is 360).

## Building on your own computer

The same scripts work outside CI. Copy the settings the workflow writes
(see the "Prepare build configuration" step) into a file, adjust the folders,
and run, for example on a Mac with Homebrew and Qt installed:

```sh
bash scripts/build-shotcut.sh -c my-build.conf
bash scripts/ci/package-macos.sh ~/dp/src/shotcut/Shotcut.app 26.10.15 ~/dp/out COPYING
```

On Windows, run `scripts/build-shotcut-msys2.sh` from an MSYS2 UCRT64 shell
with the packages listed in `build-windows.yml`. For everyday development,
`AGENTS.md` describes the CMake preset, which uses your own Qt and MLT.

## What to watch on the first CI runs

These are the assumptions made without being able to run the builds, roughly
ordered from most to least likely to break the first run.

1. **macOS dependencies on Homebrew instead of MacPorts.** Upstream builds
   macOS outside GitHub with MacPorts; this is the first time the script runs
   against Homebrew. Most likely trouble spots:
   - **MLT configure**: `lilv-0`, `glib-2.0`, `libxml-2.0` (Homebrew's
     keg-only libxml2, added to `PKG_CONFIG_PATH` in the dependency step),
     `fftw3`, `samplerate`, `sox`, `vorbis` must all be found. A missing
     package is a one-line addition to `BREW_PACKAGES`.
   - **OpenMP** for vid.stab and MLT's OpenFX module: the flags point at
     Homebrew's keg-only `libomp`. If linking `-lomp` fails, check
     `MACOS_OPENMP_*` in `macos.conf`.
   - **SWH LADSPA plugins**: `makestub.pl` runs under the system Perl and
     needs XML::Parser (installed with cpanm if missing) and List::MoreUtils
     (a tiny stand-in providing `any`).
   - **Autotools**: Movit's `autogen.sh` calls `libtoolize`, which is linked
     to Homebrew's `glibtoolize` in `$RUNNER_TEMP/bin`.
   - **x265** declares an ancient CMake minimum, which CMake 4 rejects
     without `CMAKE_POLICY_VERSION_MINIMUM=3.5` (set in the workflow).
   - x264's own build passes `-read_only_relocs suppress` to the linker,
     which current Xcode linkers should only warn about on arm64.
2. **macOS bundling** (`deploy_mac` in `build-shotcut.sh`). It now also
   copies libraries referenced through `@rpath` (dav1d, Rubber Band and
   libwebp use that) and anything from `/opt/homebrew`, and makes the copies
   writable (Homebrew installs them read-only). `verify-macos.sh` lists every
   reference that still points outside the app. Qt's frameworks are copied as
   plain `.dylib` files, as upstream does.
3. **Windows FFmpeg configure.** `windows.conf` explicitly enables
   `ffnvcodec`, `nvenc`, `nvdec`, `cuvid`, `amf`, `libvpl`, `d3d11va` and
   `dxva2`. Upstream relies on auto-detection, so configure would silently
   drop a feature; requesting them makes configure stop with an error
   instead. If it fails, `build-logs-windows-x64` contains
   `src/FFmpeg/ffbuild/config.log`. The AMF headers come from AMF's main
   branch and nv-codec-headers from its `sdk/12.0` branch (version 12.0.16.3,
   which FFmpeg 9.0 accepts).
4. **The checks after packaging are new.** A red check can be a false alarm
   (for example a slightly different service name in a newer MLT) while the
   uploaded package is fine. Read the `::error::` lines before changing the
   build. On Windows the app check relies on
   `QT_COMMAND_LINE_PARSER_NO_GUI_MESSAGE_BOXES` to stop `--version` from
   opening a message box; a 60-second timeout only produces a warning.
5. **Qt via install-qt-action** (`@v4.4.1`, aqtinstall 3.3): assumes Qt
   6.10.3 for `mac`/`desktop` is downloadable with the add-on modules
   `qtcharts qtmultimedia qtwebsockets qtimageformats qtshadertools`, and
   that Qt SVG, Qt Declarative, Qt Tools and the translations are part of the
   base package. `QTDIR` comes from the action's `QT_ROOT_DIR`.
6. **Disk space on the macOS runner.** The full Git histories of FFmpeg,
   x265, libvpx and others are cloned. The workflow deletes the dependency
   sources before building the app; if the disk still fills up, free space
   at the start of the job.
7. **`hdiutil`** sometimes fails with "Resource busy" on GitHub's Macs. The
   packaging script retries 5 times and then falls back to a zip.
8. **Cache restore on Windows** uses a path below `$RUNNER_TEMP` (`D:\a\_temp`),
   outside the workspace. If restoring fails, the dependencies are simply
   rebuilt.
9. **Version drift.** Homebrew, MSYS2, frei0r, rnnoise and zimg move forward
   between cache rebuilds. Windows builds with MSYS2's current Qt (6.11 at
   the time of writing) while the Mac build uses 6.10.3. libvpx 1.15.2
   (pinned by the script) only knows macOS up to version 15, which is one
   reason the job runs on `macos-15` rather than a newer runner.
10. **Runtime only (not a CI failure):** the Mac app needs macOS 15 or newer
    (Homebrew's bottles target the runner's macOS), and Gatekeeper blocks it
    until it is allowed as described above.
