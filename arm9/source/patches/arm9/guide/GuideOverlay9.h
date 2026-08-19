#pragma once
#include "patches/PatchContext.h"

/// @brief Finds the arm9 per-frame vblank wait function. Call during the
///        arm9 patch pass; a miss is never fatal (the overlay degrades to
///        the arm7 beep monitor only).
void GuideOverlay9FindHookSite(PatchContext& patchContext);

/// @brief Bakes the variant literals into the overlay stub, copies it to
///        \p target (reserved main memory, loader-visible address) and
///        detours the vblank wait entry to \p runTarget (the same memory
///        at its canonical game-visible address). Call after the arm7
///        patch pass reserved the target. No-ops when no variant matched.
void GuideOverlay9Install(void* target, void* runTarget);
