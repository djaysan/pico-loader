.cpu arm946e-s
.section "patch_guideoverlay9", "ax"
.syntax unified

// In-game guide overlay, phase 3 milestone 1: freeze + blank + resume.
//
// Hooked at the tail of the game's arm9 OSi_IrqVBlank (same signatures as
// the arm7 cheat engine hook; the SDK OS library is built for both CPUs).
// Entry contract: sp points to two words, the second being the return
// address; r0-r3 and r12 are free, r4 and up must be preserved.
//
// While L+R+Select is held: save both MASTER_BRIGHT registers, force both
// engines to black, and spin right here in the VBlank handler polling
// REG_KEYINPUT. The game's arm9 is frozen for the duration (IRQs stay
// masked in handler context); the arm7 keeps running, so sound continues
// and the phase 2 beep doubles as a "frozen, not crashed" indicator.
// On release: restore MASTER_BRIGHT exactly and fall out through the
// original epilogue. No VRAM, palette or SD access in this milestone.
//
// The state word is a reentry guard only: if the SDK ever re-enters the
// VBlank handler while we spin, the nested call bails out immediately
// instead of stacking a second spin loop.
//
// Position independent (copied to reserved main memory); labels are only
// referenced pc-relative.

.arm
.global guideoverlay9_entry_arm
.type guideoverlay9_entry_arm, %function
guideoverlay9_entry_arm:
    adr r12, guideoverlay9_entry + 1
    bx r12

.thumb
.global guideoverlay9_entry
.type guideoverlay9_entry, %function
guideoverlay9_entry:
    push {r4-r7}

    adr r4, overlay_state
    ldr r0, [r4]
    cmp r0, #0
    bne overlay_exit // reentered while frozen

    ldr r5, =0x04000130 // REG_KEYINPUT
    ldrh r0, [r5]
    ldr r1, =0x304 // L | R | Select (active low)
    ands r0, r1
    bne overlay_exit // combo not (fully) held

    // == freeze ==
    movs r0, #1
    str r0, [r4]
    ldr r6, =0x0400006C // MASTER_BRIGHT engine A
    ldr r7, =0x0400106C // MASTER_BRIGHT engine B
    ldrh r2, [r6] // save both
    ldrh r3, [r7]
    ldr r0, =0x8010 // force brightness down by 16 = black
    strh r0, [r6]
    strh r0, [r7]

spin:
    ldrh r0, [r5]
    ldr r1, =0x304
    ands r0, r1
    beq spin // all three still held

    // == release: restore and resume ==
    strh r2, [r6]
    strh r3, [r7]
    movs r0, #0
    str r0, [r4]

overlay_exit:
    pop {r4-r7}
    pop {r0, r1}
    bx r1

.balign 4

overlay_state:
    .word 0 // frozen reentry guard

.pool
.end
