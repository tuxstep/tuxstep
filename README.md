# TuxSTEP

A modern NeXT-inspired operating system distribution. Linux kernel underneath, Apple's libsystem and Darwin-derived userland on top, GNUstep frameworks (via Gershwin) for Cocoa-style application development. No glibc, no GNU userland, no Mach-O execution.

See [PLAN.md](./PLAN.md) for the architectural source of truth: project identity, locked design decisions, filesystem layout, boot chain, phase plan, and the v0.1 spec.

## Status

Pre-v0.1. The current ISO build infrastructure in this repo (`build.sh`, `ci/`, `grub.cfg`, `packages.list`) reflects an older Devuan-derived approach that has been superseded by the libsystem-linked-userland direction in PLAN.md. It will be replaced as the phase plan executes.

The v0.1 deliverable is a bootable ISO (amd64 + arm64) containing a Linux kernel and an entirely Apple-derived libsystem-linked userland that boots to a single-user zsh shell. See [PLAN.md](./PLAN.md) for the full phase plan and timeline.

## Component repos

| Repo | Purpose |
|---|---|
| `tuxstep/tuxstep` | Umbrella + ISO build orchestrator (this repo) |
| `tuxstep/libsystem-linux` | Phase 0 — Apple libsystem ported to ELF |
| `tuxstep/toolchain-libsystem` | Phase 1 — clang/lld rebuilt against libsystem |
| `tuxstep/coreutils-darwin-linux` | Phase 2 — Apple BSD coreutils + zsh ports |
| `tuxstep/gershwin-libsystem-patches` | Phase 4 — patches to rebuild Gershwin against libsystem |
| `tuxstep/darlingserver` | Mach IPC daemon (deferred to v0.2) |

## License

BSD 2-clause. See [LICENSE](./LICENSE).
