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
| VM (Phase B) | | | | | | |
| Real machine (Phase C) | | | | | | |
