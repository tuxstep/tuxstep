#!/bin/sh
set -ex

# Build tuxstep/darlingserver as an ELF Linux daemon and install into the
# rootfs at /usr/sbin/darlingserver.
#
# Called from the build container's Dockerfile at container-build time, with
# WORK pointing at a scratch dir and ROOTFS pointing at /rootfs (the rootfs
# being prepared inside the container image).
#
# darlingserver isn't standalone-buildable: its internal duct-tape lib
# PUBLICly links libsimple_darlingserver, which is defined in src/libsimple/
# of the Darling monorepo (one .c file, lock.c, plus headers). We vendor that
# subdir at a pinned monorepo tag and build them together via a small wrapper
# CMakeLists.txt.
#
# Required env: ROOTFS — path to the rootfs to install into.
# Optional env: WORK   — work dir (default: $PWD/work)

: "${ROOTFS:?ROOTFS env var required (path to rootfs to install into)}"

WORK="${WORK:-$(pwd)/work}"
BUILD_DIR="${WORK}/build-darlingserver"

DARLINGSERVER_REPO="https://github.com/tuxstep/darlingserver.git"
DARLINGSERVER_SHA="89751e64bc6c2082f7725061824ee0e33395b0de"

DARLING_MONO_REPO="https://github.com/darlinghq/darling.git"
DARLING_MONO_TAG="v0.1.20260222"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# 1. Clone darlingserver at the pinned SHA
echo "==> Cloning darlingserver..."
git clone "${DARLINGSERVER_REPO}" "${BUILD_DIR}/darlingserver"
( cd "${BUILD_DIR}/darlingserver" && \
  git -c advice.detachedHead=false checkout "${DARLINGSERVER_SHA}" )

# 2. Pull libsimple from the Darling monorepo at the pinned release tag.
#    Shallow clone, copy out src/libsimple, throw the rest away.
echo "==> Vendoring libsimple from Darling monorepo at ${DARLING_MONO_TAG}..."
git clone --depth=1 --branch "${DARLING_MONO_TAG}" \
    "${DARLING_MONO_REPO}" "${BUILD_DIR}/.darling-mono"
cp -r "${BUILD_DIR}/.darling-mono/src/libsimple" "${BUILD_DIR}/libsimple"
rm -rf "${BUILD_DIR}/.darling-mono"

# 3. Wrapper CMakeLists.txt that builds libsimple_darlingserver first, then
#    darlingserver. libsimple's CMakeLists in standalone-Linux mode (i.e.
#    libsimple_linux_added not yet set) creates the libsimple_darlingserver
#    static library that darlingserver_duct_tape PUBLICly links.
cat > "${BUILD_DIR}/CMakeLists.txt" << 'EOF'
cmake_minimum_required(VERSION 3.13)
project(tuxstep-darlingserver-spike)

add_subdirectory(libsimple)
add_subdirectory(darlingserver)
EOF

# 4. Configure + build
echo "==> Configuring + building darlingserver..."
mkdir -p "${BUILD_DIR}/build"
( cd "${BUILD_DIR}/build" && cmake .. )
make -C "${BUILD_DIR}/build" -j"$(nproc)"

# 5. Install the binary into the rootfs
echo "==> Installing darlingserver to ${ROOTFS}/usr/sbin/..."
install -d "${ROOTFS}/usr/sbin"
install -m 0755 \
    "${BUILD_DIR}/build/darlingserver/darlingserver" \
    "${ROOTFS}/usr/sbin/darlingserver"

ls -lh "${ROOTFS}/usr/sbin/darlingserver"
echo "==> darlingserver built and installed."
