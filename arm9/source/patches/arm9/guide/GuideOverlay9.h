#pragma once
#include "patches/PatchContext.h"

/// @brief Installs the phase-3 two-stage guide overlay bootstrap.
///
/// The arm9 per-frame IRQ dispatcher is built at runtime in ITCM and is not
/// present in the rom image, so it cannot be hooked at patch time. Instead
/// this places a resident blob and image-patches the entry of the card read
/// function (already located by the loader) with a branch into it. At runtime
/// the blob's installer scans ITCM for the dispatcher and detours it into the
/// per-frame overlay stub (freeze + blank + resume). See PHASE3-FINDINGS.md
/// and GuideOverlay9PatchCode.s.
///
/// @param patchContext  The arm9 patch context (for the patch heap).
/// @param cardiReadCard The card read function entry the loader found, or
///                      nullptr to skip (degrades to the arm7 beep monitor).
/// @param cardThumb     True if that function is thumb (currently unsupported;
///                      the overlay is skipped, never mis-hooked).
///
/// A miss (no card function, thumb, or an unrelocatable entry) is never fatal.
void GuideOverlay9Install(PatchContext& patchContext, u32* cardiReadCard, bool cardThumb);
