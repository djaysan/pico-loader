#pragma once
#include "sections.h"

DEFINE_SECTION_SYMBOLS(patch_guidemonitor);

extern "C" void guidemonitor_entry_arm(void);
extern "C" void guidemonitor_entry(void);

extern const void* guidemonitor_guideInfoPtr;
extern const void* guidemonitor_chainPtr;
#if GUIDE_ARENA_PROOF
extern u32 guidemonitor_reserveScanStart;
extern u32 guidemonitor_reserveEnd;
#endif
