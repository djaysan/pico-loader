#pragma once
#include "patches/PatchContext.h"

/// @brief Finds the arm9 per-frame vblank wait function. Call during the
///        arm9 patch pass; a miss is never fatal (the overlay degrades to
///        the arm7 beep monitor only).
void GuideOverlay9FindHookSite(PatchContext& patchContext);

/// @brief Reserves stub space from the arm9 patch heap. Call after
///        TryPerformPatches so existing patches get their space first;
///        when nothing is left the overlay degrades to beep-only. The
///        heap lives inside the game's own code image, which the arm9
///        MPU allows executing from — unlike the arm7's main memory
///        arena, where the first attempt at this stub died with a
///        prefetch abort at boot.
void GuideOverlay9ReserveStub(PatchContext& patchContext);

/// @brief Bakes the variant literals into the overlay stub, copies it to
///        the reserved heap space and detours the vblank wait entry to
///        it. Call only when a guide is present. No-ops when the site
///        was not found or no stub space could be reserved.
void GuideOverlay9Install();
