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
/// @param rebootEntry   Address of the patched OS_ResetSystem tail, or 0. With
///                      EXIT_TO_LAUNCHER the resident blob jumps here while
///                      L+R+Start+Select is held, which leaves the game without
///                      needing the per-frame hook at all.
///
/// A miss (no card function, thumb, or an unrelocatable entry) is never fatal.
void GuideOverlay9Install(PatchContext& patchContext, u32* cardiReadCard, bool cardThumb,
    u32 rebootEntry);

/// @brief Runtime address of the overlay's guide_data block, published by
///        GuideOverlay9Install so the (later) arm7 monitor pass can bake it in
///        and observe GD_FRAMECOUNT / GD_MARKER from shared main memory. 0 when
///        the overlay was not installed. Both patch passes run on the arm9
///        loader in sequence, so this static carries across them.
extern "C" u32 gGuideOverlayDataAddr;
