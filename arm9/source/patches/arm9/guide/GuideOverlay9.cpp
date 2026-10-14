#include "common.h"
#include <string.h>
#include "cache.h"
#include "GuideOverlay9PatchCode.h"
#include "GuideOverlay9.h"

#ifndef GUIDE_OVERLAY_STAGE_A
#define GUIDE_OVERLAY_STAGE_A 0
#endif
#ifndef GUIDE_OVERLAY_STAGE_B
#define GUIDE_OVERLAY_STAGE_B GUIDE_OVERLAY_STAGE_A
#endif

// Published for the arm7 monitor pass (see GuideOverlay9.h).
u32 gGuideOverlayDataAddr = 0;
u32 gGuideReserveScanStart = 0;
u32 gGuideReserveEnd = 0;

#if GUIDE_OVERLAY_STAGE_B
// Bake a value into a field of the loader's own copy of guide_data, before
// the blob is copied to its resident location.
static inline void BakeDataField(u32 offset, u32 value)
{
    *(u32*)((u8*)&guide_data + offset) = value;
}
#endif

// The detour overwrites the card function's first two instructions, so the
// trampoline replays both from another address. Returns what to bake into
// guide_replay_slot1, or 0 when instruction 1 cannot run from there. Only the
// second instructions the loader's arm card signatures actually have are
// accepted; anything else is refused (never crash the game).
static u32 RelocateCardInstruction1(const u32* cardiReadCard)
{
    u32 insn1 = cardiReadCard[1];
    u32 rd = (insn1 >> 12) & 0xF;
    if ((insn1 & 0xFFFFF000u) == 0xE24DD000u) // sub sp, sp, #imm (sdk2, twl)
        return insn1;
    if ((insn1 & 0xFFFF0FF0u) == 0xE1A00000u && rd != 15 && (insn1 & 0xF) != 15) // mov rd, rm (sdk2 007530)
        return insn1;
    if ((insn1 & 0xFFFF0000u) == 0xE59F0000u && rd != 15) // ldr rd, [pc, #+imm] (sdk4)
    {
        // Load the same word from the blob's own literal instead. The offset is
        // taken from the loader's copy; the blob keeps its layout when copied.
        guide_replay_lit = *(const u32*)((const u8*)cardiReadCard + 4 + 8 + (insn1 & 0xFFF));
        return (insn1 & 0xFFFFF000u) | ((u32)&guide_replay_lit - ((u32)&guide_replay_slot1 + 8));
    }
    return 0;
}

void GuideOverlay9Install(PatchContext& patchContext, u32 reserveBase, u32 reserveEnd,
    u32* cardiReadCard, bool cardThumb, u32 rebootEntry)
{
    if (!reserveBase)
    {
        LOG_DEBUG("Guide overlay: no arm9 arena reservation; overlay disabled\n");
        return;
    }

    // Only a stmfd prologue (top halfword 0xE92D) is safe to displace; every
    // arm card variant the loader matches begins with one. Thumb entries need
    // a thumb detour, which does not exist yet.
    u32 replay1 = 0;
    if (cardiReadCard && !cardThumb && (cardiReadCard[0] & 0xFFFF0000u) == 0xE92D0000u)
        replay1 = RelocateCardInstruction1(cardiReadCard);

    u32 sectionStart = (u32)SECTION_START(patch_guideoverlay9);
    u32 size = SECTION_SIZE(patch_guideoverlay9);
    u32 base = reserveBase;

    // Bake the literals/state into the loader's copy, then copy the whole blob.
    if (replay1)
    {
        guide_replay_slot = cardiReadCard[0];
        guide_replay_slot1 = replay1;
        // Resume where the card function really runs: an autoload block is
        // copied to its target before main(), so the image address is wrong there.
        guide_cardReturn_lit = patchContext.GetAutoloadAdjuster()->AdjustInitialToFinal((u32)cardiReadCard) + 8;
    }
    guide_rebootEntry_lit = rebootEntry;             // thumb bit already set, or 0
#if GUIDE_OVERLAY_STAGE_B
    guide_dataAddr_lit   = base + ((u32)&guide_data - sectionStart);
    gGuideOverlayDataAddr = guide_dataAddr_lit; // published for the arm7 monitor
    BakeDataField(GD_OVERLAYSTUB, base + ((u32)&overlay_stub - sectionStart));
    BakeDataField(GD_CARDENTRY, (u32)cardiReadCard); // debug
    BakeDataField(GD_ORIGINSN0, cardiReadCard ? cardiReadCard[0] : 0); // debug
#endif

    // Canary over the whole reservation, then the blob over its start. The rest
    // stays canary for the arm7 residency check to sample.
    for (u32* p = (u32*)reserveBase; p < (u32*)reserveEnd; p++)
        *p = GUIDE_RESERVE_CANARY;
    memcpy((void*)base, (const void*)sectionStart, size);
    gGuideReserveScanStart = (base + size + 3) & ~3u;
    gGuideReserveEnd = reserveEnd;

    if (replay1)
    {
        // Absolute jump, like every other patch in this loader: a relative `b`
        // is wrong by the autoload shift (-0x87E0 on New Super Mario Bros.).
        cardiReadCard[0] = 0xE51FF004u; // ldr pc, [pc, #-4]
        cardiReadCard[1] = base + ((u32)&guide_tramp - sectionStart);
    }

    dc_flushAll();
    dc_drainWriteBuffer();
    ic_invalidateAll();

    LOG_DEBUG("Guide overlay: blob 0x%08X-0x%08X, card 0x%p %s, reboot 0x%08X\n",
        base, reserveEnd, cardiReadCard, replay1 ? "detoured" : "not detoured", rebootEntry);
}
