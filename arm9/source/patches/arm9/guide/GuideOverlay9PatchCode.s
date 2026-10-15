.cpu arm946e-s
.section "patch_guideoverlay9", "ax"
.syntax unified

#ifndef EXIT_TO_LAUNCHER
#define EXIT_TO_LAUNCHER 0
#endif
// EXIT_DIAG=1 keeps the detour and the blob exactly as they are but never
// calls the key check, so guide_tramp becomes a pure pass-through: replay the
// displaced instruction, jump back. guide_exitCheck is still assembled, so the
// blob is the same size and the patch heap sees the same allocation - the only
// variable left is whether the trampoline itself works.
#ifndef EXIT_DIAG
#define EXIT_DIAG 0
#endif
// GUIDE_IPC_FREEZE=1 (phase 4 M2): the trampoline installs guide_ipcHandler in
// the game's irqTable[16] (IPC_SYNC). The arm7 guide monitor sends sync value 9
// on L+R+Select and the handler freezes with both screens black until release.
#ifndef GUIDE_IPC_FREEZE
#define GUIDE_IPC_FREEZE 0
#endif
// GUIDE_READER=1 (phase 4 M3, implies GUIDE_IPC_FREEZE): instead of blacking
// the screens, the IPC_SYNC handler shows the guide text on the sub screen,
// pages it with the d-pad and puts the display back exactly on close.
#ifndef GUIDE_READER
#define GUIDE_READER 0
#endif
// GUIDE_READER_DIAG=1: the bottom screen shows how far the reader got, for a
// hardware lap where it hangs: blue = display taken over, red = inside the
// platform sd read, black without text = reads done but drawing hung.
#ifndef GUIDE_READER_DIAG
#define GUIDE_READER_DIAG 0
#endif

#if GUIDE_READER
// Lock id the reader holds the SDK card lock with. Games allocate theirs from
// 0x40 (arm9) and 0x80 (arm7), so 0x7F is never one of theirs.
.equ GUIDE_LOCK_ID, 0x7F
// The reader's work area: right after the blob in the reservation, address in
// guide_work_lit, zeroed by the loader. W_SIZE = GUIDE_READER_WORK_SIZE in
// GuideOverlay9.h - keep in sync. Small fields first: thumb loads only reach
// 31 (byte), 62 (halfword) and 124 (word) bytes from a base register.
.equ W_TOP,       0       // byte offset of the top line on screen, kept between opens
.equ W_WINOFF,    4       // file offset of the sector window
.equ W_WINLEN,    8       // valid bytes in the window, 0 = empty
.equ W_PREVKEYS, 12       // keys held last frame (active high)
.equ W_REPEAT,   16       // frames the d-pad has been held
.equ W_BGN,      20       // the sub bg the reader borrows (0-3)
.equ W_SPSAVE,   24       // the game's irq sp while the reader runs
.equ W_VRAMC,    28       // saved VRAMCNT_C (byte)
.equ W_VRAMH,    29       // saved VRAMCNT_H (byte)
.equ W_DISPCNT,  32       // saved DISPCNT_B
.equ W_POWCNT,   36       // saved halfwords from here on
.equ W_BGCNT,    38
.equ W_BLDCNT,   40
.equ W_BRIGHT,   42
.equ W_AUXSPI,   44
.equ W_EXMEM,    46
.equ W_PAL0,     48       // sub bg palette entries 0 and 1
.equ W_PAL1,     50
.equ W_INFO,     52       // the guide's guide_file_info_t
.equ W_SDREAD,   56       // the platform's sector read function
.equ W_FSIZE,    60       // the guide's size in bytes
.equ W_LINENO,   64       // display line number of W_TOP (1 = first), 0 = not seeded yet
.equ W_LOCK,     68       // the SDK card lock word (game's own alias)
.equ W_SDWRITE,  72       // the platform's sector write function, 0 = none
.equ W_LINES,    76       // 25 words: start offset of each screen line, then the next
.equ W_ROW,      0x100    // 32 map entries the back scan wraps into (never shown)
.equ W_STACK,    0x340    // top of the reader's stack (0x140-0x340)
.equ W_WIN,      0x400    // 2 KB sector window
.equ W_BAKTILES, 0xC00    // 3 KB: the game's sub bg tiles the font overwrites
.equ W_BAKMAP,   0x1800   // 1.5 KB: the game's map rows 0-23 at screen base 15
.equ W_CLMT,     0x1E00   // the guide's guide_file_info_t, copied here by the arm7 loader
                          // (0x1F00: the platform sd write code, placed by the loader)
.equ W_SIZE,     0x2000

// guide_file_info_t fields past the cluster map (common/fileInfo.h - keep in sync)
.equ G_POSSECTOR, 132     // first sd sector of <guide>.pos, 0 = none
.equ GUIDE_POS_SIZE, 32   // bytes of <guide>.pos (fileInfo.h)

.equ ROWS, 24             // screen lines
.equ COLS, 32             // characters per line
#endif

// In-game guide overlay: the resident arm9 blob.
//
// The loader image-patches the entry of the card read function (which it
// already locates) with an absolute jump to guide_tramp, so this code runs on
// every card read during gameplay, after OS_Init. From there:
//
//   EXIT_TO_LAUNCHER (guide_exitCheck): samples the keys and, while
//     L+R+Start+Select is held, jumps to the OS_ResetSystem tail the loader
//     has already patched to reboot into Pico Loader.
//
//   GUIDE_IPC_FREEZE (guide_ipcInstall): puts guide_ipcHandler in the game's
//     irqTable[16]; the arm7 monitor raises that irq on L+R+Select.
//
// Whole blob is position independent. It is copied to the top of the arm9 main
// arena, which the loader reserves by lowering OS_GetInitArenaHi (phase 4 M1).

