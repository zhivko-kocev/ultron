# Firmware (BIOS) settings

ultron needs four things from the firmware. Most PCs and laptops from the last ten years already have the first one.

| Setting | Set to | Why |
|---|---|---|
| Boot mode | **UEFI** (CSM / Legacy support **off**) | ultron's boot loader is installed for UEFI only |
| Secure Boot | **Off** | the boot loader (Limine) is not signed |
| Fast Boot | **Off** | so the keyboard and the boot menu key always work |
| Virtualization (SVM / VT-x) | **On** | only needed for virtual machines; safe to leave on |

Enter the firmware setup with **Delete** or **F2** right after power-on (laptops: often F2, F10 or Esc). The names differ per maker; search the setup for "CSM", "Secure Boot" and "Fast Boot".

Then open the one-time boot menu (often **F12**, F11 or F8) and pick the entry that starts with **UEFI:** and names your USB stick. An entry without `UEFI:` starts the stick in legacy mode, and the installer refuses to run ("You started the USB in legacy mode").

## Before you change anything

If your firmware can save profiles (Gigabyte: Save & Exit → Save Profiles), save the current settings first. Until the installer wipes the disk, loading that profile brings your old system back exactly as it was.

## If the screen stays black after turning CSM off

Old graphics cards without UEFI support show nothing in pure UEFI mode, and some boards switch the first display to the built-in graphics.

1. Move the monitor cable to the other output (from the graphics card to the motherboard's port, or the other way round).
2. Enter the setup again and set the first display output (Gigabyte: Settings → IO Ports → Initial Display Output; ASUS: Advanced → Onboard Devices / Primary Display; MSI: Settings → Advanced → Integrated Graphics → Initiate Graphic Adapter) to the port your monitor is on.
3. Save and exit. ultron works on either GPU.

If you can't get a picture at all, clear the firmware settings (the board's CLR_CMOS jumper or button, see its manual): that restores the factory defaults.

## Example: Gigabyte AM5 boards

| Step | Where | Set to |
|---|---|---|
| 1 | Press **F2** | Advanced mode |
| 2 | Save & Exit → Save Profiles | save to profile 1 |
| 3 | Boot → CSM Support | Disabled |
| 4 | Boot → Secure Boot | Disabled |
| 5 | Boot → Fast Boot | Disabled |
| 6 | Settings → IO Ports → Initial Display Output | the slot or port your monitor is on (PCIe 1 Slot for a graphics card, IGD Video for the motherboard port) |
| 7 | Tweaker → Advanced CPU Settings → SVM Mode | Enabled |
| 8 | Press **F10** | save and exit |

Boot menu: **F12** at the logo.
