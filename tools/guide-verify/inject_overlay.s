.cpu arm946e-s
.syntax unified
.arm
.text
.global _start

// Self-contained injectable overlay for GDB verification of the phase-3
// Stage-B mechanism. Position independent; copied into free ITCM. Detours
// the ITCM dispatcher entry (the two displaced instructions
// `sub lr,lr,#4` / `stmfd sp!,{r0-r3,r12,lr}` are replayed here). Chains to
// dispatcher+8 (0x010001E0 on Castlevania DoS) which recomputes r0-r3,r12.
//
// Data block (via adr, PIC):
//   +0x00 frameCount   incremented every dispatch (proves per-frame firing)
//   +0x04 freezeCount  incremented on each freeze entry
//   +0x08 lastKeys     last REG_KEYINPUT
//   +0x0C savedA       saved MASTER_BRIGHT A
//   +0x10 savedB       saved MASTER_BRIGHT B
//   +0x14 forceFreeze  gdb-settable: nonzero forces the freeze deterministically

_start:
overlay_stub:
    sub   lr, lr, #4                 // displaced dispatcher insn 1
    stmfd sp!, {r0-r3, r12, lr}      // displaced dispatcher insn 2 (interrupted ctx)
    stmfd sp!, {r4-r8}               // private scratch
    adr   r8, guide_data

    ldr   r0, [r8, #0x00]
    add   r0, r0, #1
    str   r0, [r8, #0x00]            // frameCount++

    ldr   r1, kKeyInput              // 0x04000130
    ldr   r2, kKeyMask               // 0x304
    ldrh  r0, [r1]
    str   r0, [r8, #0x08]            // lastKeys

    ldr   r3, [r8, #0x14]
    cmp   r3, #0
    bne   do_freeze                  // forceFreeze set -> freeze

    ands  r0, r0, r2
    bne   chain                      // combo not held -> run normally

do_freeze:
    ldr   r0, [r8, #0x04]
    add   r0, r0, #1
    str   r0, [r8, #0x04]            // freezeCount++
    ldr   r4, kMbA                   // 0x0400006C
    ldr   r5, kMbB                   // 0x0400106C
    ldrh  r6, [r4]
    ldrh  r7, [r5]
    str   r6, [r8, #0x0C]            // savedA
    str   r7, [r8, #0x10]            // savedB
    ldr   r0, kBlack                 // 0x8010
    strh  r0, [r4]
    strh  r0, [r5]
spin:
    ldr   r3, [r8, #0x14]
    cmp   r3, #0
    bne   spin                       // stay frozen while forceFreeze set
    ldrh  r0, [r1]
    ands  r0, r0, r2
    beq   spin                       // or while combo still held
    strh  r6, [r4]                   // release: restore exactly
    strh  r7, [r5]

chain:
    ldr   r0, kDispReturn            // 0x010001E0 dispatcher+8
    ldmfd sp!, {r4-r8}
    mov   pc, r0

.balign 4
kKeyInput:   .word 0x04000130
kKeyMask:    .word 0x00000304
kMbA:        .word 0x0400006C
kMbB:        .word 0x0400106C
kBlack:      .word 0x00008010
kDispReturn: .word 0x010001E0

.balign 4
guide_data:
    .word 0   // frameCount
    .word 0   // freezeCount
    .word 0   // lastKeys
    .word 0   // savedA
    .word 0   // savedB
    .word 0   // forceFreeze
