; ===========================================================================
;
; VMware mouse driver for OS/2
;
; This is an OS/2 1.x device-dependent mouse driver
; for PS/2 mice on AT-class machines. If the VMware
; backdoor interface is available, this driver will
; use it to provide absolute coordinates.
;
; The VMware interface uses 32-bit instructions,
; so this driver requires an 80386 processor.
;
; To use it, update CONFIG.SYS as follows:
;   DEVICE=C:\OS2\VMWMOUSE.SYS
;   DEVICE=C:\OS2\MOUSE.SYS TYPE=VMWMOU$
;
; Interrupt handlers must be bimodal - they
; are called in both real and protected mode.

        .386p

; device header attribute bits
DEV_CHAR        equ 0x8000      ; character device
DEV_IDC         equ 0x4000      ; has IDC entry point
DEV_LEVEL1      equ 0x0080      ; OS/2 1.x device driver

DEVINFO_SIZE    equ 6           ; device info structure size

; request packet
RP_Len          equ 0x00        ; byte
RP_Unit         equ 0x01        ; byte
RP_Cmd          equ 0x02        ; byte  command code
RP_Status       equ 0x03        ; word
RPI_Units       equ 0x0D        ; INIT: byte  out: number of units
RPI_DevHlp      equ 0x0E        ; INIT: dword in:  DevHlp entry point
RPI_CodeEnd     equ 0x0E        ; INIT: word  out: end of resident code
RPI_DataEnd     equ 0x10        ; INIT: word  out: end of resident data
RPI_Args        equ 0x12        ; INIT: dword in:  DEVICE= line

CMD_INIT        equ 0x00
CMD_DEINSTALL   equ 0x14

STATUS_DONE     equ 0x0100
STATUS_GENFAIL  equ 0x002F
STATUS_ERR      equ 0x8000
ERR_UNKCMD      equ 0x0003

; DevHlp functions
DevHlp_SetIRQ   equ 0x1B        ; AX = handler, BX = IRQ, DH = 1 if shared
DevHlp_UnSetIRQ equ 0x1C        ; BX = IRQ
DevHlp_AttachDD equ 0x2A        ; BX -> name, DI -> 12-byte IDC table
DevHlp_EOI      equ 0x31        ; AL = IRQ

; MOUSE$ event bits (MOUEVENTINFO.fs)
MOUSE_MOTION                equ 0x01
MOUSE_MOTION_WITH_BN1_DOWN  equ 0x02
MOUSE_BN1_DOWN              equ 0x04
MOUSE_MOTION_WITH_BN2_DOWN  equ 0x08
MOUSE_BN2_DOWN              equ 0x10
MOUSE_MOTION_WITH_BN3_DOWN  equ 0x20
MOUSE_BN3_DOWN              equ 0x40

; MOUSE$ IDC events
IDC_RELEVENT    equ 1           ; relative event
IDC_GONE        equ 2           ; driver uninstalled
IDC_ABSEVENT    equ 3           ; absolute event

; driver flags
F_ENABLED       equ 0x01        ; MOUSE$ wants events
F_ATTACHED      equ 0x02        ; MOUSE$ attached
F_DEINSTALLED   equ 0x08        ; DEINSTALL received
F_IRQEN         equ 0x10        ; IRQ enabled
F_VMWARE        equ 0x20        ; VMware integration active

; interrupt constants
PS2_IRQ         equ 12
PS2_IRQ_BIT     equ 1 shl (PS2_IRQ - 8)
PIC2_IMR        equ 0x0A1

; keyboard controller constants
KBC_DATA        equ 0x60
KBC_STAT        equ 0x64        ; read: status, write: command
KBS_OBF         equ 0x01        ; output buffer full
KBS_IBF         equ 0x02        ; input buffer full
KBC_RD_CMDBYTE  equ 0x20
KBC_WR_CMDBYTE  equ 0x60
KBC_AUX_ENABLE  equ 0xA8
KBC_KBD_DISABLE equ 0xAD
KBC_KBD_ENABLE  equ 0xAE
KBC_WRITE_AUX   equ 0xD4
CB_KBDINT       equ 0x01        ; command byte bits
CB_AUXINT       equ 0x02
CB_KBDDIS       equ 0x10
CB_AUXDIS       equ 0x20

