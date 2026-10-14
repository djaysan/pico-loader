#pragma once
#include "sections.h"

DEFINE_SECTION_SYMBOLS(patch_guideoverlay9);

// guide_data field offsets. Keep in sync with the .equ list in
// GuideOverlay9PatchCode.s.
#define GD_MARKER      0x00
#define GD_INSTALLED   0x04
#define GD_DISPATCHER  0x08
#define GD_DISPRETURN  0x0C
#define GD_OVERLAYSTUB 0x10
#define GD_FRAMECOUNT  0x14
#define GD_FREEZECOUNT 0x18
#define GD_LASTKEYS    0x1C
#define GD_SAVEDA      0x20
#define GD_SAVEDB      0x24
#define GD_CARDENTRY   0x28
#define GD_ORIGINSN0   0x2C

extern "C" void guide_tramp(void);
extern "C" void overlay_stub(void);

// Shared state block; C bakes some fields before the blob is copied.
extern "C" u8 guide_data[];

// Literal slots baked in before the blob is copied to its resident location.
extern "C" u32 guide_replay_slot;      // displaced card instruction 0 to replay
extern "C" u32 guide_replay_slot1;     // displaced card instruction 1 to replay
extern "C" u32 guide_replay_lit;       // value instruction 1's pc-relative ldr loads
extern "C" u32 guide_cardReturn_lit;   // runtime card entry + 8
extern "C" u32 guide_dataAddr_lit;     // absolute runtime address of guide_data
extern "C" u32 guide_rebootEntry_lit;  // patched OS_ResetSystem tail, or 0
