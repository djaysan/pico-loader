.cpu arm7tdmi
.section "patch_guidemonitor", "ax"
.syntax unified

// In-game guide overlay, phase 1+2 debug monitor.
//
// Hooked at the tail of the game's arm7 OSi_IrqVBlank (the same site as the
// cheat engine). Entry contract: sp points to two words, the second being the
// return address; r0-r3 and r12 are free, r4 and up must be preserved.
//
// While L+R+Select is held and a guide cluster map was published, plays a
// PSG beep on sound channel 13 (audible on melonDS and hardware). Sound
// state is restored on release.
//
// No PMIC access: the PMIC shares the SPI bus with the touchscreen, and a
// read-modify-write raced by the game's touch traffic can write back a
// glitched value that mutes the amplifier persistently (seen in Phantom
// Hourglass) or worse (bit 6 is power off). Sound registers are safe.
//
// Chains to the cheat engine when cheats are active, otherwise performs the
// original epilogue itself. This code is position independent (copied to
// reserved main memory), so labels are only referenced pc-relative.

.arm
.global guidemonitor_entry_arm
.type guidemonitor_entry_arm, %function
guidemonitor_entry_arm:
    adr r12, guidemonitor_entry + 1
    bx r12

.thumb
.global guidemonitor_entry
.type guidemonitor_entry, %function
guidemonitor_entry:
    push {r4}

#if GUIDE_OVERLAY_STAGE_A
    // Hardware Stage-A diagnostic (phase 3): beep a periodic blip whenever the
    // arm9 overlay is firing - i.e. GD_FRAMECOUNT is advancing in shared main
    // memory - with no L+R+Select needed. So a blip during normal gameplay =
    // Stage A installed + ITCM dispatcher hooked + firing every frame. Kept
    // distinct from the combo tone: channel 12, higher pitch, blip not steady.
    // guide_data lives in the arm9 patch heap (shared main RAM), so the arm7
    // reads it at the same address. No PMIC, no master/power writes.
    ldr r0, guidemonitor_guideDataPtr
    cmp r0, #0
    beq diag_done                   // overlay not installed -> nothing
    ldr r1, [r0, #0x14]             // GD_FRAMECOUNT
    adr r4, diag_state
    ldr r2, [r4]                    // last frame count seen
    str r1, [r4]                    // remember current
    cmp r1, r2
    beq diag_off                    // not advancing -> not firing
    ldr r2, [r4, #4]               // blip phase (period 48 frames)
    adds r2, #1
    cmp r2, #48
    blt 1f
    movs r2, #0
1:
    str r2, [r4, #4]
    cmp r2, #6
    bge diag_off                    // off part of the cycle
    ldr r1, =0x040004C0             // SOUND12CNT
    ldr r0, =0x0000FBE9             // SOUNDxTMR, ~2 kHz (combo tone is ~1 kHz)
    strh r0, [r1, #8]
    ldr r0, =0xE340407F             // start | PSG | 50% duty | center | full vol
    str r0, [r1]
    b diag_done
diag_off:
    ldr r1, =0x040004C0
    movs r0, #0
    str r0, [r1]                    // channel 12 off
diag_done:
#endif

    ldr r0, guidemonitor_guideInfoPtr
    cmp r0, #0
    beq monitor_end

    adr r4, monitor_state
    ldr r0, =0x04000130 // REG_KEYINPUT
    ldrh r0, [r0]
    ldr r1, =0x304 // L | R | Select (active low)
    ands r0, r1
    beq combo_held

    // == combo not held ==
    ldr r0, [r4]
    cmp r0, #0
    beq monitor_end // was already released

    // release edge: stop the beep, restore REG_SOUNDCNT
    movs r0, #0
    str r0, [r4]
    ldr r1, =0x040004D0 // sound channel 13
    str r0, [r1]
    ldr r2, [r4, #4]
    ldr r1, =0x04000500 // REG_SOUNDCNT
    strh r2, [r1]
    b monitor_end

combo_held:
    ldr r0, [r4]
    cmp r0, #0
    bne monitor_end // already beeping

    // press edge: save REG_SOUNDCNT, force sound on, start the PSG beep
    movs r0, #1
    str r0, [r4]
    ldr r1, =0x04000304 // REG_POWERCNT7
    ldrh r0, [r1]
    movs r2, #1 // sound power on (not restored, harmless)
    orrs r0, r2
    strh r0, [r1]
    ldr r1, =0x04000500 // REG_SOUNDCNT
    ldrh r0, [r1]
    str r0, [r4, #4]
    ldr r0, =0x807F // master enable, full volume
    strh r0, [r1]
    ldr r1, =0x040004D0 // sound channel 13
    ldr r0, =0xF7D2 // ~1kHz tone (8kHz sample rate, 8 samples per period)
    strh r0, [r1, #8] // SOUNDxTMR
    ldr r0, =0xE340407F // start | PSG | 50% duty | center pan | full volume
    str r0, [r1]

monitor_end:
    pop {r4}
    ldr r0, guidemonitor_chainPtr
    cmp r0, #0
    beq no_chain
    bx r0 // cheat engine entry, stack frame passed through intact
no_chain:
    pop {r0, r1}
    bx r1

.balign 4

monitor_state:
    .word 0 // combo held flag
    .word 0 // saved REG_SOUNDCNT

.global guidemonitor_guideInfoPtr
guidemonitor_guideInfoPtr:
    .word 0

.global guidemonitor_chainPtr
guidemonitor_chainPtr:
    .word 0

#if GUIDE_OVERLAY_STAGE_A
diag_state:
    .word 0 // last GD_FRAMECOUNT seen
    .word 0 // blip phase counter

.global guidemonitor_guideDataPtr
guidemonitor_guideDataPtr:
    .word 0 // baked: runtime address of the arm9 overlay guide_data
#endif

.pool
.end
