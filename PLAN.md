# TuxSTEP — Master Plan

This document is the source of truth for TuxSTEP's architecture, scope, and phase plan. When in doubt, this overrides any other documentation in the repo. Last revised 2026-04-26.

## Project identity

TuxSTEP is a modern NeXT-inspired operating system distribution built on top of the Linux kernel, with an entirely Apple-derived userland. The Linux kernel provides hardware support and ecosystem reach; everything from PID 1 upward is libsystem-linked Apple/Darwin code, supplemented by the GNUstep frameworks (via Gershwin) for Cocoa-style application development.

While TuxSTEP doesn't run prebuilt Mach-O binaries, its **source-level compatibility with macOS is unmatched among Linux distributions**. Apple's libsystem provides BSD APIs (`kqueue`, `kevent`, `mach_absolute_time`, FSEvents-style file watching, NeXT-style signal numbering) that Linux glibc lacks; Apple's headers install at `/System/Library/Headers/`; the GNUstep stack provides source-compatible Cocoa frameworks; and the filesystem layout matches macOS conventions. A macOS application's source typically compiles and runs on TuxSTEP with far fewer patches than on any other Linux system — the porting tax that normally accompanies "Linuxify this Mac code" largely disappears.

**What TuxSTEP is:**

- A Linux distribution where the userspace is Apple's open-source userland
- A NeXT-inspired filesystem and design model (`/System`, `/Network`, `/Local`, `/Volumes`)
- A foundation for Cocoa-style application development on Linux hardware
- Rooted in Apple's libsystem as the system libc, not glibc

**What TuxSTEP is not:**

- Not a macOS binary runner. No mldr, no dyld, no Mach-O execution path.
- Not a Darling fork. We do not aim to run prebuilt brew bottles or MacPorts binaries.
- Not a Mac OS X clone. The aesthetic is NeXT-inspired, not bug-for-bug Apple-compatible.
- Not "Linux with Apple themes." The userland is genuinely Apple-derived source code, recompiled for Linux.

The core rejected goal — running unmodified Mach-O binaries — is settled and not subject to relitigation.

## Architectural decisions

These are locked. Changing any of them requires a new revision of this document.

