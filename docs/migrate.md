# Moving from Omarchy to ultron (Phase C)

This is the one-time move from Omarchy on this PC to ultron. The NVMe disk (KIOXIA 256 GB) is wiped; your data travels through the 512 GB SATA SSD (label `projects`), which is never wiped. Only a new folder `ultron-migration-<date>/` is added to it, and it stays there until you delete it yourself.

Do the steps in order. Until step C5 you can still go back (see "Going back" in [bios.md](bios.md)).

## C1. Pre-flight report (changes nothing)

The agent prepares a report for you:

- every git repo under `~/Projects` and `~/Work` with uncommitted changes or unpushed commits (commit and push what you want to keep on GitHub too);
- `sudo docker volume ls` (these volumes get exported);
- the size of your home folder without the backup's excludes;
- the SSD's free space, from a read-only mount.

The Arch ISO downloaded for the VM test is reused; nothing new is downloaded.

## C2. Back up to the SSD

Close every omp session, Jocasta, Chrome and Chromium. In a plain terminal run:

    ~/Projects/ultron/bin/ultron migrate backup

It:

1. Refuses while omp, chrome, chromium or jocasta is running.
2. Mounts the SSD at `/mnt/projects` (no fstab change), shows what's on it and the free space, and stops if the copy (plus 10 %) won't fit.
3. Writes to `/mnt/projects/ultron-migration-<date>` (with `-HHMM` added if that exists).
4. Exports every Docker volume to `docker-volumes/<volume>.tgz`.
5. Copies your home folder to `home/`, leaving out caches and things that are rebuilt anyway: `~/.cache`, mise's installs, the Trash, the VM, `~/.stremio-server`, `~/.rustup`, cargo and npm/bun caches, Arch ISOs in Downloads, and every Rust `target/` and `node_modules/` under `~/Projects` and `~/Work`.
6. Copies `/etc` to `etc/`, and saves the installed package lists (`pacman -Qqe`, `pacman -Qqm`) and your crontab as text files.
7. Checks a second dry run shows no changes, syncs, unmounts, and prints the folder and its size.

Not enough space? Run it again with `--exclude /Downloads/` and copy Downloads to another disk yourself.

## C3. Make the USB stick

Plug in a USB stick of at least 2 GB; **it will be erased**. Run:

    caligula burn ~/.local/share/ultron-vm/archlinux-*-x86_64.iso

Pick the stick and confirm.

## C4. BIOS

Follow [bios.md](bios.md): save profile 1, turn CSM, Secure Boot and Fast Boot off, set the display output to the PCIe slot, turn SVM on, F10. Then press F12 at the logo and pick the entry that starts with **UEFI:** and names your stick.

## C5. Install Arch

