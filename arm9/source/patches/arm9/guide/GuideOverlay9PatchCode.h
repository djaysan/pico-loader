#pragma once
#include "sections.h"

DEFINE_SECTION_SYMBOLS(patch_guideoverlay9);

extern "C" void guideoverlay9_entry_sdk2(void);
extern "C" void guideoverlay9_entry_sdk5(void);
extern "C" void guideoverlay9_entry_sdk4t(void);

// Literal slots inside the stub, baked in before it is copied to its
// resident location.
extern "C" u32 guideoverlay9_sdk2Return;
extern "C" u32 guideoverlay9_sdk5Return;
extern "C" u32 guideoverlay9_sdk5PoolValue;
extern "C" u32 guideoverlay9_sdk4tReturn;
extern "C" u32 guideoverlay9_sdk4tPoolValue;
