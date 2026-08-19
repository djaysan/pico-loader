#pragma once
#include "patches/PatchContext.h"

/// @brief Finds the arm9 OSi_IrqVBlank hook site. Call during the arm9
///        patch pass; a miss is never fatal (the overlay degrades to the
///        arm7 beep monitor only).
void GuideOverlay9FindHookSite(PatchContext& patchContext);

/// @brief Copies the resident overlay stub to \p target (reserved main
///        memory) and hooks the arm9 vblank tail to it. Call after the
///        arm7 patch pass reserved the target. No-ops with a log line
///        when the hook site was not found, or when the bytes at the hook
///        offset do not look like the expected epilogue (never risk a
///        blind overwrite mid-function on hardware).
void GuideOverlay9Install(void* target);