AUX_ACK         equ 0xFA
AUX_RESEND      equ 0xFE
AUX_BAT_OK      equ 0xAA
AUX_RESET       equ 0xFF
AUX_ENABLE      equ 0xF4
AUX_SET_RATE    equ 0xF3
AUX_SET_RES     equ 0xE8
AUX_SCALE_11    equ 0xE6
AUX_RATE        equ 200         ; 200 samples/s
AUX_RES         equ 3           ; 8 counts/mm

TIMEOUT         equ 32          ; i8042 timeout: TIMEOUT * 64K polls

; VMware backdoor integration
VMW_PORT                equ 0x5658      ; I/O port address
VMW_MAGIC               equ 0x564D5868  ; 'VMXh'
VMW_CMD_GETVERSION      equ 10
VMW_CMD_ABSPTR_DATA     equ 39
VMW_CMD_ABSPTR_STATUS   equ 40
VMW_CMD_ABSPTR_COMMAND  equ 41
VMW_ABSPTR_ENABLE       equ 0x45414552
VMW_ABSPTR_DISABLE      equ 0x000000F5
VMW_ABSPTR_ABSOLUTE     equ 0x53424152
VMW_ABSPTR_RELATIVE     equ 0x4C455252
VMW_STATUS_ERROR        equ 0xFFFF0000
VMW_RELATIVE            equ 0x00010000
VMW_BTN_LEFT            equ 0x20
VMW_BTN_RIGHT           equ 0x10
VMW_BTN_MIDDLE          equ 0x08
VMW_ABS_SHIFT           equ 2
VMW_ABS_EXTENT          equ 0x4000
VMW_MAX_PKTS            equ 8

        extrn   DOSPUTMESSAGE:far       ; MSG.1

; ===========================================================================
; DATA segment, must begin with device header
; ===========================================================================
DGROUP  group   _DATA

_DATA   segment word public use16 'DATA'

DevHeader       dd -1
                dw DEV_CHAR or DEV_IDC or DEV_LEVEL1
                dw offset Strategy
                dw offset IdcEntry
                db 'VMWMOU$ '
                db 8 dup (0)

DevHlp          dd 0

DevInfo         dw DEVINFO_SIZE
                db 80               ; mickeys/cm
                db 3                ; buttons
                db PS2_IRQ          ; interrupt
                db 4                ; PS/2 type

IdcFuncTable    dw offset Idc1_QueryDevInfo
                dw offset Idc2_Enable
                dw offset Idc3_Disable
                dw offset Idc4_EnableInts
                dw offset Idc5_DisableInts

Flags           dw 0
EvPktOff        dw 0                ; event packet offset in MOUSE$ DS

MouseRealEntry  dd 0
MouseRealDS     dw 0
MouseProtEntry  dd 0
MouseProtDS     dw 0
MouseDDName     db 'MOUSE$  '

OldCmdByte      db 0                ; 8042 command byte before init
PktIndex        db 0
PktBuf          db 3 dup (0)
                even
OutPkt          dw 5 dup (0)        ; event packet built here, copied to MOUSE$

                ; discarded after initialization
InitData        label byte
MsgVmw          db 'VMWMOUSE: Driver installed in VMware mode.', 13, 10, 0
MsgPs2          db 'VMWMOUSE: Driver installed in PS/2 mode.', 13, 10, 0
MsgFail         db 'VMWMOUSE: Driver not installed.', 13, 10, 0

_DATA   ends

; ===========================================================================
; CODE segment
; ===========================================================================
_TEXT   segment word public use16 'CODE'
        assume  cs:_TEXT, ds:DGROUP, es:nothing, ss:nothing

