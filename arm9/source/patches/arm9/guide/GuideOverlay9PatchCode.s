.cpu arm946e-s
.section "patch_guideoverlay9", "ax"
.syntax unified

// Stage B (the ITCM dispatcher hook) is what Stage A was built for, but an
// exit-only build wants the residency without the ITCM write, so it gets its
// own switch. Defaulting to Stage A keeps every existing build identical.
#ifndef GUIDE_OVERLAY_STAGE_A
#define GUIDE_OVERLAY_STAGE_A 0
#endif
#ifndef GUIDE_OVERLAY_STAGE_B
#define GUIDE_OVERLAY_STAGE_B GUIDE_OVERLAY_STAGE_A
#endif
#ifndef EXIT_TO_LAUNCHER
#define EXIT_TO_LAUNCHER 0
#endif

// In-game guide overlay, phase 3 milestone 1: two-stage runtime bootstrap.
//
// The arm9 per-frame IRQ dispatcher is built at runtime inside ITCM by the
// game's OS_Init; it is NOT present in the rom image, so the loader cannot
// hook it by image patching (see PHASE3-FINDINGS.md). Instead:
//
//   Stage A (guide_tramp): the loader image-patches the entry of the card
//     read function (CARDi_ReadCard, which the loader already locates) with a
//     branch to guide_tramp. That runs during gameplay AFTER OS_Init has
//     populated ITCM. It calls guide_installer once, replays the displaced
//     first instruction, then continues the original function.
//
//   EXIT_TO_LAUNCHER (guide_exitCheck): Stage A on its own is already enough
//     to leave a game. On every card read it samples the keys and, while
//     L+R+Start+Select is held, jumps to the OS_ResetSystem tail the loader
//     has already patched to reboot into Pico Loader. No ITCM write and no
//     per-frame hook, so it is the cheapest hardware proof that Stage A code
//     really is resident during gameplay.
//
//   Stage B (guide_installer): at runtime it scans ITCM for the dispatcher
//     prologue (sub lr,lr,#4 ; stmfd sp!,{r0-r3,r12,lr}), and once found
//     overwrites those two instructions with a jump into overlay_stub, which
//     is the real per-frame hook. Idempotent via installedFlag.
//
//   overlay_stub: runs at the head of every IRQ dispatch. While L+R+Select
//     is held it saves both MASTER_BRIGHT registers, forces both engines to
//     black and spins polling the keys (that is the freeze; the arm7 keeps
//     running). On release it restores MASTER_BRIGHT exactly, then replays
//     the two displaced dispatcher instructions and jumps back in, so the
//     game resumes exactly. When the combo is not held it chains straight
//     through every frame. No VRAM/palette/SD/PMIC access.
//
// Whole blob is position independent (copied to reserved patch-heap memory).
// All shared state lives in guide_data; code reaches it through the single
// baked absolute pointer in guide_dataAddr_lit. Keep the GD_* offsets below
// in sync with GuideOverlay9.h.

.equ GD_MARKER,      0x00   // progress bits (runtime): bit0 installer ran, bit1 dispatcher patched, bit2 overlay fired
.equ GD_INSTALLED,   0x04   // 0/1 (runtime)
.equ GD_DISPATCHER,  0x08   // dispatcher addr found in ITCM (runtime)
.equ GD_DISPRETURN,  0x0C   // dispatcher addr + 8 (runtime; overlay chains here)
.equ GD_OVERLAYSTUB, 0x10   // baked: runtime address of overlay_stub
.equ GD_FRAMECOUNT,  0x14   // runtime: overlay increments every dispatch
.equ GD_FREEZECOUNT, 0x18   // runtime: overlay increments on each freeze entry
.equ GD_LASTKEYS,    0x1C   // runtime: last REG_KEYINPUT read
.equ GD_SAVEDA,      0x20   // runtime: saved MASTER_BRIGHT engine A during freeze
.equ GD_SAVEDB,      0x24   // runtime: saved MASTER_BRIGHT engine B during freeze
.equ GD_CARDENTRY,   0x28   // baked debug: card function address hooked
.equ GD_ORIGINSN0,   0x2C   // baked debug: original displaced card instruction

.arm

