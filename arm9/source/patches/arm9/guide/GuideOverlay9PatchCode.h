#pragma once
#include "sections.h"

DEFINE_SECTION_SYMBOLS(patch_guideoverlay9);

extern "C" void guide_tramp(void);

// Literal slots baked in before the blob is copied to its resident location.
extern "C" u32 guide_replay_slot;      // displaced card instruction 0 to replay
extern "C" u32 guide_replay_slot1;     // displaced card instruction 1 to replay
extern "C" u32 guide_replay_lit;       // value instruction 1's pc-relative ldr loads
extern "C" u32 guide_cardReturn_lit;   // runtime card entry + 8
extern "C" u32 guide_rebootEntry_lit;  // patched OS_ResetSystem tail, or 0
extern "C" u32 guide_irqTable_lit;     // GUIDE_IPC_FREEZE: the game's OS_IRQTable, or 0
extern "C" u32 guide_work_lit;         // GUIDE_READER: the reader's work area, or 0
extern "C" u32 guide_sdRead_lit;       // GUIDE_READER: platform sector read function
extern "C" u32 guide_sdWrite_lit;      // GUIDE_READER: platform sector write function, or 0
extern "C" u32 guide_cardLock_lit;     // GUIDE_READER: the SDK card lock word
extern "C" u32 guide_info_lit;         // GUIDE_READER: the guide cluster map (arm7 pass)