; ---------------------------------------------------------------------------
; Strategy entry, ES:BX -> request packet
; ---------------------------------------------------------------------------
Strategy proc far
        mov     al, es:[bx + RP_Cmd]
        cmp     word ptr [DevHlp + 2], 0
        jne     str_initialised
        cmp     al, CMD_INIT
        jne     str_unknown
        call    Init
        jmp     short str_done
str_initialised:
        test    [Flags], F_DEINSTALLED
        jnz     str_unknown
        cmp     al, CMD_DEINSTALL
        jne     str_unknown
        push    es
        push    bx
        call    DeInstall
        pop     bx
        pop     es
        or      [Flags], F_DEINSTALLED
        jmp     short str_done
str_unknown:
        mov     word ptr es:[bx + RP_Status], STATUS_ERR or ERR_UNKCMD
str_done:
        or      word ptr es:[bx + RP_Status], STATUS_DONE
        ret
Strategy endp

; ---------------------------------------------------------------------------
; DeInstall: notify MOUSE$ and disable everything
; ---------------------------------------------------------------------------
DeInstall proc near
        test    [Flags], F_ATTACHED
        jz      dei_noattach
        mov     ax, IDC_GONE
        call    CallMouse
dei_noattach:
        call    Vmw_Off
        call    Aux_Off
        mov     bx, PS2_IRQ
        mov     dl, DevHlp_UnSetIRQ
        call    [DevHlp]
        ret
DeInstall endp

; ---------------------------------------------------------------------------
; IDC entry for MOUSE$: AX = function 1..5, DS = our data segment
; ---------------------------------------------------------------------------
IdcEntry proc far
        push    bx
        cmp     ax, 1
        jb      idc_bad
        cmp     ax, 5
        ja      idc_bad
        test    [Flags], F_DEINSTALLED
        jnz     idc_bad
        mov     bx, ax
        dec     bx
        shl     bx, 1
        call    [IdcFuncTable + bx]
        jmp     short idc_ret
idc_bad:
        stc
        mov     ax, 1
idc_ret:
        pop     bx
        ret
IdcEntry endp

; IDC 1: copy DEVINFO to ES:DI, at most the size in the first word
Idc1_QueryDevInfo proc near
        mov     cx, es:[di]
        cmp     cx, DEVINFO_SIZE
        jbe     idc1_n
        mov     cx, DEVINFO_SIZE
idc1_n: mov     si, offset DevInfo
        cld
        rep     movsb
        clc
        ret
Idc1_QueryDevInfo endp

; IDC 2: enable reporting, DI = event packet offset in MOUSE$ DS
Idc2_Enable proc near
        cli
        test    [Flags], F_ATTACHED
        jnz     idc2_attached
        push    di
        mov     bx, offset MouseDDName
        mov     di, offset MouseRealEntry
        mov     dl, DevHlp_AttachDD
        call    [DevHlp]
        pop     di
        jc      idc2_fail
        or      [Flags], F_ATTACHED
idc2_attached:
        mov     [EvPktOff], di
        mov     [PktIndex], 0
        or      [Flags], F_ENABLED
        sti
        clc
        ret
idc2_fail:
        sti
        mov     ax, 1
        stc
        ret
Idc2_Enable endp

; IDC 3: disable reporting
Idc3_Disable proc near
        and     [Flags], not F_ENABLED
        clc
        ret
Idc3_Disable endp

; IDC 4: unmask the IRQ
Idc4_EnableInts proc near
        mov     [PktIndex], 0
        or      [Flags], F_IRQEN
        pushf
        cli
        in      al, PIC2_IMR
        and     al, (not PS2_IRQ_BIT) and 0xFF
        out     PIC2_IMR, al
        popf
        xor     ax, ax
        clc
        ret
Idc4_EnableInts endp

