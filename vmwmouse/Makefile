#
# VMware mouse driver for OS/2
# build with Open Watcom 1.9 wmake
#
WASM=wasm
WLINK=wlink

vmwmouse.sys : vmwmouse.obj vmwmouse.lnk
	$(WLINK) @vmwmouse.lnk

vmwmouse.obj : vmwmouse.asm
	$(WASM) -q -3p -fo=vmwmouse.obj vmwmouse.asm

clean: .SYMBOLIC
	rm -f vmwmouse.obj vmwmouse.map vmwmouse.sys
