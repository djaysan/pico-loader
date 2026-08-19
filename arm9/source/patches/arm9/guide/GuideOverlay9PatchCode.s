.cpu arm946e-s
.section "patch_guideoverlay9", "ax"
.syntax unified

// In-game guide overlay, phase 3 milestone 1: freeze + blank + resume.
//
// Detours the entry of the SDK's per-frame vblank wait function on the
// arm9 (located by full-prologue signature; the function takes no
// arguments in all known variants, so r0-r3 are free at entry). This is
// thread context with IRQs enabled: while frozen, sound and the game's
// interrupt handlers keep running, and on release the game just sees one
// very long vblank wait.
//
// While L+R+Select is held: save both MASTER_BRIGHT registers, force
// both engines to black, spin polling REG_KEYINPUT. On release: restore
// MASTER_BRIGHT exactly, then re-execute the two displaced prologue
// instructions of the variant and jump back into the original function.
// Displaced pc-relative loads are replayed via literal slots the
// installer bakes in (GuideOverlay9Install).
//
// The state word guards against a second thread entering the wait
// function while frozen: it replays straight through without freezing.
//
// Position independent (copied to reserved main memory).

.arm

// == shared combo/freeze core; preserves r0-r3, returns via lr ==
overlay_core:
    push {r0-r3}
    adr r12, overlay_state
    ldr r0, [r12]
    cmp r0, #0
    bne core_done // reentered while frozen

    ldr r1, =0x04000130 // REG_KEYINPUT
    ldr r2, =0x304 // L | R | Select (active low)
    ldrh r0, [r1]
    ands r0, r0, r2
    bne core_done // combo not (fully) held

    // == freeze ==
    mov r0, #1
    str r0, [r12]
    ldr r3, =0x0400006C // MASTER_BRIGHT engine A
    ldrh r0, [r3]
    str r0, [r12, #4] // save A
    ldr r3, =0x0400106C // MASTER_BRIGHT engine B
    ldrh r0, [r3]
    str r0, [r12, #8] // save B
    ldr r0, =0x8010 // force brightness down by 16 = black
    ldr r3, =0x0400006C
    strh r0, [r3]
    ldr r3, =0x0400106C
    strh r0, [r3]

spin:
    ldrh r0, [r1]
    ands r0, r0, r2
    beq spin // all three still held

    // == release: restore and resume ==
    ldr r3, =0x0400006C
    ldr r0, [r12, #4]
    strh r0, [r3]
    ldr r3, =0x0400106C
    ldr r0, [r12, #8]
    strh r0, [r3]
    mov r0, #0
    str r0, [r12]

core_done:
    pop {r0-r3}
    bx lr

// == sdk2 variant (arm) ==
// displaced: push {r4, r5, lr}; sub sp, #4 (both position independent)
.global guideoverlay9_entry_sdk2
.type guideoverlay9_entry_sdk2, %function
guideoverlay9_entry_sdk2:
    push {lr}
    bl overlay_core
    pop {lr}
    push {r4, r5, lr}
    sub sp, sp, #4
    ldr pc, guideoverlay9_sdk2Return

// == sdk5 variant (arm) ==
// displaced: push {r4, r5, r6, lr}; ldr r0, [pc-relative pool]
.global guideoverlay9_entry_sdk5
.type guideoverlay9_entry_sdk5, %function
guideoverlay9_entry_sdk5:
    push {lr}
    bl overlay_core
    pop {lr}
    push {r4, r5, r6, lr}
    ldr r0, guideoverlay9_sdk5PoolValue
    ldr pc, guideoverlay9_sdk5Return

// == sdk4 thumb variant; entered in arm state via ldr r1/bx r1 hook ==
// displaced: push {r3, r4, r5, lr}; ldr r0, [pool]; ldrh r1, [r0]; cmp r1, #0
// The cmp flags survive the bx back into the original thumb code.
.global guideoverlay9_entry_sdk4t
.type guideoverlay9_entry_sdk4t, %function
guideoverlay9_entry_sdk4t:
    push {lr}
    bl overlay_core
    pop {lr}
    push {r3, r4, r5, lr}
    ldr r0, guideoverlay9_sdk4tPoolValue
    ldrh r1, [r0]
    cmp r1, #0
    ldr r12, guideoverlay9_sdk4tReturn
    bx r12

.balign 4

overlay_state:
    .word 0 // frozen reentry guard
    .word 0 // saved MASTER_BRIGHT A
    .word 0 // saved MASTER_BRIGHT B

// Literal slots baked in by GuideOverlay9Install before the copy.
.global guideoverlay9_sdk2Return
guideoverlay9_sdk2Return:
    .word 0
.global guideoverlay9_sdk5Return
guideoverlay9_sdk5Return:
    .word 0
.global guideoverlay9_sdk5PoolValue
guideoverlay9_sdk5PoolValue:
    .word 0
.global guideoverlay9_sdk4tReturn
guideoverlay9_sdk4tReturn:
    .word 0
.global guideoverlay9_sdk4tPoolValue
guideoverlay9_sdk4tPoolValue:
    .word 0

.pool
.end