; IDC 5: mask the IRQ
Idc5_DisableInts proc near
        and     [Flags], not F_IRQEN
        pushf
        cli
        in      al, PIC2_IMR
        or      al, PS2_IRQ_BIT
        out     PIC2_IMR, al
        popf
        xor     ax, ax
        clc
        ret
Idc5_DisableInts endp

; ---------------------------------------------------------------------------
; IRQ handler, called once per byte. Must be bimodal.
; The VMware backdoor uses 32-bit registers, so make sure to save them.
; CF clear on return = interrupt was ours.
; ---------------------------------------------------------------------------
        even
IntHandler proc far
        pushad                      ; save 32-bit registers
        in      al, KBC_DATA
        sti
        movzx   bx, [PktIndex]
        or      bx, bx
        jnz     int_store
        test    al, 0x08            ; first byte has bit 3 set: resync on it
        jz      int_eoi
int_store:
        mov     [PktBuf+bx], al
        inc     bx
        cmp     bx, 3
        jb      int_more
        mov     [PktIndex], 0
        test    [Flags], F_ENABLED
        jz      int_eoi
        call    ProcessPacket
        jmp     short int_eoi
int_more:
        mov     [PktIndex], bl
int_eoi:
        cli
        mov     al, PS2_IRQ
        mov     dl, DevHlp_EOI
        call    [DevHlp]
        popad                       ; restore 32-bit registers
        clc
        ret
IntHandler endp

; ---------------------------------------------------------------------------
; ProcessPacket: a complete PS/2 packet is in PktBuf
; ---------------------------------------------------------------------------
ProcessPacket proc near
        test    [Flags], F_VMWARE
        jz      SendRelative
        mov     di, VMW_MAX_PKTS
        xor     si, si              ; absolute packets sent
pp_next:
        call    Vmw_Status
        mov     edx, eax
        and     edx, VMW_STATUS_ERROR
        cmp     edx, VMW_STATUS_ERROR
        je      pp_error
        cmp     ax, 4
        jb      pp_done
        push    si
        push    di
        call    Vmw_Read
        pop     di
        pop     si
        test    eax, VMW_RELATIVE   ; relative packet
        jnz     pp_relative
        push    si
        push    di
        call    SendAbsolute
        pop     di
        pop     si
        inc     si
        dec     di
        jnz     pp_next
pp_done:
        ret
pp_error:
        call    Vmw_On              ; re-enable, then treat as relative
pp_relative:
        or      si, si              ; absolute data already sent for this
        jnz     pp_done             ; packet: don't add PS/2 motion on top
        call    Vmw_Drain
        jmp     SendRelative
ProcessPacket endp

; ---------------------------------------------------------------------------
; SendRelative: relative event (MOUSE$ IDC 1) from the PS/2 packet
;   byte 0: Yov Xov Ys Xs 1 M R L,  byte 1: X,  byte 2: Y (up = positive)
; ---------------------------------------------------------------------------
SendRelative proc near
        mov     dl, [PktBuf]
        movzx   ax, [PktBuf+1]      ; X, 9-bit two's complement
        test    dl, 0x10
        jz      rel_xp
        or      ah, 0xFF
rel_xp: movzx   cx, [PktBuf+2]      ; Y
        test    dl, 0x20
        jz      rel_yp
        or      ch, 0xFF
rel_yp: neg     cx                  ; OS/2 inverts vertical coordinate
        test    dl, 0xC0            ; overflow: motion is garbage
        jz      rel_nov
        xor     ax, ax
        xor     cx, cx
rel_nov:
        mov     [OutPkt+2], ax      ; column movement
        mov     [OutPkt+4], cx      ; row movement
        xor     bx, bx
        test    dl, 0x01
        jz      rel_l
        or      bl, MOUSE_MOTION_WITH_BN1_DOWN
rel_l:  test    dl, 0x02
        jz      rel_r
        or      bl, MOUSE_MOTION_WITH_BN2_DOWN
rel_r:  test    dl, 0x04
        jz      rel_m
        or      bl, MOUSE_MOTION_WITH_BN3_DOWN
