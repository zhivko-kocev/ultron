# Moving to ultron from another Linux install

ultron's installer wipes one disk. This page is for when your current system lives on that disk and you want your files, logins and Docker volumes on the other side. You need a second disk, partition or external drive with enough free space; it is never wiped.

Do the steps in order. Nothing is erased before step 5.

## 1. Check what would be lost

- Commit and push work in your git repos (an extra copy never hurts).
- Note anything that lives outside your home folder (databases in `/var`, files in `/opt`). The backup takes your home folder, `/etc`, package lists, your crontab and Docker volumes; nothing else.

## 2. Back up

On the **old** system, get ultron and run the backup. Close browsers and agents first (the backup refuses while they run, so their files are copied in a consistent state).

    git clone https://github.com/zhivko-kocev/ultron ~/Projects/ultron
    ~/Projects/ultron/bin/ultron migrate backup --to LABEL=backup

`--to` takes a folder (`--to /run/media/me/usb`) or a partition (`LABEL=…`, `UUID=…`, `/dev/sdb1`), which is mounted for the run. Not sure what your disks are called? `lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINTS`.

It writes a new folder `ultron-migration-<date>` there and:

1. stops if the copy won't fit;
2. exports every Docker volume;
3. copies your home folder without caches and things that are rebuilt anyway (`~/.cache`, the Trash, tool installs, `node_modules`, Rust `target/` folders, ISO downloads, rootless Docker's images and containers in `~/.local/share/docker`: the volumes were exported in step 2);
4. copies `/etc` and saves your package lists;
5. checks the copy and marks it complete.

Not enough space? Add `--exclude /Downloads/` (any path relative to your home) and copy that folder yourself.

**The copy is not encrypted.** It holds your browser profile and login tokens. Keep the disk with you and delete the copy when you're done (step 8).

## 3. Make the USB stick

Download the Arch ISO from <https://archlinux.org/download/> and write it to a stick of at least 2 GB (it will be erased), for example with `caligula burn archlinux-*.iso` or any USB writer.

## 4. Firmware

See [bios.md](bios.md): UEFI mode, Secure Boot off. Boot the stick from the entry that starts with **UEFI:**.

## 5. Install

In the live ISO (plug in a network cable, or run `iwctl` for Wi-Fi):

    ULTRON_KEEP=backup bash <(curl -fsSL https://raw.githubusercontent.com/zhivko-kocev/ultron/main/bootstrap.sh)

`ULTRON_KEEP` names the label (or UUID) of your backup partition: the disk holding it is never offered for wiping. Answer the questions, check the disk shown is the right one, type `wipe`. Use the **same user name** as on the old system if you want paths inside your files to keep working. Remove the stick and reboot.

## 6. Install ultron

Type the disk password, log in, and run:

    ~/Projects/ultron/bin/ultron install

Reboot. The desktop starts by itself.

## 7. Restore

Look first:

    ultron migrate restore --from LABEL=backup --dry-run

The summary shows what would be copied (it prints the path of the full list, a new file under `/tmp`). Then for real:

    ultron migrate restore --from LABEL=backup

It uses the newest complete backup folder and:

- never deletes anything and never replaces a file that ultron or your dotfiles manage;
- skips the old desktop's own config (other window managers, bars, launchers) so it doesn't fight ultron's;
- brings back your files, browser profiles, keyrings, agent logins and sessions, `gh` login, projects;
- imports each Docker volume under the same name.

Log out and in again (Super+Escape → Log out) so everything picks up the restored files.

## 8. Check, then delete the copy

    ultron doctor --deep

Use the system for a few days. `doctor` keeps reminding you that the unencrypted copy exists. When you're sure nothing is missing:

    ultron migrate clean --from LABEL=backup

## When something goes wrong

| What happens | What to do |
|---|---|
| The installer says the USB was started in legacy mode | Reboot, open the boot menu, pick the entry that starts with **UEFI:** |
| Black screen after changing firmware settings | See [bios.md](bios.md) |
| Second thoughts before typing `wipe` | Power off. Nothing has changed |
| The installer (archinstall) fails at the bootloader | "Installing Limine by hand" below, then continue with step 6 |
| `migrate backup`: not enough space | `--exclude /Downloads/` (or another big folder), copy that one separately |
| The Limine tools' AUR build fails | `ultron install aur boot` again. Until it works you have snapshots but no boot-menu entries for them |
| Restore's preview shows a file you want kept as it is | Move that file aside on the new system first; restore never overwrites newer files it was told to skip, but it does replace same-named ordinary files |
| `sudo` from an agent fails at once with "no password was provided" | The popup can't reach the desktop: run `ultron doctor`; log out and in |
| `docker info` fails after an update | `docker-rootless-extras` (AUR) is behind `docker`: `ultron update` again a day later, or rebuild it with `yay -S docker-rootless-extras` |
| `ollama ps` doesn't show `100% GPU` | `ultron conf set OLLAMA_GPU <number>` (numbers: `vulkaninfo --summary`), then `ultron install ai`. Short on VRAM: `ultron setup model qwen3:1.7b` |

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

4. Leave the chroot (`exit`), reboot, and continue with step 6. `ultron install` later rewrites the boot menu properly.
