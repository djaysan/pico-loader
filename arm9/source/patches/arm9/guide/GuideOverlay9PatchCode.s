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
#endif

.end