rel_m:  or      ax, cx
        jnz     rel_moved
        shl     bx, 1               ; no motion: MOTION_WITH_BNx -> BNx_DOWN
        jmp     short rel_ev
rel_moved:
        or      bx, bx
        jnz     rel_ev
        inc     bx                  ; MOUSE_MOTION
rel_ev: mov     [OutPkt], bx
        mov     ax, IDC_RELEVENT
        mov     cx, 6
        jmp     PostEvent
SendRelative endp

; ---------------------------------------------------------------------------
; SendAbsolute: absolute event (MOUSE$ IDC 3) from backdoor data
;   EAX = buttons, EBX = X, ECX = Y (0..FFFFh)
; MOUSE$ derives motion from the position, so only BNx_DOWN bits are sent.
; ---------------------------------------------------------------------------
SendAbsolute proc near
        xor     dx, dx
        test    al, VMW_BTN_LEFT
        jz      abs_l
        or      dl, MOUSE_BN1_DOWN
abs_l:  test    al, VMW_BTN_RIGHT
        jz      abs_r
        or      dl, MOUSE_BN2_DOWN
abs_r:  test    al, VMW_BTN_MIDDLE
        jz      abs_m
        or      dl, MOUSE_BN3_DOWN
abs_m:  mov     [OutPkt], dx
        shr     cx, VMW_ABS_SHIFT
        mov     [OutPkt+2], cx      ; row
        shr     bx, VMW_ABS_SHIFT
        mov     [OutPkt+4], bx      ; column
        mov     [OutPkt+6], VMW_ABS_EXTENT
        mov     [OutPkt+8], VMW_ABS_EXTENT
        mov     ax, IDC_ABSEVENT
        mov     cx, 10
        jmp     PostEvent
SendAbsolute endp

; ---------------------------------------------------------------------------
; PostEvent: copy CX bytes of OutPkt to MOUSE$:EvPktOff, call MOUSE$ IDC AX
; CallMouse: just call MOUSE$ IDC AX
; ---------------------------------------------------------------------------
PostEvent proc near
        push    ds
        push    es
        mov     dx, ax
        call    LoadMouseDS
        mov     si, offset OutPkt
        mov     di, [EvPktOff]
        cld
        rep     movsb               ; DS:SI (ours) -> ES:DI (MOUSE$)
        mov     ax, dx
        call    MouseCall
        pop     es
        pop     ds
        ret
PostEvent endp

CallMouse proc near
        push    ds
        push    es
        call    LoadMouseDS
        call    MouseCall
        pop     es
        pop     ds
        ret
CallMouse endp

; load correct (real/protected mode) MOUSE$ data segment in ES
LoadMouseDS proc near
        smsw    bx
        and     bx, 1
        jnz     lmd_prot
        mov     es, [MouseRealDS]
        ret
lmd_prot:
        mov     es, [MouseProtDS]
        ret
LoadMouseDS endp

; AX = function, ES = MOUSE$ data, BX = mode. Swaps DS/ES (the caller
; restores them): MOUSE$ expects DS = its data, ES = ours.
MouseCall proc near
        push    ds
        push    es
        pop     ds
        pop     es
        assume  ds:nothing, es:DGROUP
        or      bx, bx
        jnz     mc_prot
        call    es:[MouseRealEntry]
        ret
mc_prot:
        call    es:[MouseProtEntry]
        ret
        assume  ds:DGROUP, es:nothing
MouseCall endp

; ---------------------------------------------------------------------------
; VMware backdoor. All of these clobber EAX, EBX, ECX, EDX.
; ---------------------------------------------------------------------------
Vmw_Call proc near                  ; ECX = command, EBX = parameter
        mov     eax, VMW_MAGIC
        mov     dx, VMW_PORT
        in      eax, dx
        ret
Vmw_Call endp

