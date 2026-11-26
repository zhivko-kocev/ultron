# Idle footprint baseline

This records how much the machine uses when nothing is happening. There is no pass or fail; the numbers are for comparison after changes.

## What is measured, and how

1. **Memory after login.** Boot, type the disk password, wait for sway, touch nothing for 2 minutes and do not start any agents (the boss window may be open but idle). Then run:

       free -m

   Record the `used` and `available` columns of the `Mem:` row.

2. **Idle CPU and memory of Jocasta and the boss omp.** With Jocasta open on workspace 1 and no thread running, wait 2 minutes, then run:

       ps -C jocasta -o pid,pcpu,rss,etime,args
       ps -C omp -o pid,ppid,pcpu,rss,etime,args

   `pcpu` is the average CPU % since the process started; for a current reading run `top -b -n 3 -d 5 -p <pid>` and use the last sample. `rss` is resident memory in KiB (divide by 1024 for MiB). Record the boss omp (the one whose parent is Jocasta, or the `omp` in the boss window when `BOSS=omp`).

3. **Context.** Record the date, the kernel (`uname -r`) and the `BOSS` value from `~/.config/ultron/ultron.conf`.

## Results

| Where | Date | Kernel | `free -m` used / available (MiB) | jocasta CPU % / RSS (MiB) | boss omp CPU % / RSS (MiB) | Notes |
|---|---|---|---|---|---|---|
| VM, v0.1 | 2026-11-26 | 7.3.6-arch1-1 | 572 / 5337 (desktop only: Jocasta closed, model unloaded); 4454 / 1454 with Jocasta running (boss, 3 startup reviews, qwen3:4b loaded on the CPU, 3.3 GB) | 0.2 / 27 | 0.2 / 280 | QEMU/KVM, 6 vCPU, 5.9 GiB, no GPU. With no cloud login, the boss and Jocasta's startup reviews ran on the local model. omp's own `omp daemon` (83 MiB) and tiny-inference worker (70 MiB) stay running after Jocasta closes |
| VM, v2, generic install (`LOCAL_AI=no`, no dotfiles) | 2026-11-26 | 7.3.6-arch1-1 | 620 / 5289 (desktop only: no agent, Docker not started); 859 / 5050 with the omp boss idle and rootless Docker started | – | 3.9 (first minute) / 281 | Same VM. sway alone is 190 MiB here because the VM renders in software. Rootless Docker starts on first use and then holds about 160 MiB (dockerd, containerd, rootlesskit) |
| Real machine | | | | | | |