.arm

// ======================= card-entry trampoline =======================
// Entered via `ldr pc,[pc,#-4]` + this address, written over the card
// function's first two instructions. An absolute jump, so it stays right when
// the card function sits in an autoload block that is copied elsewhere before
// main(). r0-r3 hold the card args, lr the game caller. Preserve everything;
// run the enabled checks; replay the two displaced instructions; go.
.global guide_tramp
.type guide_tramp, %function
guide_tramp:
    stmfd sp!, {r0-r3, r12, lr}
#if EXIT_TO_LAUNCHER && !EXIT_DIAG
    bl    guide_exitCheck
#endif
#if GUIDE_IPC_FREEZE
    bl    guide_ipcInstall
#endif
    ldmfd sp!, {r0-r3, r12, lr}
.global guide_replay_slot
guide_replay_slot:
    nop                              // C bakes displaced instruction 0 (the stmfd)
.global guide_replay_slot1
guide_replay_slot1:
    nop                              // C bakes displaced instruction 1, or `ldr rX, guide_replay_lit`
    ldr   pc, guide_cardReturn_lit   // -> card function + 8

.balign 4
.global guide_cardReturn_lit
guide_cardReturn_lit:
    .word 0                          // C bakes: runtime card entry + 8
.global guide_replay_lit
guide_replay_lit:
    .word 0                          // C bakes: what instruction 1's pc-relative ldr loads
.global guide_rebootEntry_lit
guide_rebootEntry_lit:
    .word 0                          // C bakes: patched OS_ResetSystem tail, or 0