Vmw_Status proc near                ; -> EAX: error bits | queued words
        mov     ecx, VMW_CMD_ABSPTR_STATUS
        xor     ebx, ebx
        jmp     Vmw_Call
Vmw_Status endp

Vmw_Read proc near                  ; -> EAX buttons, EBX x, ECX y, EDX z
        mov     ecx, VMW_CMD_ABSPTR_DATA
        mov     ebx, 4
        jmp     Vmw_Call
Vmw_Read endp

Vmw_Command proc near               ; EBX = sub-command
        mov     ecx, VMW_CMD_ABSPTR_COMMAND
        jmp     Vmw_Call
Vmw_Command endp

; discard queued packets
Vmw_Drain proc near
        push    si
        mov     si, 64
vd_loop:
        call    Vmw_Status
        test    eax, VMW_STATUS_ERROR
        jnz     vd_done
        cmp     ax, 4
        jb      vd_done
        call    Vmw_Read
        dec     si
        jnz     vd_loop
vd_done:
        pop     si
        ret
Vmw_Drain endp

; enable the absolute pointer, empty the queue, request absolute mode
; -> CF set if the backdoor reports an error
Vmw_On proc near
        mov     ebx, VMW_ABSPTR_ENABLE
        call    Vmw_Command
        call    Vmw_Status
        test    eax, VMW_STATUS_ERROR
        jnz     von_fail
        call    Vmw_Drain
        mov     ebx, VMW_ABSPTR_ABSOLUTE
        call    Vmw_Command
        clc
        ret
von_fail:
        stc
        ret
Vmw_On endp

Vmw_Off proc near
        test    [Flags], F_VMWARE
        jz      voff_ret
        and     [Flags], not F_VMWARE
        mov     ebx, VMW_ABSPTR_RELATIVE
        call    Vmw_Command
        mov     ebx, VMW_ABSPTR_DISABLE
        call    Vmw_Command
voff_ret:
        ret
Vmw_Off endp

; ---------------------------------------------------------------------------
; 8042 helpers. CF set = timeout. Clobber AL, CX, DX.
; ---------------------------------------------------------------------------
Kbc_WaitIn proc near                ; wait for input buffer empty
        mov     dx, TIMEOUT
kwi_o:  xor     cx, cx
kwi_i:  in      al, KBC_STAT
        test    al, KBS_IBF
        jz      kwi_ok
        loop    kwi_i
        dec     dx
        jnz     kwi_o
        stc
        ret
kwi_ok: clc
        ret
Kbc_WaitIn endp

Kbc_WaitOut proc near               ; wait for output buffer full
        mov     dx, TIMEOUT
kwo_o:  xor     cx, cx
kwo_i:  in      al, KBC_STAT
        test    al, KBS_OBF
        jnz     kwo_ok
        loop    kwo_i
        dec     dx
        jnz     kwo_o
        stc
        ret
kwo_ok: clc
        ret
Kbc_WaitOut endp

Kbc_Cmd proc near                   ; AH = controller command
        call    Kbc_WaitIn
        jc      kc_ret
        mov     al, ah
        out     KBC_STAT, al
kc_ret: ret
Kbc_Cmd endp

Kbc_WriteData proc near             ; AH = data byte
        call    Kbc_WaitIn
        jc      kd_ret
        mov     al, ah
        out     KBC_DATA, al
kd_ret: ret
Kbc_WriteData endp

Kbc_Drain proc near                 ; discard pending output bytes
        mov     cx, 16
kdr_l:  in      al, KBC_STAT
        test    al, KBS_OBF
        jz      kdr_d
        in      al, KBC_DATA
        loop    kdr_l
kdr_d:  ret
Kbc_Drain endp

Kbc_SetCmdByte proc near            ; BL = new command byte
        mov     ah, KBC_WR_CMDBYTE
        call    Kbc_Cmd
        jc      ksc_ret
        mov     ah, bl
        call    Kbc_WriteData
ksc_ret:
        ret
Kbc_SetCmdByte endp

