# VMware mouse driver for OS/2

VMWMOUSE.SYS is an OS/2 device-dependent mouse driver for PS/2 mice.

If VMware extensions are available, this driver will use them to provide
**absolute pointer coordinates**; if they are absent, the driver will
work like the regular IBM PS/2 mouse driver (IBMMOU01.SYS) and provide
relative coordinates. It does not support serial or bus mice.

Note: The VMware extensions assume a 32-bit processor, so this driver
requires an **80386 or later**, even in regular PS/2 mode.

## Files

| File          | Description                                        |
|---------------|----------------------------------------------------|
| Makefile      | Open Watcom 1.9 `wmake` Makefile                   |
| vmwmouse.asm  | Driver source                                      |
| vmwmouse.lnk  | Linker script                                      |
| vmwmouse.ddp  | Device Driver Profile for `DDINSTAL.EXE`           |

## Building

With Open Watcom 1.9 installed:

    wmake

This produces `vmwmouse.sys` (and `vmwmouse.map`).

## Installation

Copy `vmwmouse.sys` to `C:\OS2` (or your OS/2 system directory) and add
the following two lines to `CONFIG.SYS`:

    DEVICE=C:\OS2\VMWMOUSE.SYS
    DEVICE=C:\OS2\MOUSE.SYS TYPE=VMWMOU$

Make sure to load `VMWMOUSE.SYS` before `MOUSE.SYS`. Remove references
to the previous mouse driver to save some memory.

Alternatively, install with the Device Driver Installer by running
`DDINSTAL.EXE` and pointing it at the location of `vmwmouse.ddp`;
it will copy the driver file and update `CONFIG.SYS` for you.

## Usage

No further configuration is needed. At boot the driver reports its mode:

- `VMWMOUSE: Driver installed in VMware mode.` — VMware integration
  is available and enabled.
- `VMWMOUSE: Driver installed in PS/2 mode.` — VMware integration
  is unavailable, but a PS/2 mouse can be used.
- `VMWMOUSE: Driver not installed.` — No PS/2 mouse was detected.

To remove the driver, delete the two DEVICE lines from `CONFIG.SYS` and
reboot.

## Compatibility

This driver should be compatible with OS/2 1.2 and OS/2 1.3,
as long as they run on a 32-bit processor.

It has been developed against DOSBox-X 2026.10.01 with
PS/2 port emulation and VMware integration enabled:

    [dos]
    vmware = true

    [keyboard]
    aux = true
    controllertype = at

On IBM OS/2 1.20 (syslevel XR00000), only PS/2 mode works.
Microsoft OS/2 1.21 (XR04072) and all tested versions of
OS/2 1.3 support both PS/2 and VMware mode correctly.

Compatibility with later versions of OS/2 is unknown.