| # | Decision | Rationale |
|---|---|---|
| 1 | Format: ELF everywhere | Linux kernel is the loader; Mach-O execution would require maintaining mldr+dyld+binfmt forever for no benefit |
| 2 | Libc: Apple libsystem (ELF) is the system libc | libsystem is the project identity. glibc is not present in v0.1 — the userland is libsystem-linked end to end |
| 3 | Obj-C runtime: libobjc2 | Modern, arm64-clean, already maintained by GNUstep; we avoid Apple-objc4 ABI complexity |
| 4 | Foundation/runtime stack: GNUstep via Gershwin | libdispatch, libobjc2, tools-make, libs-base, libs-corebase — installed at `/System/Library/Libraries/` and `/System/Library/Makefiles/` |
| 5 | Mach IPC: deferred to v0.2 | v0.1 has no daemons that need it; libsimple_darlingserver and darlingserver come back later |
| 6 | Init: deferred to v0.2 | v0.1 boots to single-user zsh as PID 1 directly. launchd port is post-v0.1. |
| 7 | Coreutils: Apple BSD-derived | file_cmds, shell_cmds, system_cmds, network_cmds, text_cmds — installed at `/System/Library/Tools/` |
| 8 | Filesystem layout: Gershwin/NeXT | Four real top-level directories (`/System`, `/Network`, `/Local`, `/Volumes`). All system-internal Unix infrastructure (etc, var, tmp, dev, sys, kernel images, firmware, modules) lives under `/System/Library/`. No `/etc`, `/var`, `/tmp`, `/dev`, `/sys`, `/boot`, `/lib`, `/usr`, `/bin`, `/sbin`, `/Users`, `/home`, `/private` at root. |
| 9 | Apple source: vendored unmodified, build-time patched | Apple-OSS lives as git submodules per component repo; never edited in place. Linux-specific code lives in parallel `linux-glue/` directories. A focused `patches/` series is applied at build time for two purposes: (1) replacing path constants in `<paths.h>` to point at `/System/Library/Private/...`, (2) rewriting any direct path-string literals in Apple source. Sync remains `git submodule update`; patches reapplied at next build. |
| 10 | Syscall stubs: generated from a table | One source-of-truth `syscall_table.txt` drives all libsystem_kernel stub generation; minimizes hand-maintained code |
| 11 | Bootloader: `tuxstep/grub` (forked from upstream GRUB) | GRUB is the only mainstream bootloader that handles BIOS (i386, amd64) and UEFI (i386, amd64, arm64) from a single codebase. We fork upstream GNU GRUB into `tuxstep/grub` to add TuxSTEP-specific behavior: silent boot by default, Mac-style boot-key shortcuts (cmd-V for verbose boot, cmd-S for single-user mode, option/alt to pick boot volume, shift for safe-boot, C to boot from CD, etc., mapped to physical keys appropriate to each arch's keyboard), TuxSTEP-styled boot screen, and any patches needed for the chainloader-on-hidden-ESP layout. Per-arch GRUB binaries are built once (grub-pc, grub-efi-ia32, grub-efi-amd64, grub-efi-arm64) and shipped on every TuxSTEP ISO. On UEFI: a 5 MB FAT32 ESP holds a thin GRUB stub. On BIOS: GRUB stage 1 in MBR, stage 1.5 in BIOS-boot partition. Kernel built with `CONFIG_EFI_STUB=y` for UEFI archs so the kernel image is itself a valid EFI binary; BIOS path uses standard kernel + initramfs loading. The actual boot artifacts always live at `/System/Library/Boot/` on the ext4 partition; the ESP / BIOS-boot region only contains the chainloader stub. |
| 12 | KMS drivers built into kernel for v0.1 | No userspace module-loading infrastructure needed. Trade ~30-50MB on the kernel image for a vastly simpler v0.1 userland. |
| 13 | Base distribution: none | We do not derive from Devuan, Debian, or any Linux distribution at runtime. Devuan may be used as a build host to cross-compile; the resulting ISO contains zero Devuan binaries. |
| 14 | /System is the OS — drag-and-drop deployable | Copying `/System` to a volume makes that volume bootable, automatically. An auto-bless daemon detects when `/System/Library/Boot/kernel.efi` (or `/System/Library/Boot/kernel` for BIOS) is written to a volume and silently performs whatever partition surgery is needed (creating a hidden ESP and/or BIOS-boot region, installing the GRUB chainloader, updating bootloader config). The drag-and-drop operation itself is non-destructive of existing user data; failure modes are non-corrupting. Classic-Mac-style: format the disk once however you like, drag `/System` to it, the disk becomes bootable. |
| 15 | Supported architectures: i386 + amd64 + arm64 — required, not optional | Three CPU architectures supported from v0.1. amd64 + arm64 track current Apple-OSS releases. i386 pins to an older Apple-OSS release that still contains full 32-bit code paths (macOS Mojave 10.14 source drops, ~2018) and is maintained as a separate pin in `tuxstep/libsystem-linux`. The i386 build is a first-class deliverable on equal footing with amd64 and arm64; it is not deferrable. The bootloader (GRUB) and auto-bless workflow are arch-independent: same tooling, same drag-and-drop UX on all three archs. The TuxSTEP ISO matrix is i386 + amd64 + arm64; CI gates green on all three. |
| 16 | Filesystem: ext4 | The `/System` partition is ext4. Chosen for: mature Linux kernel support, crash-safe journaling, mature shrink/resize tooling (`resize2fs`) which the auto-bless daemon depends on for non-destructive partition surgery. HFS+ was considered (better aesthetic match for Apple-flavored userland) but rejected because Linux's HFS+ driver is rougher around the edges and shrink tooling is less reliable. The filesystem is invisible from any user-facing surface; aesthetic energy is spent elsewhere (UTI integration, xattr-based resource forks, NeXT-style format command naming) without sacrificing the technical foundation. |

## Filesystem layout (v0.1 ISO root)

Four real directories at root. No symlinks. Everything system-internal lives under `/System/Library/`. More pure than NeXTSTEP itself was.

```
/                                       ISO root
│
├── System/                              the entire OS
│   └── Library/
│       ├── Kernels/<kver>/              kernel image, initramfs
│       ├── Firmware/                    firmware blobs (was /lib/firmware)
│       ├── Modules/<kver>/              kernel modules (post-v0.1; empty in v0.1)
│       ├── Libraries/                   libSystem.so, libobjc2.so, libdispatch.so,
│       │                                libgnustep-base.so, libgnustep-corebase.so
│       ├── Headers/                     Apple + GNUstep headers
│       ├── Tools/                       Apple BSD coreutils, zsh, cc, ld, ar, ...
│       ├── Makefiles/                   gnustep-make
│       └── Private/                     system-internal Unix infrastructure
│           ├── etc/                     passwd, hosts, fstab, ...
│           ├── var/                     logs, state, spool
│           ├── tmp/                     temp files (tmpfs at runtime)
│           ├── dev/                     devtmpfs mount point
│           └── sys/                     sysfs mount point (post-v0.1)
│
├── Network/                             site-wide / NFS-mounted (empty in v0.1)
│   ├── Applications/, Library/, Users/
│
├── Local/                               per-machine sysadmin (empty in v0.1)
│   ├── Applications/, Library/, Users/
│
└── Volumes/                             mounted external media
```

**No `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/boot`, `/home`, `/Users`, `/etc`, `/var`, `/tmp`, `/dev`, `/sys`, `/proc`, `/run`, `/mnt`, `/opt`, `/private` at root.** Apple's libsystem and downstream Apple-OSS components are patched at build time so their hardcoded path constants (`_PATH_DEVNULL`, `_PATH_PASSWD`, etc.) and direct string literals point at `/System/Library/Private/...`. Patches live per-component in `patches/` directories; the vendored submodules themselves remain untouched.

User homes (post-v0.1 multi-user support) live under `/Local/Users/<name>` for interactive users and `/Network/Users/<name>` for NFS-mounted users, following Gershwin's NeXT-style convention. There is no top-level `/Users`.

## Boot chain (v0.1)

The disk is laid out as two GPT partitions:

```
Disk:
├── Partition 1: FAT32 ESP, 5 MB, hidden    (chainloader stub only — never auto-mounted)
└── Partition 2: ext4, rest of disk
    └── /System/...                          (entire OS)
```

Boot sequence:

1. **UEFI firmware** reads partition 1 (the hidden ESP) and executes `\EFI\BOOT\BOOTX64.EFI` (or `BOOTAA64.EFI` on arm64). This is a thin GRUB or rEFInd stub (~1-3 MB) that knows how to read ext4.
2. **Stub bootloader** reads its config (which references partition 2 by UUID) and executes `/System/Library/Boot/kernel.efi`.
3. **Linux kernel** (built with `CONFIG_EFI_STUB=y`, so the kernel image *is* an EFI binary) boots from there. KMS drivers built into the kernel come up automatically; framebuffer console renders at native resolution.
4. **initramfs** (small, transient — embedded in the kernel image or loaded as a separate file from `/System/Library/Boot/initramfs`) mounts the squashfs/ext4 root, mounts the kernel-managed filesystems at their `/System/Library/Private` locations:
   - `mount -t devtmpfs devtmpfs /System/Library/Private/dev`
   - `mount -t sysfs sysfs /System/Library/Private/sys` (only if needed; v0.1 may skip)
   - `mount -t tmpfs tmpfs /System/Library/Private/tmp`
   - `mount -t tmpfs tmpfs /System/Library/Private/var/run`
5. **PID 1 = `/System/Library/Tools/zsh`** directly. No init system, no service supervisor, no auth chain. The user is at a `#` prompt as root.

`CONFIG_DEVTMPFS_MOUNT=n` in the kernel config — we mount devtmpfs at the deep path explicitly rather than letting the kernel auto-mount at `/dev`. There is no `/dev` directory at the squashfs root.

The 5 MB FAT32 ESP is hidden by partition flags and never appears in `ls /`, `mount`, or `df` output — it's plumbing required by UEFI firmware, not part of the running system. After initial setup, kernel updates only write to `/System/Library/Boot/` on the ext4 partition; the ESP itself is touched once at install and never again.

When the user types `exit`, the kernel panics with "Attempted to kill init" — expected behavior for a shell-as-PID-1 system. Power off via the syscalls `reboot(2)` / `halt(2)` directly, or via Apple's `reboot` and `halt` commands (which call those syscalls).

## Phase plan to v0.1

| Phase | Component | Estimate |
|---|---|---|
| 0 | `tuxstep/libsystem-linux` — Apple libsystem ported to ELF | 4-6 months |
| 1 | Bootstrap toolchain — clang + lld rebuilt against libsystem; Apple headers at `/System/Library/Headers/` | 3-4 months |
| 2 | Apple BSD coreutils + zsh ported to libsystem | 3-4 months |
| 3 | `mount`, `umount`, `fsck.ext4` ports (small subset, just enough for ISO) | 2-3 weeks |
| 4 | Gershwin stack rebuilt against libsystem (libobjc2, libdispatch, tools-make, libs-base, libs-corebase) | 1-2 months |
| 5 | Kernel config + initramfs + ISO assembly with chainloader-on-hidden-ESP layout | 1-2 months |

Post-v0.1 (informational; not part of v0.1 timeline):

| Phase | Component |
|---|---|
| 6 | `newfs`, `bless`, auto-bless daemon — drag-and-drop deployment model |
| 7 | launchd as PID 1 + login chain + multi-user |
| 8 | darlingserver + libsimple_darlingserver (Mach IPC for ELF callers) |
| 9 | Display server, libs-gui rebuilt against libsystem, Eau, Workspace.app |

**Total to v0.1: roughly 10-13 months of focused work.**

### Phase 0 — `tuxstep/libsystem-linux`

The foundational repository. Vendors apple-oss-distributions submodules unmodified:

- `Libc`
- `libplatform`
- `libpthread`
- `libmalloc`
- `libclosure`
- `libdispatch`

Adds a `linux-glue/` directory containing:

- `kernel/syscall_table.txt` — hand-maintained mapping of Apple syscalls to Linux syscalls
- `kernel/syscall_stubs.S` — generated from the table by `scripts/gen_syscall_stubs.py`
- `kernel/struct_*.c` — manual translators for `stat`, `dirent`, `sigaction`, `rusage`, etc.
- `kernel/signal_remap.c` — Apple↔Linux signal number mapping
- `kernel/errno_remap.c` — Apple↔Linux errno mapping
- `compat/apple_only_stubs.c` — `ENOSYS` returns for Apple-only APIs

Adds a `patches/` directory containing build-time patches against Apple-OSS:

- `0001-paths-h-redirect-to-system-library-private.patch` — replaces every `_PATH_*` macro in `<paths.h>` to point at `/System/Library/Private/...`
- `00NN-libc-direct-literal-*.patch` — patches each direct path literal in libc source (`fopen("/etc/passwd")` → `fopen("/System/Library/Private/etc/passwd")`, etc.)

Patches are applied at build time after `git submodule update`; the vendored submodules themselves are never modified. A `scripts/audit_paths.sh` enumerates direct path literals so new patches can be authored mechanically when Apple introduces them upstream.

Output: `/System/Library/Libraries/libSystem.so`. Installed alongside the constituent libraries.

Day-1 milestone: a hello-world C program compiles against libsystem and prints via `write(2)`. Validates: zero references to `/dev`, `/etc`, `/var`, `/tmp` outside `/System/Library/Private/` in the produced binary's strings table.

### Phase 1 — Bootstrap toolchain

Cross-compile clang + LLVM (or just llvm-project's clang-bootstrap) to produce libsystem-linked binaries. Establishes:

- `/System/Library/Tools/cc` — clang against libsystem
- `/System/Library/Tools/ld` — lld
- `/System/Library/Tools/ar`, `as`, `ranlib` — LLVM tools
- `/System/Library/Headers/` — Apple's headers from xnu/Libc/etc., plus GNUstep headers

Self-hosted: the toolchain can rebuild itself on a libsystem system.

Validate: a hello-world Obj-C program compiles using only `/System/Library/Tools/cc`, links only against `/System/Library/Libraries/libSystem.so`.

### Phase 2 — Apple BSD coreutils + zsh

Port apple-oss-distributions:

- `file_cmds` (ls, cp, mv, rm, ln, cat, mkdir, rmdir, chmod, chown, find, etc.)
- `shell_cmds` (echo, env, kill, ps, sleep, test, printf, true, false, etc.)
- `system_cmds` (sysctl, mount, umount, ifconfig, hostname, etc.)
- `text_cmds` (grep, sed, awk-equivalent, head, tail, sort, uniq, cut, etc.)
- `network_cmds` (ifconfig, netstat, ping, route)
- `zsh` (Apple's port; PID 1 in v0.1)

All installed at `/System/Library/Tools/`. The shell's `$PATH` is just `/System/Library/Tools`.

### Phase 3 — Filesystem tooling

Just enough to mount and check the ISO's root filesystem:

- `mount` (port from apple-oss/system_cmds)
- `umount`
- `fsck.ext4` (port from FreeBSD or fresh-write — small)

Defer everything else (`mkfs`, `lvm`, `cryptsetup`, etc.) to v0.2.

### Phase 4 — Gershwin stack rebuilt against libsystem

Patch each upstream to compile against libsystem instead of glibc:

- `libobjc2` (modern Obj-C runtime)
- `libdispatch` (Apple's GCD; already largely portable)
- `tools-make` (gnustep-make)
- `libs-base` (Foundation)
- `libs-corebase` (CoreFoundation analog)

Each gets a `__TUXSTEP_LIBSYSTEM__` build target. Patches go into a parallel `linux-glue/` tree per component, never modifying upstream Gershwin source.

Result: `/System/Library/Tools/cc -ObjC -lSystem -lobjc2 -ldispatch -lgnustep-base hello.m -o hello` works.

### Phase 5 — ISO assembly

- Build kernel from `kernel.org` upstream with a focused `.config`: KMS drivers built in, framebuffer console, common storage/networking, ext4/isofs/squashfs, `CONFIG_DEVTMPFS_MOUNT=n` (we mount it explicitly at `/System/Library/Private/dev`), `CONFIG_EXTRA_FIRMWARE_DIR="/System/Library/Firmware"`
- Compose initramfs (transient; mounts squashfs, mounts kernel-managed filesystems at `/System/Library/Private/{dev,sys,tmp,var/run}`, pivots, exec's PID 1)
- Compose squashfs root according to the layout above (four real top-level dirs: `/System`, `/Network`, `/Local`, `/Volumes`; no compat symlinks)
- GRUB stage on hidden 5 MB FAT32 ESP (UEFI) and/or BIOS-boot region (legacy BIOS); `grub.cfg` references `/System/Library/Boot/kernel.efi` (UEFI) or `/System/Library/Boot/kernel` + initramfs (BIOS) on the ext4 partition
- ISO build pipeline producing **i386, amd64, and arm64 images** (all three are required v0.1 deliverables; CI gates on all three turning green simultaneously)

## Volume management — drag-and-drop deployment

TuxSTEP's deployment model is classic-Mac: **`/System` is the OS. Drag it to a volume, the volume becomes bootable.** Three tools support this, all post-v0.1 deliverables:

**`newfs <disk>`** — convenience tool to format a disk for TuxSTEP (creates the layout: 5 MB hidden FAT32 ESP + ext4 spanning the rest, pre-installs the chainloader on the ESP). Destructive of any existing data on the disk, like any format command. Optional — disks formatted by other means also work, the auto-bless daemon handles the partition surgery on the fly.

**`bless <volume>`** — explicit command to make a volume bootable. Inspects the volume's partition layout; if no ESP exists, creates one (non-destructively shrinks the ext4 partition by 5 MB if necessary using `resize2fs`, then carves out an ESP partition). Installs the chainloader, writes the bootloader config to reference `/System/Library/Boot/kernel.efi` on the ext4 partition. User-explicit; for users who want to bless without copying.

**Auto-bless daemon** (launchd-managed post-v0.1) — watches mounted volumes via `fanotify` for `/System/Library/Boot/kernel.efi` being written. When detected, performs the same logic as `bless` automatically and silently:
- If the volume already has an ESP (TuxSTEP-formatted), updates the bootloader config inside it. Non-destructive, no partition table changes.
- If the volume has no ESP but has free space at the start, reorganizes the partition table to declare an ESP region and installs the chainloader. Non-destructive of data.
- If the volume needs an ext4 shrink to make room, runs `resize2fs` on the unmounted partition. Non-destructive of data, takes a few seconds on near-empty disks.
- If the volume is 100% full and can't be shrunk, logs a notice and stops. The user's data is preserved; the disk just doesn't auto-bless. They can free space and the next `/System` write triggers a retry.

The user-visible workflow is:

```
$ cp -aR /System /Volumes/NewDisk/    # this is the only command the user ever needs
$                                     # disk is now bootable
```

No format step required (auto-bless handles partition surgery). No bless command required (auto-bless does it). Like classic Mac: drag the System Folder, the disk is ready.

**Cross-arch:** the same auto-bless daemon and same workflow apply to **i386, amd64, and arm64**. Each `/System` tree is per-arch (binaries can't cross archs), so users pick the right `/System` build for the target machine. The tooling is identical across all three archs; the contents differ. Bless logic adapts to the firmware mode it detects:
- **UEFI volumes** (modern amd64, arm64): bless creates/updates the hidden 5 MB FAT32 ESP and writes the chainloader.
- **BIOS volumes** (legacy i386, amd64): bless installs GRUB stage 1 to the MBR and stage 1.5 to a BIOS-boot region or post-MBR gap. No FAT32 ESP needed in pure-BIOS deployments.
- **Hybrid volumes** (amd64 with both BIOS and UEFI firmware support): bless installs both, allowing the same disk to boot in either firmware mode.

**Post-v0.1 deliverable.** v0.1 ships a `dd`-able hybrid ISO (no auto-bless needed — the ISO is its own pre-blessed image). The auto-bless daemon, `newfs`, and `bless` come in v0.2 alongside launchd, when the system has the daemon infrastructure to support background services.

## v0.1 demo

Boot the ISO. GRUB menu appears. Kernel boots; KMS detects the GPU and brings up the framebuffer console at native resolution. Squashfs mounts. PID 1 is zsh.

```
# uname -a
Linux tuxstep 6.16.0-tuxstep-amd64 #1 SMP ... x86_64

# ldd /System/Library/Tools/ls
        /System/Library/Libraries/libSystem.so (0x...)

# ls /
Local  Network  System  Volumes

# ls /System/Library/Libraries/
libdispatch.so       libgnustep-base.so       libobjc2.so       libSystem.so
libgnustep-corebase.so

# cat > /System/Library/Private/tmp/hello.m <<EOF
#import <Foundation/Foundation.h>
int main(void) {
    @autoreleasepool {
        NSLog(@"Hello from TuxSTEP v0.1");
    }
}
EOF

# /System/Library/Tools/cc -ObjC -lSystem -lobjc2 -ldispatch -lgnustep-base \
        /System/Library/Private/tmp/hello.m \
        -o /System/Library/Private/tmp/hello
# /System/Library/Private/tmp/hello
2026-XX-XX HH:MM:SS.fff Hello from TuxSTEP v0.1
```

That is the v0.1 deliverable. Three bootable ISOs (i386, amd64, arm64), all of which demonstrate: Linux kernel + Apple libsystem + Apple BSD userland + Gershwin runtime stack + Obj-C compilation, zero glibc anywhere on the system, four real top-level directories with no compat symlinks. `ls /` shows exactly the system's identity. CI gates green on all three architectures simultaneously before v0.1 is declared shipping.

## Component repos

| Repo | Purpose | Status |
|---|---|---|
| `tuxstep/tuxstep` | Umbrella + ISO build orchestrator | Active (this repo) |
| `tuxstep/libsystem-linux` | Phase 0 — Apple libsystem as ELF | To create |
| `tuxstep/toolchain-libsystem` | Phase 1 — clang/lld rebuilt against libsystem | To create |
| `tuxstep/coreutils-darwin-linux` | Phase 2 — Apple BSD coreutils + zsh ports | To create |
| `tuxstep/gershwin-libsystem-patches` | Phase 4 — patches to rebuild Gershwin stack against libsystem | To create |
| `tuxstep/grub` | Phase 5 — GRUB fork with TuxSTEP boot UX (silent boot default, Mac-style boot keys: cmd-V verbose, cmd-S single-user, etc.) | To create |
| `tuxstep/bless` | Phase 6 — `newfs` + `bless` + auto-bless daemon | To create (post-v0.1) |
| `tuxstep/darlingserver` | Mach IPC daemon (deferred to v0.2) | Live, on hold |
| `tuxstep/darling` | Monorepo fork (Mach-O execution path — abandoned) | Archive |
| `tuxstep/darling-bootstrap_cmds` | mig (deferred — needed when Mach IPC interface defs become relevant) | On hold |

## Deferred to v0.2 and beyond

- **launchd** as PID 1 (replaces shell-as-PID-1)
- **darlingserver** + **libsimple_darlingserver** (Mach IPC for ELF callers)
- **login + getty + auth chain** (multi-user)
- **`tuxstep-uevent` + `tuxstep-modload`** (modular kernel + hot-plug)
- **Wifi support** (port wpa_supplicant against libsystem, or fresh-write)
- **DHCP client** (port apple-oss/bootp_cmds)
- **`configd`** (system network/host configuration)
- **Package management** (port apple-oss/pkgutil + installer)
- **Display server / GUI stack** (libs-gui, libs-back, libs-opal, libs-quartzcore rebuilt against libsystem)
- **Window manager** (Eau from Gershwin)
- **Workspace.app, Terminal.app, demo applications**
- **NSPasteboard ↔ X11, UTI ↔ MIME bridges**

## Open questions

These are not blocking v0.1 work but should be resolved before the milestones they affect.

1. **initramfs build tool for v0.1.** Pragmatic option: use whatever's convenient on the build host (mkinitramfs, dracut, or a hand-rolled cpio archive). The initramfs is transient and pre-PID-1, so it does not affect the "no glibc, no GNU userland" constraint of the running system. Resolve before Phase 5.

2. **`/etc/passwd` for v0.1.** Some libsystem code calls `getpwnam`/`getpwuid`. Ship a minimal `/etc/passwd` with just root for v0.1.

3. **Bootloader post-v0.1.** GRUB is GPL/GNU but pre-userland. For a long-term cleaner story, evaluate rEFInd (BSD-licensed, UEFI+BIOS) or systemd-boot (LGPL, UEFI-only) in v0.2 or v0.3.

4. **Apple OSS pin.** Choose a specific Apple Open Source release to pin against (likely the most recent macOS release available — Tahoe 26.x as of project start). Stay on it until concrete reason to bump.

5. **CI build infrastructure.** Until the toolchain is self-hosted, builds happen on a Devuan/Debian host with cross-compilation. Plan for self-hosting around the v0.1 → v0.2 transition.

## Maintaining sync with upstream

The architecture is designed so that staying in sync with Apple's open-source releases is bounded and inexpensive:

- **Apple source is vendored unmodified as a submodule.** The submodule is never edited in place. Bumping is `git submodule update --remote`, not a merge.
- **Linux-specific code lives in parallel `linux-glue/` directories.** Adding kernel-specific behavior never touches Apple source.
- **Path-rewriting patches live in a separate `patches/` series.** A small, stable set of patches replaces hardcoded `/dev`, `/etc`, `/var`, `/tmp` references with `/System/Library/Private/...` equivalents. Patches are applied at build time after `git submodule update`. They rarely conflict because Apple seldom changes `<paths.h>` macros or path-string literals.
- **Syscall stubs generated from a table.** When Apple adds a syscall, we add one line to `syscall_table.txt`; no new hand-written code.
- **A `scripts/audit_paths.sh` enumerates direct path literals** in any newly-vendored Apple source so the patch series can be extended mechanically.
- **Pin upstream to yearly Apple OSS releases, not tip.** Apple ships tagged source drops; we track those, not the upstream development branches.
- **Watch CI to detect upstream-bump breakage early.** A weekly automated build against upstream's latest gives advance warning of incoming work without forcing immediate action.

Estimated ongoing sync work after the initial port: 1-3 days per Apple OSS release. Most bumps require zero changes to the patch series; occasional bumps require adding 1-3 patches if Apple introduced new hardcoded paths in their source.

## Revision history

- 2026-04-26: Initial plan, v0.1 spec locked. Reflects pivot away from Mach-O-execution approach (Darling-style) toward libsystem-linked ELF userland.
- 2026-04-26 (rev 2): Filesystem layout cleanup. All system-internal Unix infrastructure (etc, var, tmp, dev, sys, kernel images, firmware, modules) moved under `/System/Library/`. No `/etc`, `/var`, `/tmp`, `/dev`, `/sys`, `/boot`, `/lib`, `/Users`, `/private` at root. Compat symlinks eliminated by patching Apple-OSS source at build time to use `/System/Library/Private/...` paths. Decision #8 and #9 revised; new `patches/` mechanism added to Phase 0 description and sync workflow. Four real top-level directories: `/System`, `/Network`, `/Local`, `/Volumes`.
- 2026-04-26 (rev 3): Boot architecture, drag-and-drop deployment, multi-arch commitment locked in. Decision #11 revised: bootloader is `tuxstep/grub` (forked from upstream GNU GRUB) with TuxSTEP boot UX — silent boot default, Mac-style boot keys (cmd-V verbose, cmd-S single-user, option for boot-volume picker, etc.). Decision #14 added: `/System` is the OS; drag-and-drop deployable via auto-bless daemon that performs non-destructive partition surgery (creating hidden ESP, shrinking ext4 if needed via `resize2fs`). Decision #15 added: i386 + amd64 + arm64 all required from v0.1 — i386 is not optional, not deferrable; pinned to a 2018-era Apple-OSS release that still contains 32-bit code. Decision #16 added: filesystem is ext4 (UFS and HFS+ considered and rejected on technical grounds). Boot chain section rewritten to describe the hidden 5 MB FAT32 ESP + GRUB chainloader + EFI-stub kernel pattern. New "Volume management" section documents `newfs` / `bless` / auto-bless daemon. Phase plan extended with Phases 6-9 (post-v0.1) for the deployment tooling, launchd, Mach IPC, and GUI stack. Component repos table extended with `tuxstep/grub` and `tuxstep/bless`.
