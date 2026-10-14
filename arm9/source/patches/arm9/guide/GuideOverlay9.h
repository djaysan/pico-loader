#pragma once
#include "patches/PatchContext.h"

/// @brief Size of the arm9 main-memory reservation for the guide overlay, taken
///        off the top of the game's main arena (OsGetInitArenaHiPatch).
#define GUIDE_RESERVE_SIZE      0x4000

/// @brief Fill word for the unused part of the reservation. The arm7 monitor
///        (GUIDE_ARENA_PROOF) samples it to tell whether the game wrote there.
///        Also hardcoded in GuideMonitorPatchCode.s - keep in sync.
#define GUIDE_RESERVE_CANARY    0xA55A3CC3u

/// @brief Installs the phase-3 two-stage guide overlay bootstrap.
///
/// The arm9 per-frame IRQ dispatcher is built at runtime in ITCM and is not
/// present in the rom image, so it cannot be hooked at patch time. Instead
/// this places a resident blob at the start of the reservation and image-patches
/// the entry of the card read function (already located by the loader) with an
/// absolute jump into it. At runtime the blob's installer scans ITCM for the
/// dispatcher and detours it into the per-frame overlay stub (freeze + blank +
/// resume). See PHASE3-FINDINGS.md, PHASE4-PLAN.md and GuideOverlay9PatchCode.s.
///
/// @param patchContext  The arm9 patch context (for the autoload adjuster).
/// @param reserveBase   Start of the reserved main memory, or 0 to skip (no
///                      reservation on this game: degrades to the arm7 beep monitor).
/// @param reserveEnd    End of the reserved main memory (the original arena high).
/// @param cardiReadCard The card read function entry the loader found, or nullptr.
/// @param cardThumb     True if that function is thumb (not detoured).
/// @param rebootEntry   Address of the patched OS_ResetSystem tail, or 0. With
///                      EXIT_TO_LAUNCHER the resident blob jumps here while
///                      L+R+Start+Select is held.
///
/// A card entry that cannot be detoured still gets the blob placed, so the
/// residency check covers it. Nothing here is ever fatal.
void GuideOverlay9Install(PatchContext& patchContext, u32 reserveBase, u32 reserveEnd,
    u32* cardiReadCard, bool cardThumb, u32 rebootEntry);

/// @brief Runtime address of the overlay's guide_data block, published by
///        GuideOverlay9Install so the (later) arm7 monitor pass can bake it in
///        and observe GD_FRAMECOUNT / GD_MARKER from shared main memory. 0 when
///        the overlay was not installed. Both patch passes run on the arm9
///        loader in sequence, so this static carries across them.
extern "C" u32 gGuideOverlayDataAddr;

/// @brief The canary part of the reservation, [start, end), published the same
///        way for the arm7 residency check. Both 0 when nothing was placed.
extern "C" u32 gGuideReserveScanStart;
extern "C" u32 gGuideReserveEnd;
