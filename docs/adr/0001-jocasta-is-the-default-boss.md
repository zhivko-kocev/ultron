# 1. Jocasta is the default boss

Date: 2026-11-26. Status: accepted (ultron 0.3.0).

**Context.** The boss window on workspace 1 is where the user talks to agents all day. Up to 0.2 it ran plain omp by default; Jocasta (many omp sessions as threads, review pages, a queue of what needs you) was opt-in and built from source on the PC, with omp pinned to the version Jocasta's README named.

**Decision.** From 0.3, `BOSS=jocasta` is the default and `jocasta` is a default install step. mise installs Jocasta from its GitHub releases (`"github:zhivko-kocev/jocasta" = "latest"` in `ultron-tools.toml`, checksums and build attestations checked), next to omp at its latest version. The step runs `jocasta setup --yes` on the first install, writes `projects.yaml` and the palette; it needs no root and builds nothing. Any other agent stays one command away (`ultron agent boss omp`).

**Rejected: keep omp as the default and Jocasta opt-in.** Every fresh install would then miss the queue, threads and review pages the desktop is built around, and the opt-in path was the one that compiled Rust and pinned omp on the user's machine.

**Rejected: keep the source build.** A Rust build at install time is slow, needs a toolchain and runs third-party build scripts; a release archive verified by mise does neither.
