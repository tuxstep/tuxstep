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
# Build & install Darling runtime: darlingserver into /rootfs/usr/sbin/
# =========================================================================

COPY ci/build/sources/darlingserver.sh /tmp/build-darlingserver.sh
RUN chmod +x /tmp/build-darlingserver.sh \
 && WORK=/tmp/dswork ROOTFS=/rootfs /tmp/build-darlingserver.sh \
 && rm -rf /tmp/dswork /tmp/build-darlingserver.sh

WORKDIR /work
