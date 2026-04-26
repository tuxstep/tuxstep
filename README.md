# TuxSTEP

A Linux distribution whose userspace is intended to become a direct descendant of NeXTSTEP — built from GNUstep + Gershwin + curated Apple open-source components.

## Status

**Phase 0**: minimal bootable Devuan-based live ISO for amd64 + arm64. No NeXTSTEP userland yet — this exists to validate the CI pipeline. Subsequent phases layer on the four-domain Gershwin filesystem layout, GNUstep + Gershwin, then Apple OSS components, then launchd as PID 1.

## Build

CI builds amd64 + arm64 ISOs on every push to `main` and uploads them to the `continuous` release tag.

To build locally on a Devuan or Debian host with build deps installed:

```sh
sudo ./build.sh
```

Build deps: `debootstrap squashfs-tools xorriso mtools dosfstools grub-pc-bin grub-efi-amd64-bin grub-efi-arm64-bin`. The `ci/containers/Dockerfile` is the authoritative dep list.

## Default credentials

The phase 0 live ISO ships with `root:tuxstep`. Replace before deploying anywhere reachable.

## License

BSD 2-clause. See `LICENSE`.