// ======================= Stage A: card-entry trampoline =======================
// Entered via `b guide_tramp` written over the card function's first
// instruction. r0-r3 hold the card args, lr the game caller. Preserve
// everything; run the installer once; replay the displaced instruction; go.
.global guide_tramp
.type guide_tramp, %function
guide_tramp:
    stmfd sp!, {r0-r3, r12, lr}
#if EXIT_TO_LAUNCHER
    bl    guide_exitCheck
#endif
#if GUIDE_OVERLAY_STAGE_B
    bl    guide_installer
#endif
    ldmfd sp!, {r0-r3, r12, lr}
.global guide_replay_slot
guide_replay_slot:
    nop                              // C bakes the displaced card instruction here
    ldr   pc, guide_cardReturn_lit   // -> card function + 4

.balign 4
.global guide_cardReturn_lit
guide_cardReturn_lit:
    .word 0                          // C bakes: card entry + 4
.global guide_dataAddr_lit
guide_dataAddr_lit:
    .word 0                          // C bakes: absolute address of guide_data
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

#if GUIDE_OVERLAY_STAGE_B
// ======================= Stage B: runtime installer =======================
// Scan ITCM for the dispatcher prologue; on first find, detour it into
// overlay_stub. Idempotent.
.type guide_installer, %function
guide_installer:
    stmfd sp!, {r0-r8, lr}
    ldr   r8, guide_dataAddr_lit
    // marker bit0: installer ran
    ldr   r0, [r8, #GD_MARKER]
    orr   r0, r0, #1
    str   r0, [r8, #GD_MARKER]

    ldr   r0, [r8, #GD_INSTALLED]
    cmp   r0, #0
    bne   gi_ret

    mov   r1, #0x01000000            // ITCM scan start
    add   r2, r1, #0x8000            // ITCM scan end (32KB)
    ldr   r5, gi_sig0                // sub lr,lr,#4
    ldr   r6, gi_sig1               // stmfd sp!,{r0-r3,r12,lr}
gi_loop:
    ldr   r3, [r1]
    cmp   r3, r5
    bne   gi_cont
    ldr   r3, [r1, #4]
    cmp   r3, r6
    beq   gi_found
gi_cont:
    add   r1, r1, #4
    cmp   r1, r2
    blo   gi_loop
    b     gi_ret                     // not present yet; try again next card read

gi_found:
    str   r1, [r8, #GD_DISPATCHER]
    add   r3, r1, #8
    str   r3, [r8, #GD_DISPRETURN]   // overlay chains to dispatcher+8
    ldr   r0, [r8, #GD_OVERLAYSTUB]  // baked runtime address of overlay_stub
    ldr   r3, gi_ldrpc               // ldr pc,[pc,#-4]
    str   r3, [r1]                   // overwrite `sub lr,lr,#4`
    str   r0, [r1, #4]               // overwrite `stmfd ...` with target word
    mov   r0, #1
    str   r0, [r8, #GD_INSTALLED]
    ldr   r0, [r8, #GD_MARKER]
    orr   r0, r0, #2                 // marker bit1: dispatcher patched
    str   r0, [r8, #GD_MARKER]
    // publish the ITCM write + make the icache refetch it
    mov   r0, #0
    mcr   p15, 0, r0, c7, c10, 4     // drain write buffer
    mcr   p15, 0, r0, c7, c5, 0      // invalidate entire icache

gi_ret:
    ldmfd sp!, {r0-r8, lr}
    bx    lr

.balign 4
gi_sig0:
    .word 0xE24EE004                 // sub lr, lr, #4
gi_sig1:
    .word 0xE92D500F                 // stmfd sp!, {r0-r3, r12, lr}
gi_ldrpc:
    .word 0xE51FF004                 // ldr pc, [pc, #-4]

// ======================= per-frame overlay stub =======================
// Reached from the detoured dispatcher entry, in IRQ mode with IRQs masked.
// The stack frame it leaves for dispatcher+8 must be exactly {r0-r3,r12,lr}.
.global overlay_stub
.type overlay_stub, %function
overlay_stub:
    sub   lr, lr, #4                 // displaced dispatcher insn 1
    stmfd sp!, {r0-r3, r12, lr}      // displaced dispatcher insn 2 (interrupted ctx)
    stmfd sp!, {r4-r8}               // private scratch (restored before chaining)
    ldr   r8, guide_dataAddr_lit

    ldr   r0, [r8, #GD_FRAMECOUNT]   // proves per-frame firing over gdb
    add   r0, r0, #1
    str   r0, [r8, #GD_FRAMECOUNT]
    ldr   r0, [r8, #GD_MARKER]
    orr   r0, r0, #4                 // marker bit2: overlay fired
    str   r0, [r8, #GD_MARKER]

#if !GUIDE_OVERLAY_FREEZE
    // Diagnostic build: the cacheless arm7 monitor reads GD_FRAMECOUNT from
    // main memory, so clean the guide_data d-cache line and drain the write
    // buffer here (GD_MARKER at +0 and GD_FRAMECOUNT at +0x14 share the line).
    mcr   p15, 0, r8, c7, c10, 1     // clean d-cache line by MVA (guide_data)
    mcr   p15, 0, r8, c7, c10, 4     // drain write buffer
#endif

#if GUIDE_OVERLAY_FREEZE
    // ---- freeze/blank/resume path (proven; opt-in via GUIDE_OVERLAY_FREEZE) ----
    ldr   r1, ov_keyinput            // 0x04000130 REG_KEYINPUT
    ldr   r2, ov_keymask             // 0x304 = L | R | Select (active low)
    ldrh  r0, [r1]
    str   r0, [r8, #GD_LASTKEYS]
    ands  r0, r0, r2
    bne   ov_chain                   // any of the three not held -> run normally

    ldr   r0, [r8, #GD_FREEZECOUNT]
    add   r0, r0, #1
    str   r0, [r8, #GD_FREEZECOUNT]
    ldr   r4, ov_mbA                 // 0x0400006C MASTER_BRIGHT engine A
    ldr   r5, ov_mbB                 // 0x0400106C MASTER_BRIGHT engine B
    ldrh  r6, [r4]                   // save A
    ldrh  r7, [r5]                   // save B
    str   r6, [r8, #GD_SAVEDA]
    str   r7, [r8, #GD_SAVEDB]
    ldr   r0, ov_black               // 0x8010 = brightness down by 16 (black)
    strh  r0, [r4]
    strh  r0, [r5]
ov_spin:
    ldrh  r0, [r1]
    ands  r0, r0, r2
    beq   ov_spin                    // all three still held -> stay frozen

    // ---- release: restore exactly ----
    strh  r6, [r4]
    strh  r7, [r5]
#endif
    // In the default (diagnostic) build there is NO freeze and NO display
    // register access: the stub only advances GD_FRAMECOUNT / GD_MARKER above,
    // which the arm7 monitor observes to prove the hook fires every frame.

ov_chain:
    ldr   r0, [r8, #GD_DISPRETURN]   // dispatcher + 8 (loaded before r8 is restored)
    ldmfd sp!, {r4-r8}               // restore private scratch (r0 preserved)
    mov   pc, r0                     // resume the original dispatcher; it recomputes r0-r3,r12

.balign 4
#if GUIDE_OVERLAY_FREEZE
ov_keyinput:
    .word 0x04000130
ov_keymask:
    .word 0x00000304
ov_mbA:
    .word 0x0400006C
ov_mbB:
    .word 0x0400106C
ov_black:
    .word 0x00008010
#endif
#endif // GUIDE_OVERLAY_STAGE_B

#if GUIDE_OVERLAY_STAGE_B
// ======================= shared state (guide_data) =======================
// Layout must match the GD_* equ  offsets above and GuideOverlay9.h.
// Only Stage B and the arm7 diagnostic read it, so an exit-only build leaves
// it out entirely - the arm9 patch heap is 0x500 bytes shared with every other
// patch, and 48 bytes of state nothing reads is 48 bytes that could be the
// difference between the blob fitting and not.
.balign 4
.global guide_data
guide_data:
    .word 0   // GD_MARKER
    .word 0   // GD_INSTALLED
    .word 0   // GD_DISPATCHER
    .word 0   // GD_DISPRETURN
    .word 0   // GD_OVERLAYSTUB (baked)
    .word 0   // GD_FRAMECOUNT
    .word 0   // GD_FREEZECOUNT
    .word 0   // GD_LASTKEYS
    .word 0   // GD_SAVEDA
    .word 0   // GD_SAVEDB
    .word 0   // GD_CARDENTRY (baked debug)
    .word 0   // GD_ORIGINSN0 (baked debug)
#endif // GUIDE_OVERLAY_STAGE_B

.end