; aux port off: aux clock and aux interrupt off, keyboard back on
Aux_Off proc near
        pushf
        cli
        mov     bl, [OldCmdByte]
        and     bl, (not (CB_AUXINT or CB_KBDDIS)) and 0xFF
        or      bl, CB_AUXDIS or CB_KBDINT
        call    Kbc_SetCmdByte
        mov     ah, KBC_KBD_ENABLE
        call    Kbc_Cmd
        popf
        ret
Aux_Off endp

; ---------------------------------------------------------------------------
; INIT (everything from here on is discarded after initialisation)
; ---------------------------------------------------------------------------
Init proc near
        push    es
        push    bx
        mov     ax, es:[bx+RPI_DevHlp]
        mov     word ptr [DevHlp], ax
        mov     ax, es:[bx+RPI_DevHlp+2]
        mov     word ptr [DevHlp+2], ax
        mov     word ptr es:[bx+RP_Status], 0

        call    Aux_Init
        jc      init_fail

        mov     ax, offset IntHandler
        mov     bx, PS2_IRQ
        xor     dh, dh               ; not shared
        mov     dl, DevHlp_SetIRQ
        call    [DevHlp]
        jc      init_fail_aux

        call    Vmw_Detect          ; sets F_VMWARE

        call    Aux_Start
        jc      init_fail_irq

        mov     si, offset MsgPs2
        test    [Flags], F_VMWARE
        jz      init_msg
        mov     si, offset MsgVmw
init_msg:
        call    PutMsg
        pop     bx
        pop     es
        mov     byte ptr es:[bx+RPI_Units], 0
        mov     word ptr es:[bx+RPI_CodeEnd], offset Init
        mov     word ptr es:[bx+RPI_DataEnd], offset InitData
        ret

init_fail_irq:
        mov     bx, PS2_IRQ
        mov     dl, DevHlp_UnSetIRQ
        call    [DevHlp]
init_fail_aux:
        call    Vmw_Off
        call    Aux_Off
init_fail:
        mov     si, offset MsgFail
        call    PutMsg
        pop     bx
        pop     es
        or      word ptr es:[bx+RP_Status], STATUS_ERR or STATUS_GENFAIL
        mov     byte ptr es:[bx+RPI_Units], 0
        mov     word ptr es:[bx+RPI_CodeEnd], 0
        mov     word ptr es:[bx+RPI_DataEnd], 0
        ret
Init endp

; ---------------------------------------------------------------------------
; Aux_Init: take the 8042 aux port, reset and configure the mouse.
; Keyboard and aux interrupts stay off until Aux_Start.
; ---------------------------------------------------------------------------
Aux_Init proc near
        cli
        mov     ah, KBC_KBD_DISABLE
        call    Kbc_Cmd
        jc      ai_fail
        call    Kbc_Drain
        mov     ah, KBC_RD_CMDBYTE
        call    Kbc_Cmd
        jc      ai_fail
        call    Kbc_WaitOut
        jc      ai_fail
        in      al, KBC_DATA
        mov     [OldCmdByte], al
        mov     bl, al
        and     bl, (not (CB_KBDINT or CB_AUXINT or CB_AUXDIS)) and 0xFF
        or      bl, CB_KBDDIS
        call    Kbc_SetCmdByte
        jc      ai_fail
        mov     ah, KBC_AUX_ENABLE
        call    Kbc_Cmd
        jc      ai_fail
        sti

        call    Aux_ResetMouse
        jc      ai_fail
        mov     ah, AUX_SET_RATE
        mov     bh, AUX_RATE
        call    Aux_Send2
        jc      ai_fail
        mov     ah, AUX_SET_RES
        mov     bh, AUX_RES
        call    Aux_Send2
        jc      ai_fail
        mov     ah, AUX_SCALE_11
        call    Aux_Send
        jc      ai_fail
        call    Kbc_Drain
        clc
        ret
ai_fail:
        sti
        call    Aux_Off
        stc
        ret