In the live ISO run:

    bash <(curl -fsSL https://raw.githubusercontent.com/zhivko-kocev/ultron/main/bootstrap.sh)

Check that the disk shown is the **KIOXIA 256 GB**, then type `wipe`. Choose the disk password and the user password. When it finishes, remove the stick and reboot.

## C6. Install ultron

At the Limine menu pick the Arch entry, type the disk password, log in, and run:

    ~/Projects/ultron/bin/ultron install

It builds some AUR packages (GraalVM for the Limine tools, Rust for stremio-service), so it takes a while. Reboot. The boot menu now says ultron, and sway starts by itself.

## C7. Restore your data

First look at what would happen:

    ultron migrate restore --dry-run

Read the summary (the full list is in `/tmp/ultron-restore-preview.txt`), then run it for real:

    ultron migrate restore

It:

1. Needs `/mnt/projects` mounted, and uses the newest `ultron-migration-*` folder (or the one given with `--dir`).
2. Skips every file in your home that is a link into `~/Projects/ultron` or `~/Projects/dotfiles`.
3. Skips Omarchy's desktop files and the configs ultron and dotfiles now own (Hyprland, Omarchy, waybar, walker, other terminals, mako, systemd user units, environment.d, mise, applications, `~/.agents`, shell rc files, Chrome/Chromium flags, Zed, git config, and the two repos themselves).
4. Copies everything else with `rsync -aHAX`, never deleting anything.
5. Imports each `docker-volumes/<volume>.tgz` into a rootless Docker volume of the same name.
6. Runs `xdg-user-dirs-update`.

Your data, Chrome profile, keyrings (logins), `.omp` (sessions and logins), gh login, `~/Projects` (with `jocasta`) and `~/Work` all come back.

## C8. Jocasta

    ultron install jocasta

It builds and installs Jocasta. Read each `jocasta setup` diff and type `y`. Then Super+W on workspace 1 (confirm) and Super+B: the boss is Jocasta. Details: [jocasta.md](jocasta.md).

## C9. Tailscale and phone alerts

    ultron install net

Open the printed link and sign in. In <https://login.tailscale.com/admin/dns> turn on **MagicDNS** and **HTTPS Certificates**. Then:

    ultron install ntfy

Pick a password for the phone app, then follow the printed iPhone steps (Tailscale app with the same account; ntfy app subscribed to `ultron-alerts` on your server, user `zhivko`).

## C10. Check everything

    ultron doctor --deep

Then go through the "Real" column of the verification table with the agent. The agent finally points dotai's README to the dotfiles repo and archives dotai.

## When something goes wrong

| What happens | What to do |
|---|---|
| The installer (archinstall) fails at the bootloader | See "Installing Limine by hand" below, then continue with C6 |
| Black screen after turning CSM off | Monitor cable to the motherboard HDMI, and Initial Display Output = **IGD Video** ([bios.md](bios.md)) |
| Second thoughts before C5 | BIOS → load profile 1 (CSM on): Omarchy boots as before |
| `migrate backup` stops: not enough SSD space | Run it again with `--exclude /Downloads/`, and copy Downloads separately to another disk |
| The installer says "You started the USB in legacy mode" | Reboot, press F12, pick the entry that starts with **UEFI:** |
| The Limine tools' AUR build fails (GraalVM download) | Run `ultron install aur boot` again. If it still fails, carry on without snapshot boot entries for now: snapper still snapshots, and you roll back from the live USB with `snapper rollback` |
| Restore would overwrite a linked file | The dry-run preview shows a linked path: add it to the static excludes, push, run `ultron update`, then restore again |
| Jocasta doesn't run on Linux | Set `BOSS=omp` in `~/.config/ultron/ultron.conf`, close the boss window, press Super+B |
| askpass can't reach Wayland (sudo fails at once with "no password was provided") | askpass already defaults `WAYLAND_DISPLAY=wayland-1` and `XDG_RUNTIME_DIR=/run/user/1000`; check `ls $XDG_RUNTIME_DIR` for the real socket name |
| `docker info` fails (docker-rootless-extras newer than docker) | `yay -G docker-rootless-extras`, set `pkgver` to the installed docker version, `makepkg -si` |
| `ollama ps` doesn't show `100% GPU` | Set `GGML_VK_VISIBLE_DEVICES` by hand in `/etc/systemd/system/ollama.service.d/ultron.conf`; if VRAM is short, `OLLAMA_CONTEXT_LENGTH=4096` or `ULTRON_ASK_MODEL=qwen3:1.7b` |
| `omp commit` errors on `ollama/qwen3:4b` | Keep the commit role on haiku |
| `tailscale serve` fails (HTTPS off) | Turn on HTTPS Certificates in the admin console, then `ultron install ntfy` again |
| The iPhone gets no pushes | Phone's Tailscale on; server `https://ultron.<tailnet>.ts.net`; user `zhivko` |
| Jocasta's next setup reverts the commit role (doctor WARN) | `ultron install ai` sets it again |

### Installing Limine by hand

If archinstall fails at the bootloader, the disk is already partitioned, encrypted and mounted at `/mnt`. In the live ISO:

1. Find the root partition's PARTUUID (the encrypted one, partition 2), for example `blkid -s PARTUUID -o value /dev/nvme0n1p2`.
2. Enter the new system and install Limine to the fallback path:

       arch-chroot /mnt
       pacman -S limine
       install -D /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI

3. Write `/boot/limine.conf` with one entry (put the PARTUUID from step 1 in place of `<PARTUUID>`). archinstall's initramfs unlocks the disk with the `encrypt` hook, so the command line uses `cryptdevice=`:

       timeout: 3

       /Arch Linux
           protocol: linux
           path: boot():/vmlinuz-linux
           module_path: boot():/initramfs-linux.img
           cmdline: cryptdevice=PARTUUID=<PARTUUID>:root root=/dev/mapper/root rootflags=subvol=@ rw rootfstype=btrfs quiet

4. Leave the chroot (`exit`), reboot, and continue with C6. `ultron install` later rewrites the boot menu properly.
