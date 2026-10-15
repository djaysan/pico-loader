#pragma once
#include "patches/PatchContext.h"

/// @brief Size of the arm9 main-memory reservation for the guide overlay, taken
///        off the top of the game's main arena (OsGetInitArenaHiPatch).
#define GUIDE_RESERVE_SIZE      0x4000

/// @brief Fill word for the unused part of the reservation. The arm7 monitor
///        (GUIDE_ARENA_PROOF) samples it to tell whether the game wrote there.
///        Also hardcoded in GuideMonitorPatchCode.s - keep in sync.
#define GUIDE_RESERVE_CANARY    0xA55A3CC3u

/// @brief Installs the guide overlay's resident arm9 blob.
///
/// Places the blob at the start of the reservation and image-patches the entry
/// of the card read function (already located by the loader) with an absolute
/// jump into it, so the blob runs on every card read during gameplay. With
/// GUIDE_IPC_FREEZE that is where it installs its IPC_SYNC irq handler in the
/// game's irq table (found here at patch time). See PHASE4-PLAN.md and
/// GuideOverlay9PatchCode.s.
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

/// @brief The canary part of the reservation, [start, end), published by
///        GuideOverlay9Install for the arm7 residency check, which the later
///        arm7 patch pass bakes in (both passes run on the arm9 loader in
///        sequence). Both 0 when nothing was placed.
extern "C" u32 gGuideReserveScanStart;
extern "C" u32 gGuideReserveEnd;
