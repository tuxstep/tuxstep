#!/bin/bash
set -ex

# Build Darling using the monorepo pattern (xnulinux/darling-style).
# Clones darlinghq/darling at a pinned release tag, rewrites .gitmodules
# to point at our 4 tuxstep forks where applicable, inits only headless-
# relevant submodules, builds the darlingserver target via -DCOMPONENTS=cli,
# installs the resulting binary into the rootfs at /usr/sbin/darlingserver.
#
# Why this dance: darlingserver isn't standalone-buildable. Its duct-tape
# CMakeLists uses mig() from cmake/mig.cmake at the monorepo root, plus
# add_darling_library, ARCH/TRIPLET variables, the build-mig tool, and a
# bunch of supporting cmake/*.cmake macros. Replicating that harness
# outside the monorepo doesn't scale; using it from inside is a bounded
# few hundred lines of bash.
#
# Required env: ROOTFS — path to the rootfs to install into.
# Optional env: WORK   — work dir (default: $PWD/work)

: "${ROOTFS:?ROOTFS env var required (path to rootfs to install into)}"

WORK="${WORK:-$(pwd)/work}"
BUILD_DIR="${WORK}/build-darling"
DARLING_REPO="https://github.com/darlinghq/darling.git"
DARLING_TAG="v0.1.20260222"

rm -rf "${BUILD_DIR}"
mkdir -p "${WORK}"

# === Clone the monorepo at the pinned tag (no submodules yet) ===
echo "==> Cloning Darling monorepo at ${DARLING_TAG}..."
git clone --depth=1 --branch "${DARLING_TAG}" --no-recurse-submodules \
    "${DARLING_REPO}" "${BUILD_DIR}"

cd "${BUILD_DIR}"

# === Rewrite .gitmodules: point our 4 forked components at the tuxstep ===
# === org. Order matters — specific tuxstep rewrites first, then catch-  ===
# === all to darlinghq for everything else.                              ===
echo "==> Rewriting .gitmodules to use tuxstep forks where applicable..."
sed -i '
    s|url = \.\./darling-dyld\.git|url = https://github.com/tuxstep/darling-dyld.git|
    s|url = \.\./darling-Libsystem\.git|url = https://github.com/tuxstep/darling-Libsystem.git|
    s|url = \.\./darlingserver\.git|url = https://github.com/tuxstep/darlingserver.git|
    s|url = \.\./|url = https://github.com/darlinghq/|
' .gitmodules
git submodule sync --recursive

# === Init only submodules needed for a headless cli build. ===
# Skip GUI / Swift / language-runtime / webkit / metal / iokitd / older
# libressl variants — they're either gated behind COMPONENT_gui/jsc/etc.
# at the cmake level, or excluded via -DBUILD_SWIFT=OFF /
# -DBUILD_LEGACY_LIBRESSL=OFF in the configure step below. List borrowed
# from xnulinux/darling's already-proven build-headless workflow.
SKIP=(
    src/external/cups
    src/external/dbuskit
    src/external/WTF
    src/external/bmalloc
    src/external/JavaScriptCore
    src/external/WebCore
    src/external/python
    src/external/python_modules
    src/external/pyobjc
    src/external/ruby
    src/external/perl
    src/external/metal
    src/external/openjdk
    src/external/glut
    src/external/OpenAL
    src/external/TextEdit
    src/external/swift
    src/external/iokitd
    src/external/libffi
    src/external/libressl-2.2.9
    src/external/libressl-2.5.5
    src/external/libressl-2.6.5
)

echo "==> Initializing submodules (skipping headless-irrelevant ones)..."
mapfile -t ALL < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
KEEP=()
for path in "${ALL[@]}"; do
    skip=0
    for s in "${SKIP[@]}"; do
        if [[ "$path" == "$s" ]]; then skip=1; break; fi
    done
    (( skip == 0 )) && KEEP+=("$path")
done
echo "    initializing ${#KEEP[@]} of ${#ALL[@]} submodules (skipping ${#SKIP[@]})"
git submodule update --init --depth=1 --recursive --jobs=8 -- "${KEEP[@]}"

# === Configure & build the darlingserver target ===
# No CMAKE_BUILD_TYPE on purpose: Release made Clang emit chained-fixup
# relocations that cctools-port ld64 cannot read, breaking dyld linkage.
# Upstream's debian/rules also builds with empty config.
echo "==> Configuring (cmake -DCOMPONENTS=cli, no Swift, no legacy LibreSSL)..."
mkdir -p build
cd build
cmake .. \
    -DCOMPONENTS=cli \
    -DTARGET_i386=OFF \
    -DBUILD_SWIFT=OFF \
    -DBUILD_LEGACY_LIBRESSL=OFF

echo "==> Building darlingserver target..."
make -j"$(nproc)" darlingserver

# Find the built binary
DARLINGSERVER_BIN=$(find . -name darlingserver -type f -executable | head -1)
if [ -z "$DARLINGSERVER_BIN" ]; then
    echo "ERROR: darlingserver binary not found after build"
    exit 1
fi

# === Install into the rootfs ===
echo "==> Installing darlingserver to ${ROOTFS}/usr/sbin/..."
install -d "${ROOTFS}/usr/sbin"
install -m 0755 "${DARLINGSERVER_BIN}" "${ROOTFS}/usr/sbin/darlingserver"

# Cleanup the build tree so the container image layer stays small.
# This is in the same Dockerfile RUN as the build, so the layer size
# reflects only the post-rm state (just the rootfs binary).
cd /
rm -rf "${BUILD_DIR}"

ls -lh "${ROOTFS}/usr/sbin/darlingserver"
echo "==> darlingserver built and installed."
