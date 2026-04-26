# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================================
# Build-side tools (used during container build, also stay in the image so
# the ISO-build job can run mksquashfs/GRUB/xorriso from the container)
# =========================================================================

# Bootstrap Devuan keyring so mmdebstrap can verify package signatures.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && echo "deb http://deb.devuan.org/merged excalibur main" > /etc/apt/sources.list.d/devuan.list \
 && apt-get -o Acquire::AllowInsecureRepositories=true update \
 && apt-get -o APT::Get::AllowUnauthenticated=true install -y --no-install-recommends devuan-keyring \
 && apt-get update

RUN apt-get install -y --no-install-recommends \
        mmdebstrap \
        squashfs-tools \
        xorriso \
        mtools \
        dosfstools \
        grub-common \
        grub2-common \
        wget \
        git \
        xz-utils \
        zstd \
        cmake \
        build-essential \
        passwd

RUN if [ "$TARGETARCH" = "amd64" ]; then \
        apt-get install -y --no-install-recommends \
            grub-pc-bin grub-efi-amd64-bin; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        apt-get install -y --no-install-recommends \
            grub-efi-arm64-bin; \
    fi \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# =========================================================================
# Build the Devuan rootfs at /rootfs
# =========================================================================
# mmdebstrap is the unprivileged-friendly debootstrap replacement. We use
# --mode=root with `RUN --security=insecure` (BuildKit) so it can mount
# /proc /sys /dev inside the rootfs to run package maintainer scripts.
# Requires the buildx daemon to allow security.insecure entitlement
# (configured in the workflow).

COPY packages.list /tmp/packages.list

RUN --security=insecure <<EOT bash
set -ex
case "$TARGETARCH" in
    amd64) HOST_ARCH=x86_64 ;;
    arm64) HOST_ARCH=aarch64 ;;
esac
cp /tmp/packages.list /tmp/packages.list.tmp
sed -i "s/^#\${HOST_ARCH} //g" /tmp/packages.list.tmp
PACKAGES=\$(grep -v '^#' /tmp/packages.list.tmp | grep -v '^\$' | tr '\n' ',' | sed 's/,\$//')
rm /tmp/packages.list.tmp /tmp/packages.list

mmdebstrap \
    --variant=minbase \
    --architectures="$TARGETARCH" \
    --include="\$PACKAGES" \
    --components=main \
    excalibur \
    /rootfs \
    http://deb.devuan.org/merged
EOT

# =========================================================================
# Configure the rootfs (apt sources, hostname, sshd, root password)
# =========================================================================

RUN <<EOT bash
set -ex
cat > /rootfs/etc/apt/sources.list <<APT
deb http://deb.devuan.org/merged excalibur main non-free-firmware
deb http://deb.devuan.org/merged excalibur-security main non-free-firmware
deb http://deb.devuan.org/merged excalibur-updates main non-free-firmware
deb http://deb.devuan.org/merged excalibur-backports main non-free-firmware
APT
echo "tuxstep" > /rootfs/etc/hostname
echo 'root:tuxstep' | chpasswd --root /rootfs
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /rootfs/etc/ssh/sshd_config
EOT

# =========================================================================
# Darling build deps + runtime build
# =========================================================================
# We use the monorepo build pattern (clone darlinghq/darling, rewrite
# .gitmodules to point at our 4 forks where applicable, init only headless-
# relevant submodules, build with -DCOMPONENTS=cli). See
# ci/build/build-darling.sh for details and rationale.

# Apt deps required by Darling's build (matches xnulinux/darling's known-
# working set). gcc-multilib is amd64-only; arm64 has no multilib for x86_64.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        clang \
        bison \
        flex \
        pkg-config \
        libfuse-dev \
        libudev-dev \
        libxml2-dev \
        libelf-dev \
        libcap2-bin \
        libbsd-dev \
        libdbus-1-dev \
        libssl-dev \
        python3 \
        libstdc++-12-dev \
        linux-libc-dev \
        dpkg-dev \
        ccache \
 && if [ "$TARGETARCH" = "amd64" ]; then \
        apt-get install -y --no-install-recommends gcc-multilib; \
    fi \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Build Darling from source and install darlingserver into /rootfs/usr/sbin/.
# The whole monorepo (~5-10 GB during build) is cleaned up at the end of the
# RUN, so the layer adds only the size of the installed binary.
COPY ci/build/build-darling.sh /tmp/build-darling.sh
RUN chmod +x /tmp/build-darling.sh \
 && WORK=/tmp/dwork ROOTFS=/rootfs /tmp/build-darling.sh \
 && rm -rf /tmp/dwork /tmp/build-darling.sh

WORKDIR /work
