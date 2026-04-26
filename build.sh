#!/bin/sh
set -e

# The build container at ghcr.io/tuxstep/tuxstep-build-<arch>:<tag> has the
# prepared Devuan rootfs at /rootfs (built via mmdebstrap during container
# build), with darlingserver pre-installed at /rootfs/usr/sbin/. This script
# packages /rootfs into a bootable hybrid ISO. No debootstrap, no apt-install,
# no chroot — that all happened at container-build time.

# === Configuration ===
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    x86_64|i?86) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $HOST_ARCH"; exit 1 ;;
esac
WORK="$(pwd)/work"
ISO_NAME="tuxstep-$(date +%Y.%m.%d)-${HOST_ARCH}.iso"

if [ ! -d /rootfs ]; then
    echo "ERROR: /rootfs not found in container — Dockerfile must build it"
    exit 1
fi

rm -rf "${WORK}"
mkdir -p "${WORK}/iso/live"

# === Step 1: Copy kernel + initramfs out of the rootfs ===
echo "==> Copying kernel and initramfs from /rootfs/boot..."
cp /rootfs/boot/vmlinuz-* "${WORK}/iso/live/vmlinuz"
cp /rootfs/boot/initrd.img-* "${WORK}/iso/live/initrd.img"

# === Step 2: Pack the rootfs as a squashfs ===
# zstd is ~10x faster than xz for ~10% larger output. Worth it on the GHA
# 4-core runners where xz takes 5-10 min and zstd takes <1.
echo "==> Creating squashfs (zstd)..."
mksquashfs /rootfs "${WORK}/iso/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 19 \
    -e boot/vmlinuz-* -e boot/initrd.img-*

# === Step 3: Setup GRUB ===
echo "==> Setting up GRUB..."
mkdir -p "${WORK}/iso/boot/grub"
cp grub.cfg "${WORK}/iso/boot/grub/grub.cfg"

if [ "$ARCH" = "amd64" ]; then
    # --- x86_64: BIOS + UEFI hybrid ---
    grub-mkstandalone \
        --format=i386-pc \
        --output="${WORK}/bios.img" \
        --install-modules="linux normal iso9660 biosdisk memdisk search tar ls all_video font gfxterm part_gpt part_msdos" \
        --modules="linux normal iso9660 biosdisk search part_gpt part_msdos" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${WORK}/iso/boot/grub/grub.cfg"

    cat /usr/lib/grub/i386-pc/cdboot.img "${WORK}/bios.img" > "${WORK}/iso/boot/grub/bios.img"

    grub-mkstandalone \
        --format=x86_64-efi \
        --output="${WORK}/bootx64.efi" \
        --install-modules="linux normal iso9660 search tar ls all_video font gfxterm part_gpt part_msdos fat efi_gop efi_uga" \
        --modules="linux normal iso9660 search part_gpt part_msdos fat efi_gop" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${WORK}/iso/boot/grub/grub.cfg"

    mkdir -p "${WORK}/iso/EFI/boot"
    cp "${WORK}/bootx64.efi" "${WORK}/iso/EFI/boot/bootx64.efi"

    dd if=/dev/zero of="${WORK}/iso/boot/grub/efi.img" bs=1M count=4 2>/dev/null
    mkfs.vfat "${WORK}/iso/boot/grub/efi.img"
    mmd -i "${WORK}/iso/boot/grub/efi.img" EFI EFI/boot
    mcopy -i "${WORK}/iso/boot/grub/efi.img" "${WORK}/bootx64.efi" ::EFI/boot/bootx64.efi

    echo "==> Building ISO (BIOS+UEFI)..."
    xorriso -as mkisofs \
        -R -J -joliet-long \
        -V "TUXSTEP" \
        -partition_offset 16 \
        -b boot/grub/bios.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            --grub2-boot-info \
            --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
            -no-emul-boot \
        -append_partition 2 0xef "${WORK}/iso/boot/grub/efi.img" \
        -appended_part_as_gpt \
        -o "${ISO_NAME}" \
        "${WORK}/iso"

elif [ "$ARCH" = "arm64" ]; then
    # --- ARM64: UEFI only ---
    grub-mkstandalone \
        --format=arm64-efi \
        --output="${WORK}/bootaa64.efi" \
        --install-modules="linux normal iso9660 search tar ls all_video font gfxterm part_gpt part_msdos fat efi_gop" \
        --modules="linux normal iso9660 search part_gpt part_msdos fat efi_gop" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${WORK}/iso/boot/grub/grub.cfg"

    mkdir -p "${WORK}/iso/EFI/boot"
    cp "${WORK}/bootaa64.efi" "${WORK}/iso/EFI/boot/bootaa64.efi"

    dd if=/dev/zero of="${WORK}/iso/boot/grub/efi.img" bs=1M count=4 2>/dev/null
    mkfs.vfat "${WORK}/iso/boot/grub/efi.img"
    mmd -i "${WORK}/iso/boot/grub/efi.img" EFI EFI/boot
    mcopy -i "${WORK}/iso/boot/grub/efi.img" "${WORK}/bootaa64.efi" ::EFI/boot/bootaa64.efi

    echo "==> Building ISO (UEFI only)..."
    xorriso -as mkisofs \
        -R -J -joliet-long \
        -V "TUXSTEP" \
        -e boot/grub/efi.img \
            -no-emul-boot \
        -append_partition 2 0xef "${WORK}/iso/boot/grub/efi.img" \
        -appended_part_as_gpt \
        -o "${ISO_NAME}" \
        "${WORK}/iso"
fi

echo "==> Done: ${ISO_NAME}"
ls -lh "${ISO_NAME}"
