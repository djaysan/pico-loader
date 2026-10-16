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
/// @param loaderEntryLiteral Thumb card functions: the literal of the loader's
///                      own `blx` into its card patch, or nullptr. Repointed at
///                      guide_tramp_call when there is no detour.
/// @param rebootEntry   Address of the patched OS_ResetSystem tail, or 0. With
///                      EXIT_TO_LAUNCHER the resident blob jumps here while
///                      L+R+Start+Select is held.
///
/// A card entry that cannot be detoured still gets the blob placed, so the
/// residency check covers it. Nothing here is ever fatal.
void GuideOverlay9Install(PatchContext& patchContext, u32 reserveBase, u32 reserveEnd,
    u32* cardiReadCard, bool cardThumb, u32* loaderEntryLiteral, u32 rebootEntry);

/// @brief The canary part of the reservation, [start, end), published by
///        GuideOverlay9Install for the arm7 residency check, which the later
///        arm7 patch pass bakes in (both passes run on the arm9 loader in
///        sequence). Both 0 when nothing was placed.
extern "C" u32 gGuideReserveScanStart;
extern "C" u32 gGuideReserveEnd;

/// @brief GUIDE_READER: bytes of the reader's work area, placed right after
///        the blob in the reservation (W_SIZE in GuideOverlay9PatchCode.s -
///        keep in sync). Stack, sector window, the backup of the sub bg
///        tiles and map the reader draws over, the guide cluster map and a copy
///        of the platform's sd write code.
#define GUIDE_READER_WORK_SIZE  0x2000

/// @brief GUIDE_READER: offset of the guide cluster map in the work area
///        (W_CLMT in GuideOverlay9PatchCode.s - keep in sync).
#define GUIDE_READER_CLMT_OFFSET 0x1E00

/// @brief GUIDE_READER: where in the work area the platform's sd write code is
///        copied (for saving the reading position), and the room it has.
#define GUIDE_READER_WRCODE_OFFSET 0x1F00
#define GUIDE_READER_WRCODE_SIZE   0x100

/// @brief GUIDE_READER: where the arm7 patch pass (which runs after the arm9
///        pass) must place the guide cluster map, or 0 when the reader is off.
///        The reader runs on the arm9, and the game's arm9 MPU has no access to
///        the arm7's part of main memory (region 2, 0x023E0000-0x02400000)
///        where the map would otherwise go; the arm7 can write anywhere.
extern "C" u32 gGuideReaderClmt;
