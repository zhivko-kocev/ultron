# BIOS settings for ultron (Gigabyte A620M H)

ultron boots in UEFI mode. Today the PC boots in legacy CSM mode, which is also why the Ryzen's built-in GPU (780M) does not start. Change these settings once, just before installing (Phase C, step C4).

Restart the PC and press **Delete** repeatedly to enter the BIOS.

| Step | Where | Set to | Why |
|---|---|---|---|
| 1 | Press **F2** | Advanced mode | All the settings below are only in Advanced mode |
| 2 | Save & Exit → Save Profiles | Save to **profile 1** | Your way back to today's settings |
| 3 | Boot → CSM Support | **Disabled** | Pure UEFI boot (and the iGPU can start) |
| 4 | Boot → Secure Boot | **Disabled** | Limine is not signed |
| 5 | Boot → Fast Boot | **Disabled** | So the keyboard and F12 boot menu always work |
| 6 | Settings → IO Ports → Initial Display Output | **PCIe 1 Slot** | The monitor is on the RX 580 |
| 7 | Tweaker → Advanced CPU Settings → SVM Mode | **Enabled** | Virtualization (KVM) |
| 8 | Press **F10** | Save and exit | |

Then press **F12** at the Gigabyte logo and choose the entry that starts with **UEFI:** and names your USB stick. An entry without `UEFI:` boots in legacy mode, and the installer will refuse to run ("You started the USB in legacy mode").

## If the screen stays black

1. Move the monitor cable from the RX 580 to the motherboard's HDMI port.
2. Enter the BIOS again (Delete) and set Settings → IO Ports → Initial Display Output to **IGD Video**.
3. Save with F10. ultron works on either GPU.

## Going back

Before the disk is wiped (step C5) nothing is lost: enter the BIOS, go to Save & Exit → Load Profiles, load **profile 1** (CSM on), and save with F10. Omarchy boots exactly as before.