Aux_Init endp

; ---------------------------------------------------------------------------
; Aux_Start: enable data reporting, then aux + keyboard interrupts
; ---------------------------------------------------------------------------
Aux_Start proc near
        mov     ah, AUX_ENABLE
        call    Aux_Send
        jc      as_ret
        cli
        mov     bl, [OldCmdByte]
        and     bl, (not (CB_KBDDIS or CB_AUXDIS)) and 0xFF
        or      bl, CB_KBDINT or CB_AUXINT
        call    Kbc_SetCmdByte
        mov     ah, KBC_KBD_ENABLE
        call    Kbc_Cmd
        sti
        clc
as_ret: ret
Aux_Start endp

; ---------------------------------------------------------------------------
; Aux_Send: AH = byte for the mouse, wait for ACK (FEh -> resend, 3 times)
; Aux_Send2: AH = command, BH = argument.  Clobber AX, BL, CX, DX.
; ---------------------------------------------------------------------------
Aux_Send proc near
        mov     bl, 3
asn_try:
        push    ax
        mov     ah, KBC_WRITE_AUX
        call    Kbc_Cmd
        pop     ax
        jc      asn_ret
        call    Kbc_WriteData
        jc      asn_ret
        call    Kbc_WaitOut
        jc      asn_ret
        in      al, KBC_DATA
        cmp     al, AUX_ACK
        je      asn_ret             ; (CF clear: equal)
        cmp     al, AUX_RESEND
        jne     asn_fail
        dec     bl
        jnz     asn_try
asn_fail:
        stc
asn_ret:
        ret
Aux_Send endp

Aux_Send2 proc near
        call    Aux_Send
        jc      as2_ret
        mov     ah, bh
        call    Aux_Send
as2_ret:
        ret
Aux_Send2 endp

; ---------------------------------------------------------------------------
; Aux_ResetMouse: FFh -> FAh, then BAT AAh 00h (lenient: emulators may omit
; or shorten the BAT report). FCh = BAT failure.
; ---------------------------------------------------------------------------
Aux_ResetMouse proc near
        call    Kbc_Drain
        mov     ah, AUX_RESET
        call    Aux_Send
        jc      ar_ret
        call    Kbc_WaitOut
        jc      ar_ok
        in      al, KBC_DATA
        cmp     al, AUX_BAT_OK
        je      ar_id
        or      al, al
        jz      ar_ok
        stc
        ret
ar_id:  call    Kbc_WaitOut
        jc      ar_ok
        in      al, KBC_DATA         ; device id 00h
ar_ok:  call    Kbc_Drain
        clc
ar_ret: ret
Aux_ResetMouse endp

; ---------------------------------------------------------------------------
; Vmw_Detect: probe the backdoor (GETVERSION must echo the magic in EBX;
; on real hardware the port reads FFFFFFFFh and EBX stays unchanged),
; then enable the absolute pointer in absolute mode.
; ---------------------------------------------------------------------------
Vmw_Detect proc near
        mov     ecx, VMW_CMD_GETVERSION
        mov     ebx, not VMW_MAGIC
        call    Vmw_Call
        cmp     ebx, VMW_MAGIC
        jne     vdet_no
        cmp     eax, 0xFFFFFFFF
        je      vdet_no
        call    Vmw_On
        jc      vdet_no
        or      [Flags], F_VMWARE
vdet_no:
        ret
Vmw_Detect endp

; ---------------------------------------------------------------------------
; PutMsg: write zero-terminated string in DS:SI to stdout
; ---------------------------------------------------------------------------
PutMsg proc near
        mov     di, si
        xor     cx, cx
pm_len: cmp     byte ptr [di], 0
        je      pm_go
        inc     di
        inc     cx
        jmp     short pm_len
pm_go:  push    1                   ; stdout
        push    cx
        push    ds
        push    si
        call    DOSPUTMESSAGE
        ret
PutMsg endp

_TEXT   ends

        end