#if EXIT_TO_LAUNCHER
// ======================= exit to launcher =======================
// Returns normally unless the combo is held, in which case it never returns.
//
// The reboot tail is written to be entered from the game's own OS_ResetSystem,
// which has already torn the game down by then. Coming in cold from a card read
// skips that, so do the two parts of the teardown that would otherwise corrupt
// the load: stop interrupts (the game's vblank handler would keep drawing into
// vram that the tail remaps to LCDC) and stop the arm9 dma channels (an
// in-flight transfer would write over the loader as it is read in). Everything
// else the tail handles itself - its first act is to reset the arm7, which
// stops sound and touch.
.type guide_exitCheck, %function
guide_exitCheck:
    ldr   r1, ex_keyinput
    ldrh  r0, [r1]
    ldr   r1, ex_keymask             // L | R | Start | Select, active low
    ands  r0, r0, r1
    bxne  lr                         // any of the four not held -> carry on
    ldr   r0, guide_rebootEntry_lit
    cmp   r0, #0
    bxeq  lr                         // no reboot tail on this game -> carry on

    ldr   r1, ex_regIme
    mov   r2, #0
    str   r2, [r1]                   // REG_IME = 0

    ldr   r1, ex_regDma0Cnt
    str   r2, [r1]                   // DMA0CNT
    str   r2, [r1, #0xC]             // DMA1CNT
    str   r2, [r1, #0x18]            // DMA2CNT
    str   r2, [r1, #0x24]            // DMA3CNT

    mcr   p15, 0, r2, c7, c10, 4     // drain write buffer
    mcr   p15, 0, r2, c7, c5, 0      // invalidate icache
    bx    r0                         // thumb bit is set in the baked literal

.balign 4
ex_keyinput:
    .word 0x04000130
ex_keymask:
    .word 0x0000030C
ex_regIme:
    .word 0x04000208
ex_regDma0Cnt:
    .word 0x040000B8
#endif

#if GUIDE_IPC_FREEZE
// ======================= M2: IPC_SYNC hook installer =======================
// Runs on every card read (from guide_tramp, which saved r0-r3, r12, lr). Puts
// guide_ipcHandler in irqTable[16], keeping the game's own entry as the chain
// target, and enables the IPC_SYNC irq. The game may rewrite the table or IE
// at any time, so this re-asserts on every call (as nds-bootstrap does).
// ponytail: re-asserted on card reads only; a game that clears IE bit 16 and
// then stops reading the card ignores the combo until its next read. Hook
// OS_EnableIrqMask like nds-bootstrap if a lap shows that.
.type guide_ipcInstall, %function
guide_ipcInstall:
    ldr   r0, guide_irqTable_lit
    cmp   r0, #0
    bxeq  lr                         // no table found on this game
    adr   r2, guide_ipcHandler
    ldr   r1, [r0, #16 * 4]          // irqTable[16] (IPC_SYNC)
    cmp   r1, r2
    strne r1, ipc_orig               // chain target first: an irq can land between the stores
    strne r2, [r0, #16 * 4]

    mov   r3, #0x04000000
    ldr   r12, [r3, #0x208]          // REG_IME
    mov   r0, #0
    str   r0, [r3, #0x208]           // no irq during the read-modify-writes
    ldr   r0, [r3, #0x210]           // REG_IE
    orr   r0, r0, #0x10000           // IRQ_IPC_SYNC
    str   r0, [r3, #0x210]
    add   r1, r3, #0x180             // REG_IPCSYNC
    ldrh  r0, [r1]
    orr   r0, r0, #0x4000            // irq from the arm7 enabled (send bit 13 reads 0)
    strh  r0, [r1]
    str   r12, [r3, #0x208]          // REG_IME back
    bx    lr

// ======================= M2: IPC_SYNC handler =======================
// irqTable[16] entry. The game's dispatcher has already acknowledged IF and
// calls this like any irq handler: irq mode, irqs off, r0-r3 and r12 free,
// return with bx lr. On sync value 9 (the arm7 monitor saw L+R+Select) it is
// the phase 3 freeze: both MASTER_BRIGHT to black, spin while the combo is
// held, restore exactly. Then the game's own entry runs, lr intact.
.type guide_ipcHandler, %function
guide_ipcHandler:
    mov   r12, #0x04000000
    add   r0, r12, #0x180
    ldrh  r0, [r0]                   // REG_IPCSYNC, bits 0-3 = the arm7's value
    and   r0, r0, #0xF
    cmp   r0, #9
    bne   ih_chain
#if GUIDE_READER
    // The reader reads the sd card, which shares the slot-1 bus with the game's
    // own rom reads and saves and with the arm7's own card accesses (the card
    // id check). A DSpico sd read is several card transfers (E3 set sector,
    // E4 poll, E5 data) and ROMCTRL bit 31 drops between them, so it alone
    // cannot tell that someone is mid read. The SDK's card lock can: every
    // user of the bus holds it, and whenever it is free the bus belongs to the
    // arm7 (OS_UnlockCard hands it over). Held -> do nothing now (its holder is
    // a game thread we just froze); the user presses the combo again. Free ->
    // open; each sd read then takes the lock and the bus for its few ms only
    // (rd_cardTake), so the arm7, which keeps checking the card, never waits
    // long. Holding it for the whole session stalled the arm7: no release beep
    // stop, no game sound.
    ldr   r0, guide_cardLock_lit
    ldr   r0, [r0]                   // lockFlag of the SDK card lock
    cmp   r0, #0
    bne   ih_chain
    ldr   r0, [r12, #0x1A4]          // REG_ROMCTRL
    tst   r0, #0x80000000            // a card transfer is running
    bne   ih_chain
    ldr   r0, guide_work_lit
    ldr   r1, guide_info_lit
    ldr   r2, guide_sdRead_lit
    cmp   r0, #0
    cmpne r1, #0
    cmpne r2, #0
    beq   ih_chain                   // reader not set up on this game
    ldr   r3, [r1, #12]              // guide_file_info_t.fileSize, 0 = no guide copied in
    cmp   r3, #0
    beq   ih_chain
    ldr   r3, guide_cardLock_lit
    str   r3, [r0, #W_LOCK]
    ldr   r3, guide_sdWrite_lit
    str   r3, [r0, #W_SDWRITE]
    str   r1, [r0, #W_INFO]
    str   r2, [r0, #W_SDREAD]
    ldr   r1, [r1, #12]              // guide_file_info_t.fileSize
    str   r1, [r0, #W_FSIZE]
    // Run the reader on its own stack in the reservation; the game's irq stack
    // is small. Irq mode, irqs stay off throughout, so the game is frozen.
    str   sp, [r0, #W_SPSAVE]
    add   sp, r0, #W_STACK
    stmfd sp!, {r4-r11, lr}
    blx   guide_reader               // r0 = work area
    ldmfd sp!, {r4-r11, lr}
    ldr   r0, guide_work_lit
    ldr   sp, [r0, #W_SPSAVE]
    b     ih_chain                   // like M2: the game's own entry runs after
#else
    stmfd sp!, {r4, r5}
    add   r1, r12, #0x130            // REG_KEYINPUT
    add   r2, r12, #0x6C             // MASTER_BRIGHT engine A
    add   r3, r2, #0x1000            // MASTER_BRIGHT engine B
    ldrh  r4, [r2]                   // save A
    ldrh  r5, [r3]                   // save B
    mov   r0, #0x8000
    orr   r0, r0, #0x10              // 0x8010 = brightness down by 16 (black)
    strh  r0, [r2]
    strh  r0, [r3]
ih_spin:
    ldrh  r0, [r1]
    tst   r0, #0x304                 // L | R | Select, active low
    beq   ih_spin                    // all three still held -> stay frozen
    strh  r4, [r2]                   // release: restore exactly
    strh  r5, [r3]
    ldmfd sp!, {r4, r5}
#endif
ih_chain:
    ldr   r0, ipc_orig
    cmp   r0, #0
    bxeq  lr                         // the game had no entry there
    bx    r0                         // the game's own entry; it returns to the dispatcher

.balign 4
.global guide_irqTable_lit
guide_irqTable_lit:
    .word 0                          // C bakes: the game's OS_IRQTable, or 0
ipc_orig:
    .word 0                          // runtime: the game's own irqTable[16] entry
#if GUIDE_READER
.global guide_work_lit
guide_work_lit:
    .word 0                          // C bakes: the reader's work area, or 0 (reader off)
.global guide_sdRead_lit
guide_sdRead_lit:
    .word 0                          // C bakes: platform sector read (sector, dst, count)
.global guide_sdWrite_lit
guide_sdWrite_lit:
    .word 0                          // C bakes: platform sector write (sector, src, count), or 0
.global guide_cardLock_lit
guide_cardLock_lit:
    .word 0                          // C bakes: the SDK card lock word, at the address the game uses
.global guide_info_lit
guide_info_lit:
    .word 0                          // C bakes: the guide's cluster map (in the work area)

// ======================= M3: guide reader =======================
// Thumb from here. Every routine keeps r7 = the work area. Position
// independent: only pc-relative branches, and literal pools that hold numbers.
.thumb

// Entered from guide_ipcHandler: irq mode, irqs off, own stack, r0 = work.
.type guide_reader, %function
.thumb_func
guide_reader:
    push  {r4-r7, lr}
    movs  r7, r0
    ldr   r0, [r7, #W_LINENO]        // first open since boot: start where the
    cmp   r0, #0                     // last session (or the guide-reader app) left
    bne   1f
    ldr   r1, [r7, #W_INFO]
    adds  r1, #G_POSSECTOR
    ldr   r0, [r1, #4]               // posOffset (0 when there is no .pos)
    str   r0, [r7, #W_TOP]
    ldr   r0, [r1, #8]               // posLine
    cmp   r0, #0
    bne   2f
    movs  r0, #1
2:  str   r0, [r7, #W_LINENO]
1:  bl    rd_open
#if GUIDE_READER_DIAG
    ldr   r0, =0x7C00                // blue backdrop, no bgs: rd_open finished
    bl    rd_diag
    ldr   r1, =0x04001000
    ldr   r0, =0x10000
    str   r0, [r1]
#endif
    bl    rd_render
    ldr   r0, [r7, #W_BGN]           // show it: mode 0, only the borrowed bg
    ldr   r1, =0x100
    lsls  r1, r0
    ldr   r0, =0x10000               // display mode 1 (bg/obj)
    orrs  r1, r0
    ldr   r0, =0x04001000            // DISPCNT_B
    str   r1, [r0]
    bl    rd_loop
    bl    rd_close
    bl    rd_savepos
    pop   {r4-r7, pc}

#if GUIDE_READER_DIAG
// r0 = color for the sub backdrop (palette entry 0). Clobbers r1.
.thumb_func
rd_diag:
    ldr   r1, =0x05000400
    strh  r0, [r1]
    bx    lr
#endif

// Save everything the reader touches on the sub engine and set it up for text.
// Nothing in the main engine changes: the top screen keeps the frozen game.
.thumb_func
rd_open:
    push  {r4-r6, lr}
    ldr   r6, =0x04000000
    ldr   r0, =0x304                 // POWCNT1: save, power lcds + 2d engine B. The
    ldrh  r1, [r6, r0]               // screen swap stays the game's: the guide shows
    strh  r1, [r7, #W_POWCNT]        // opposite the main gameplay, top or bottom
    ldr   r2, =0x0201
    orrs  r1, r2
    strh  r1, [r6, r0]

    // VRAM: bank H (32 KB) to the sub bg at 0x06200000. If bank C is mapped
    // there it moves to LCDC meanwhile (its contents stay). Both readable.
    ldr   r0, =0x240
    adds  r0, r6
    ldrb  r1, [r0, #2]               // VRAMCNT_C
    strb  r1, [r7, #W_VRAMC]
    ldrb  r2, [r0, #8]               // VRAMCNT_H
    strb  r2, [r7, #W_VRAMH]
    movs  r3, #0x87
    ands  r1, r3
    cmp   r1, #0x84                  // enabled, MST 4 = sub bg
    bne   1f
    movs  r1, #0x80                  // enabled, LCDC
    strb  r1, [r0, #2]
1:  movs  r1, #0x81                  // enabled, MST 1 = sub bg
    strb  r1, [r0, #8]

    // Borrow the highest bg the game has switched off (its scroll does not
    // matter now), else bg3. Scroll registers are write-only: zeroed, never
    // restored - a game that left that bg scrolled and never rewrites it
    // resumes shifted. nds-bootstrap's in-game menu has the same ceiling.
    ldr   r5, =0x04001000
    ldr   r0, [r5]                   // DISPCNT_B
    str   r0, [r7, #W_DISPCNT]
    movs  r4, #3
2:  movs  r1, #8
    adds  r1, r4
    movs  r2, r0
    lsrs  r2, r1
    lsls  r2, #31                    // Z = bg n is off
    beq   3f
    subs  r4, #1
    bpl   2b
    movs  r4, #3
3:  str   r4, [r7, #W_BGN]
    lsls  r1, r4, #1
    adds  r1, #8
    ldrh  r2, [r5, r1]               // BGnCNT_B
    strh  r2, [r7, #W_BGCNT]
    ldr   r2, =0x0F00                // map base 15, tiles base 0, 4bpp, 256x256, prio 0
    strh  r2, [r5, r1]
    lsls  r1, r4, #2
    adds  r1, #0x10
    movs  r2, #0
    str   r2, [r5, r1]               // BGnHOFS + BGnVOFS = 0
    ldr   r1, =0x50                  // BLDCNT_B: save, no blending
    ldrh  r2, [r5, r1]
    strh  r2, [r7, #W_BLDCNT]
    movs  r2, #0
    strh  r2, [r5, r1]
    ldr   r1, =0x6C                  // MASTER_BRIGHT_B: save, normal
    ldrh  r2, [r5, r1]
    strh  r2, [r7, #W_BRIGHT]
    movs  r2, #0
    strh  r2, [r5, r1]

    ldr   r6, =0x05000400            // sub bg palette: save 0 and 1, black + white
    ldrh  r0, [r6]
    strh  r0, [r7, #W_PAL0]
    ldrh  r0, [r6, #2]
    strh  r0, [r7, #W_PAL1]
    ldr   r0, =0x7FFF0000
    str   r0, [r6]

    // Back up the game's tiles and map rows the reader overwrites.
    ldr   r0, =W_BAKTILES
    adds  r0, r7
    ldr   r1, =0x06200000
    ldr   r2, =0xC00
    bl    rd_copy32
    ldr   r0, =W_BAKMAP
    adds  r0, r7
    ldr   r1, =0x06207800
    ldr   r2, =0x600
    bl    rd_copy32

    // Font: 96 glyphs, 8 rows of 1 bit per pixel (bit 0 = leftmost) become 4bpp
    // tiles 0-95 with color 1 (lowest nibble = leftmost pixel).
    ldr   r1, 9f
8:  add   r1, pc                     // r1 = rd_font
    ldr   r0, =0x06200000
    ldr   r6, =96 * 8
4:  ldrb  r3, [r1]
    adds  r1, #1
    movs  r4, #0
    movs  r5, #8
5:  lsls  r4, #4
    subs  r5, #1
    movs  r2, r3
    lsrs  r2, r5
    lsls  r2, #31
    lsrs  r2, #31
    orrs  r4, r2
    cmp   r5, #0
    bne   5b
    stmia r0!, {r4}
    subs  r6, #1
    bne   4b
    pop   {r4-r6, pc}
.balign 4
9:  .word rd_font - (8b + 4)
.pool

// Put back everything rd_open changed, in reverse.
.thumb_func
rd_close:
    push  {r4-r6, lr}
    ldr   r0, =0x06200000            // vram first, while bank H is still at the sub bg
    ldr   r1, =W_BAKTILES
    adds  r1, r7
    ldr   r2, =0xC00
    bl    rd_copy32
    ldr   r0, =0x06207800
    ldr   r1, =W_BAKMAP
    adds  r1, r7
    ldr   r2, =0x600
    bl    rd_copy32
    ldr   r0, =0x05000400
    ldrh  r1, [r7, #W_PAL0]
    strh  r1, [r0]
    ldrh  r1, [r7, #W_PAL1]
    strh  r1, [r0, #2]
    ldr   r5, =0x04001000
    ldr   r0, [r7, #W_DISPCNT]
    str   r0, [r5]
    ldr   r1, [r7, #W_BGN]
    lsls  r1, #1
    adds  r1, #8
    ldrh  r0, [r7, #W_BGCNT]
    strh  r0, [r5, r1]
    ldr   r1, =0x50
    ldrh  r0, [r7, #W_BLDCNT]
    strh  r0, [r5, r1]
    ldr   r1, =0x6C
    ldrh  r0, [r7, #W_BRIGHT]
    strh  r0, [r5, r1]
    ldr   r6, =0x04000000
    ldr   r0, =0x240
    adds  r0, r6
    ldrb  r1, [r7, #W_VRAMH]
    strb  r1, [r0, #8]
    ldrb  r1, [r7, #W_VRAMC]
    strb  r1, [r0, #2]
    ldr   r1, =0x304
    ldrh  r0, [r7, #W_POWCNT]
    strh  r0, [r6, r1]
    pop   {r4-r6, pc}

// r0 = dst, r1 = src, r2 = bytes (multiple of 4). Clobbers r0-r3.
.thumb_func
rd_copy32:
    ldmia r1!, {r3}
    stmia r0!, {r3}
    subs  r2, #4
    bne   rd_copy32
    bx    lr
.pool

// Key loop. Up/Down = one line, Left/Right = one page, held d-pad repeats.
// B, or L+R+Select again, closes.
.thumb_func
rd_loop:
    push  {r4-r6, lr}
    bl    rd_keys
    str   r0, [r7, #W_PREVKEYS]      // keys still held from the combo do nothing
    movs  r0, #0
    str   r0, [r7, #W_REPEAT]
rl_frame:
    bl    rd_frame
    bl    rd_keys
    ldr   r1, [r7, #W_PREVKEYS]
    str   r0, [r7, #W_PREVKEYS]
    movs  r4, r0                     // r4 = held
    bics  r0, r1
    movs  r5, r0                     // r5 = act on these: newly pressed...
    movs  r1, #0xF0
    ands  r1, r4                     // ...plus the held d-pad after 20 frames, every 4th
    ldr   r2, [r7, #W_REPEAT]
    adds  r2, #1
    cmp   r1, #0
    bne   1f
    movs  r2, #0
1:  str   r2, [r7, #W_REPEAT]
    cmp   r2, #20
    blo   2f
    lsls  r3, r2, #30
    bne   2f
    orrs  r5, r1
2:  movs  r0, #2                     // B
    tst   r5, r0
    bne   rl_close
    ldr   r0, =0x304                 // L+R+Select, one of them new
    movs  r1, r4
    ands  r1, r0
    cmp   r1, r0
    bne   3f
    tst   r5, r0
    bne   rl_close
3:  ldr   r6, [r7, #W_TOP]           // r6 = top before
    ldr   r0, =W_LINES + ROWS * 4
    ldr   r0, [r7, r0]               // where the line after the screen starts
    ldr   r1, [r7, #W_FSIZE]
    cmp   r0, r1
    bhs   rl_up                      // the end is on screen: no further down
    movs  r2, #0x10                  // Right: next page
    tst   r5, r2
    beq   4f
    str   r0, [r7, #W_TOP]
    movs  r1, #ROWS
    b     rl_forward
4:  movs  r2, #0x80                  // Down: next line
    tst   r5, r2
    beq   rl_up
    ldr   r0, [r7, #W_LINES + 4]
    str   r0, [r7, #W_TOP]
    movs  r1, #1
rl_forward:
    ldr   r0, [r7, #W_LINENO]        // keep the line number in step for the .pos
    adds  r0, r1
    str   r0, [r7, #W_LINENO]
    b     rl_moved
rl_up:
    movs  r2, #0x40                  // Up: previous line
    tst   r5, r2
    beq   5f
    bl    rd_back
    b     rl_moved
5:  movs  r2, #0x20                  // Left: previous page
    tst   r5, r2
    beq   rl_frame
    movs  r4, #ROWS
6:  bl    rd_back
    subs  r4, #1
    bne   6b
rl_moved:
    ldr   r0, [r7, #W_TOP]
    cmp   r0, r6
    beq   rl_frame
    bl    rd_render
    b     rl_frame
rl_close:
    // Wait until B, L, R and Select are all up, then two more frames so the
    // arm7 monitor sees the release and takes its sync value 9 back.
7:  bl    rd_frame
    bl    rd_keys
    ldr   r1, =0x306
    tst   r0, r1
    bne   7b
    bl    rd_frame
    bl    rd_frame
    pop   {r4-r6, pc}

// One display line back: W_TOP, and W_LINENO when it moved. Clobbers r0-r3.
.thumb_func
rd_back:
    push  {r4, lr}
    ldr   r4, [r7, #W_TOP]
    movs  r0, r4
    bl    rd_prev
    str   r0, [r7, #W_TOP]
    cmp   r0, r4
    beq   1f
    ldr   r0, [r7, #W_LINENO]
    cmp   r0, #1
    bls   1f
    subs  r0, #1
    str   r0, [r7, #W_LINENO]
1:  pop   {r4, pc}

// Waits for the start of the next vblank (irqs are off: poll VCOUNT).
.thumb_func
rd_frame:
    ldr   r0, =0x04000006
1:  ldrh  r1, [r0]
    cmp   r1, #192
    beq   1b
2:  ldrh  r1, [r0]
    cmp   r1, #192
    bne   2b
    bx    lr

// r0 = keys held, active high (A B Sel St R L U D R L = bits 0-9).
.thumb_func
rd_keys:
    ldr   r0, =0x04000130
    ldrh  r0, [r0]
    mvns  r0, r0
    ldr   r1, =0x3FF
    ands  r0, r1
    bx    lr
.pool

// Draws ROWS lines from W_TOP into the map and records where each starts.
.thumb_func
rd_render:
    push  {r4-r6, lr}
    ldr   r5, =W_LINES
    adds  r5, r7
    ldr   r0, [r7, #W_TOP]
    str   r0, [r5]
    ldr   r6, =0x06207800            // map row 0
    movs  r4, #ROWS
1:  ldr   r0, [r5]
    movs  r1, r6
    bl    rd_line
    adds  r5, #4
    str   r0, [r5]
    adds  r6, #COLS * 2
    subs  r4, #1
    bne   1b
    pop   {r4-r6, pc}

// Soft wrap, the same rules as the standalone guide-reader app (main.c,
// line_at), so pages break the same way. r0 = file offset, r1 = map row
// (COLS halfwords, filled with tile numbers and padded with spaces).
// Returns the offset where the next display line starts (r0 unchanged at
// the end of the file).
.thumb_func
rd_line:
    push  {r4-r6, lr}
    mov   r2, r8
    mov   r3, r9
    push  {r2, r3}
    movs  r4, r0                     // r4 = p
    movs  r6, r1                     // r6 = row
    movs  r5, #0                     // r5 = n, characters written
    movs  r0, #0
    mvns  r0, r0
    mov   r8, r0                     // r8 = index of the last space, -1 = none
1:  cmp   r5, #COLS
    beq   5f                         // row full
    movs  r0, r4
    bl    rd_byte
    cmp   r0, #0
    blt   5f                         // end of file
    adds  r4, #1
    cmp   r0, #13
    beq   1b                         // CR of CRLF
    cmp   r0, #10
    beq   9f                         // hard break: next line starts after it
    cmp   r0, #0x20
    bhs   2f
    movs  r0, #0x20                  // tab and other controls
2:  cmp   r0, #0x7E
    bls   3f
    movs  r0, #'?'                   // the font is ASCII; one byte stays one column
3:  cmp   r0, #0x20
    bne   4f
    mov   r8, r5                     // last space at n,
    mov   r9, r4                     // the next line would start after it
4:  subs  r0, #0x20                  // tile = character - 0x20
    lsls  r1, r5, #1
    strh  r0, [r6, r1]
    adds  r5, #1
    b     1b
5:  push  {r4}                       // row full or eof: where does the next start?
    movs  r0, r4
    bl    rd_byte
    cmp   r0, #13
    bne   6f
    adds  r4, #1
    movs  r0, r4
    bl    rd_byte
6:  cmp   r0, #10
    beq   7f                         // ended exactly on a line break
    cmp   r0, #0x20
    beq   7f                         // the word ended exactly at the edge
    cmp   r0, #9
    beq   7f
    pop   {r4}
    cmp   r5, #COLS
    bne   9f
    mov   r0, r8
    cmp   r0, #0
    ble   9f                         // one word wider than the screen: hard break
    movs  r5, r0                     // break at the last space
    mov   r4, r9
    b     9f
7:  add   sp, #4
    adds  r4, #1
9:  movs  r0, #0                     // pad with spaces from n
    cmp   r5, #COLS
    bhs   10f
    lsls  r1, r5, #1
    strh  r0, [r6, r1]
    adds  r5, #1
    b     9b
10: movs  r0, r4
    pop   {r2, r3}
    mov   r8, r2
    mov   r9, r3
    pop   {r4-r6, pc}

// r0 = offset of a display line -> offset of the one before it. Scans back to
// the start of the physical line (at most 4 KB) and wraps forward again, as
// the app's line_prev does.
.thumb_func
rd_prev:
    push  {r4-r6, lr}
    movs  r6, r0                     // r6 = off
    cmp   r0, #0
    ble   8f
    subs  r4, r0, #1                 // r4 = p
    movs  r0, r4
    bl    rd_byte
    cmp   r0, #10
    bne   1f
    subs  r4, #1                     // step over the line break we came through
1:  cmp   r4, #0
    blt   8f
    movs  r0, r4
    bl    rd_byte
    cmp   r0, #13
    bne   2f
    subs  r4, #1
2:  cmp   r4, #0
    blt   8f
    ldr   r5, =4096                  // r5 = scan limit
    subs  r5, r4, r5
    bpl   3f
    movs  r5, #0
3:  cmp   r4, r5
    ble   4f
    subs  r0, r4, #1
    bl    rd_byte
    cmp   r0, #10
    beq   4f
    subs  r4, #1
    b     3b
4:  movs  r5, r4                     // r5 = prev, r4 = cur
5:  cmp   r4, r6
    bhs   6f
    movs  r5, r4
    movs  r0, r4
    ldr   r1, =W_ROW
    adds  r1, r7
    bl    rd_line
    movs  r4, r0
    cmp   r4, r5
    bhi   5b                         // never loop forever
6:  movs  r0, r5
    pop   {r4-r6, pc}
8:  movs  r0, #0
    pop   {r4-r6, pc}
.pool

// r0 = file offset -> the byte there, or -1 past the end. Keeps a 2 KB window
// of sectors; a miss reloads it with the offset 1 KB in, so short scans in
// either direction stay inside. Clobbers r1-r3.
.thumb_func
rd_byte:
    ldr   r1, [r7, #W_FSIZE]
    cmp   r0, r1
    bhs   2f
    ldr   r1, [r7, #W_WINOFF]
    subs  r2, r0, r1
    ldr   r3, [r7, #W_WINLEN]
    cmp   r2, r3
    bhs   1f
    ldr   r1, =W_WIN
    adds  r1, r7
    ldrb  r0, [r1, r2]
    bx    lr
1:  push  {r0, lr}
    bl    rd_fill
    pop   {r0, r1}
    mov   lr, r1
    b     rd_byte
2:  movs  r0, #0
    mvns  r0, r0
    bx    lr

// Loads the window around file offset r0, one sector per read (a cluster
// boundary can fall anywhere).
.thumb_func
rd_fill:
    push  {r4-r6, lr}
    lsrs  r0, #9
    lsls  r0, #9
    ldr   r1, =1024
    subs  r0, r1
    bpl   1f
    movs  r0, #0
1:  str   r0, [r7, #W_WINOFF]
    ldr   r1, [r7, #W_FSIZE]
    subs  r1, r0
    ldr   r2, =0x800
    cmp   r1, r2
    bls   2f
    movs  r1, r2
2:  str   r1, [r7, #W_WINLEN]
    lsrs  r4, r0, #9                 // r4 = file sector
    ldr   r5, =W_WIN
    adds  r5, r7                     // r5 = dst
    ldr   r2, =511
    adds  r1, r2
    lsrs  r6, r1, #9                 // r6 = sectors
    blx   rd_cardTake                // card lock + bus for the reads below only
    cmp   r0, #0
    beq   5f                         // the arm7 kept the card
3:  movs  r0, r4
    bl    rd_sector
    cmp   r0, #0
    beq   4f                         // not in the cluster map: never read a wrong sector
#if GUIDE_READER_DIAG
    push  {r0}
    movs  r0, #0x1F                  // red: inside the platform sd read
    bl    rd_diag
    pop   {r0}
#endif
    movs  r1, r5
    movs  r2, #1
    ldr   r3, [r7, #W_SDREAD]
    blx   r3
#if GUIDE_READER_DIAG
    movs  r0, #0                     // black: the read returned
    bl    rd_diag
#endif
4:  adds  r4, #1
    ldr   r0, =512
    adds  r5, r0
    subs  r6, #1
    bne   3b
    blx   rd_cardGive
    pop   {r4-r6, pc}
5:  ldr   r1, =W_WIN                 // blank lines rather than stale text
    adds  r1, r7
    ldr   r2, =0x800
    movs  r0, #0
6:  stmia r1!, {r0}
    subs  r2, #4
    bne   6b
    pop   {r4-r6, pc}

// r0 = sector index in the guide file -> sd sector, or 0. Walks the FatFs
// cluster link map (guide_file_info_t: clusterShift, database, clusterMask,
// fileSize, then count + (clusters, start cluster) pairs ending in 0), like
// rom_offset_to_sd_sector_asm does for the rom.
.thumb_func
rd_sector:
    push  {r4, r5, lr}
    ldr   r5, [r7, #W_INFO]
    ldr   r1, [r5, #0]               // clusterShift
    ldr   r2, [r5, #8]               // clusterMask
    ands  r2, r0                     // sector within the cluster
    lsrs  r0, r1                     // cluster index in the file
    adds  r5, #20                    // first pair
1:  ldmia r5!, {r3, r4}              // clusters in this run, its first cluster
    cmp   r3, #0
    beq   2f
    subs  r0, r3
    bhs   1b
    adds  r0, r3
    adds  r0, r4
    subs  r0, #2
    lsls  r0, r1
    adds  r0, r2
    ldr   r3, [r7, #W_INFO]
    ldr   r3, [r3, #4]               // database
    adds  r0, r3
    pop   {r4, r5, pc}
2:  movs  r0, #0
    pop   {r4, r5, pc}
.pool

// Saves the reading position to <guide>.pos: rewrites its first sector in
// place with "<offset> <line>", spaces and a newline (GUIDE_POS_SIZE bytes, the
// guide-reader app's format; the loader made the file exactly that size).
// Runs after rd_close, so the tile backup is free to hold the sector.
.thumb_func
rd_savepos:
    push  {r4-r6, lr}
    ldr   r4, [r7, #W_INFO]
    adds  r4, #G_POSSECTOR           // r4 = &posSector
    ldr   r0, [r4]
    cmp   r0, #0
    beq   9f                         // no .pos file on the sd
    ldr   r0, [r7, #W_SDWRITE]
    cmp   r0, #0
    beq   9f                         // no sd write code on this platform
    ldr   r5, =W_BAKTILES
    adds  r5, r7                     // r5 = sector buffer
    movs  r1, r5
    ldr   r0, =0x20202020            // the text part: spaces...
    movs  r2, #GUIDE_POS_SIZE / 4
1:  stmia r1!, {r0}
    subs  r2, #1
    bne   1b
    movs  r0, #0                     // ...the rest of the sector (past the end of the file): zeros
    movs  r2, #(512 - GUIDE_POS_SIZE) / 4
2:  stmia r1!, {r0}
    subs  r2, #1
    bne   2b
    ldr   r0, [r7, #W_TOP]
    movs  r1, r5
    bl    rd_decimal
    movs  r0, #' '
    strb  r0, [r1]
    adds  r1, #1
    ldr   r0, [r7, #W_LINENO]
    bl    rd_decimal
    movs  r0, #10
    strb  r0, [r5, #GUIDE_POS_SIZE - 1]
    blx   rd_cardTake
    cmp   r0, #0
    beq   9f                         // the arm7 kept the card: not saved this time
    ldr   r0, [r4]
    movs  r1, r5
    movs  r2, #1
    ldr   r3, [r7, #W_SDWRITE]
    blx   r3
    blx   rd_cardGive
9:  pop   {r4-r6, pc}

// Writes r0 in decimal at r1 (no leading zeros), returns the end in r1.
// Subtracts powers of ten: the hardware divider belongs to the frozen game.
.thumb_func
rd_decimal:
    push  {r4-r6, lr}
    ldr   r4, 8f
7:  add   r4, pc                     // r4 = rd_pow10
    movs  r5, #0                     // r5 = a digit has been written
    movs  r6, #10                    // r6 = powers left
1:  ldmia r4!, {r3}
    movs  r2, #'0'
2:  cmp   r0, r3
    blo   3f
    subs  r0, r3
    adds  r2, #1
    b     2b
3:  cmp   r2, #'0'
    bne   4f
    cmp   r5, #0
    bne   4f
    cmp   r6, #1                     // the last digit is always written
    bne   5f
4:  strb  r2, [r1]
    adds  r1, #1
    movs  r5, #1
5:  subs  r6, #1
    bne   1b
    pop   {r4-r6, pc}
.balign 4
8:  .word rd_pow10 - (7b + 4)
rd_pow10:
    .word 1000000000, 100000000, 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1
.pool

// Takes the SDK card lock the way OS_LockCard does, then the slot-1 bus. While
// the game is frozen the only other holder can be the arm7 (its card id
// check), which lets go quickly: retry for ~150 ms. Arm code: thumb has no
// swp. r7 = work. Returns r0 = 1, or 0 when the lock never came free.
// Clobbers r0-r3, r12.
.arm
.balign 4
.type rd_cardTake, %function
rd_cardTake:
    ldr   r1, [r7, #W_LOCK]
    mov   r3, #0x200000
1:  mov   r2, #GUIDE_LOCK_ID
    swp   r2, r2, [r1]               // lockFlag = ours; r2 = what it was
    cmp   r2, #0
    beq   2f
    subs  r3, r3, #1                 // held: its unlock clears our id, try again
    bne   1b
    mov   r0, #0
    bx    lr
2:  mov   r2, #GUIDE_LOCK_ID
    strh  r2, [r1, #4]               // ownerID
    mov   r12, #0x04000000
    add   r12, r12, #0x200
    ldrh  r2, [r12, #4]              // EXMEMCNT: save, slot-1 bus to the arm9
    strh  r2, [r7, #W_EXMEM]
    bic   r2, r2, #0x800
    strh  r2, [r12, #4]
    sub   r12, r12, #0x60
    ldrh  r2, [r12]                  // AUXSPICNT: save (the sd read sets it)
    strh  r2, [r7, #W_AUXSPI]
    mov   r0, #1
    bx    lr

// Undoes rd_cardTake like OS_UnlockCard: card regs back, bus to the arm7,
// lock free. Clobbers r1, r2, r12.
.type rd_cardGive, %function
rd_cardGive:
    mov   r12, #0x04000000
    add   r12, r12, #0x1A0
    ldrh  r2, [r7, #W_AUXSPI]
    strh  r2, [r12]
    ldrh  r2, [r7, #W_EXMEM]
    strh  r2, [r12, #0x64]           // EXMEMCNT
    ldr   r1, [r7, #W_LOCK]
    mov   r2, #0
    strh  r2, [r1, #4]
    str   r2, [r1]
    bx    lr

// 8x8 ASCII font 0x20-0x7F, 1 bit per pixel: libnds default_fontTiles
// (Copyright (C) 2005-2021 Michael Noland, Jason Rogers, Dave Murphy et al.,
// zlib license), the font the standalone guide-reader app shows.
.balign 4
rd_font:
    .incbin "arm9/source/patches/arm9/guide/GuideReaderFont.bin"
#endif
#endif

.end
