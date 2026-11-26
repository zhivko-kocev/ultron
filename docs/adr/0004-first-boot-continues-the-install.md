# 4. The first boot continues the install

Date: 2026-11-26. Status: accepted (ultron 0.3.0).

**Context.** Up to 0.2, after the live-ISO installer the user rebooted, logged in on a text console and had to know to type `~/Projects/ultron/bin/ultron install`. Omarchy's install runs through without that step, and a beginner on a bare console doesn't know what to type.

**Decision.** `bootstrap.sh` arms the first boot: a marker `/var/lib/ultron/firstboot`, autologin of the new user on tty1, and a profile script that runs `ultron install --first-boot` on that console while the marker exists. It runs the default steps (asking for the password once), and the `desktop` step removes all three files as its last root action; on success it reboots into the desktop after 10 seconds. A failure names the step, says what to run, and leaves the marker, so the next login on tty1 retries. The Wi-Fi network joined in the installer is carried into NetworkManager so the first boot is online. Each release ships an ISO that starts the installer by itself.

**Rejected: a systemd service that runs the install at boot.** The install asks for the user's password and builds AUR packages as the user; a service has no terminal to ask in and would run it as root or without a ticket.

**Rejected: install everything from the live ISO.** Inside the chroot there is no user session, no rootless Docker and no running desktop to check, and AUR builds as root are what the sudo rules forbid.
