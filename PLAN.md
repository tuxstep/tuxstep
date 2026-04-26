# TuxSTEP — Master Plan

This document is the source of truth for TuxSTEP's architecture, scope, and phase plan. When in doubt, this overrides any other documentation in the repo. Last revised 2026-04-26.

## Project identity

TuxSTEP is a modern NeXT-inspired operating system distribution built on top of the Linux kernel, with an entirely Apple-derived userland. The Linux kernel provides hardware support and ecosystem reach; everything from PID 1 upward is libsystem-linked Apple/Darwin code, supplemented by the GNUstep frameworks (via Gershwin) for Cocoa-style application development.

**What TuxSTEP is:**

- A Linux distribution where the userspace is Apple's open-source userland
- A NeXT-inspired filesystem and design model (`/System`, `/Network`, `/Local`, `/Users`)
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
| 11 | Bootloader: GRUB for v0.1 | Pragmatic; pre-userland anyway. Reconsider rEFInd/systemd-boot post-v0.1. |
| 12 | KMS drivers built into kernel for v0.1 | No userspace module-loading infrastructure needed. Trade ~30-50MB on the kernel image for a vastly simpler v0.1 userland. |
| 13 | Base distribution: none | We do not derive from Devuan, Debian, or any Linux distribution at runtime. Devuan may be used as a build host to cross-compile; the resulting ISO contains zero Devuan binaries. |

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

1. **GRUB** loads kernel + initramfs from `/System/Library/Kernels/<kver>/`. The grub.cfg points at the in-System path; GRUB doesn't care about the depth.
2. **Linux kernel** boots. KMS drivers are built into the kernel and come up automatically; framebuffer console renders at native resolution. The kernel opens `/dev/console` from initramfs (initramfs is transient and may have its own conventional layout).
3. **initramfs** mounts the squashfs as the new root, mounts the kernel-managed filesystems at their /System/Library/Private locations:
   - `mount -t devtmpfs devtmpfs /System/Library/Private/dev`
   - `mount -t sysfs sysfs /System/Library/Private/sys` (only if needed; v0.1 may skip)
   - `mount -t tmpfs tmpfs /System/Library/Private/tmp`
   - `mount -t tmpfs tmpfs /System/Library/Private/var/run`
4. **PID 1 = `/System/Library/Tools/zsh`** directly. No init system, no service supervisor, no auth chain. The user is at a `#` prompt as root.

`CONFIG_DEVTMPFS_MOUNT=n` in the kernel config — we mount devtmpfs at the deep path explicitly rather than letting the kernel auto-mount at `/dev`. There is no `/dev` directory at the squashfs root.

When the user types `exit`, the kernel panics with "Attempted to kill init" — expected behavior for a shell-as-PID-1 system. Power off via the syscalls `reboot(2)` / `halt(2)` directly, or via Apple's `reboot` and `halt` commands (which call those syscalls).

## Phase plan to v0.1

| Phase | Component | Estimate |
|---|---|---|
| 0 | `tuxstep/libsystem-linux` — Apple libsystem ported to ELF | 4-6 months |
| 1 | Bootstrap toolchain — clang + lld rebuilt against libsystem; Apple headers at `/System/Library/Headers/` | 3-4 months |
| 2 | Apple BSD coreutils + zsh ported to libsystem | 3-4 months |
| 3 | `mount`, `umount`, `fsck.ext4` ports (small subset, just enough for ISO) | 2-3 weeks |
| 4 | Gershwin stack rebuilt against libsystem (libobjc2, libdispatch, tools-make, libs-base, libs-corebase) | 1-2 months |
| 5 | Kernel config + initramfs + ISO assembly | 1-2 months |

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
- GRUB `grub.cfg` references `/System/Library/Kernels/<kver>/{vmlinuz,initramfs}`
- ISO build pipeline producing both amd64 and arm64 images

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

That is the v0.1 deliverable. A bootable ISO, both arches, that demonstrates: Linux kernel + Apple libsystem + Apple BSD userland + Gershwin runtime stack + Obj-C compilation, zero glibc anywhere on the system, four real top-level directories with no compat symlinks. `ls /` shows exactly the system's identity.

## Component repos

| Repo | Purpose | Status |
|---|---|---|
| `tuxstep/tuxstep` | Umbrella + ISO build orchestrator | Active (this repo) |
| `tuxstep/libsystem-linux` | Phase 0 — Apple libsystem as ELF | To create |
| `tuxstep/toolchain-libsystem` | Phase 1 — clang/lld rebuilt against libsystem | To create |
| `tuxstep/coreutils-darwin-linux` | Phase 2 — Apple BSD coreutils + zsh ports | To create |
| `tuxstep/gershwin-libsystem-patches` | Phase 4 — patches to rebuild Gershwin stack against libsystem | To create |
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
