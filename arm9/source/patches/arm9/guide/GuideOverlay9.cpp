#include "common.h"
#include <string.h>
#include "cache.h"
#include "GuideOverlay9PatchCode.h"
#include "GuideOverlay9.h"

// Bake a value into a field of the loader's own copy of guide_data, before
// the blob is copied to its resident location.
static inline void BakeDataField(u32 offset, u32 value)
{
    *(u32*)((u8*)&guide_data + offset) = value;
}

void GuideOverlay9Install(PatchContext& patchContext, u32* cardiReadCard, bool cardThumb)
{
    if (!cardiReadCard)
    {
        LOG_DEBUG("Guide overlay: no card function; overlay disabled\n");
        return;
    }
    if (cardThumb)
    {
        // The card-entry detour below assumes an arm entry. Thumb card
        // functions are left alone rather than mis-hooked.
        LOG_DEBUG("Guide overlay: thumb card function unsupported; overlay disabled\n");
        return;
    }

    u32 insn0 = cardiReadCard[0];
    // Only a relocatable stmfd-style prologue (top halfword 0xE92D) is safe to
    // displace and replay. Every arm CARDi_ReadCard variant the loader matches
    // begins with one; anything else we refuse (never crash the game).
    if ((insn0 & 0xFFFF0000u) != 0xE92D0000u)
    {
        LOG_DEBUG("Guide overlay: unexpected card entry 0x%08X; overlay disabled\n", insn0);
        return;
    }

    u32 sectionStart = (u32)SECTION_START(patch_guideoverlay9);
    u32 size = SECTION_SIZE(patch_guideoverlay9);

    // +4 so the blob can be word aligned; the heap gives no alignment guarantee.
    void* space = patchContext.GetPatchHeap().Alloc(size + 4);
    if (!space)
    {
        LOG_DEBUG("Guide overlay: no patch heap space; overlay disabled\n");
        return;
    }
    u32 base = ((u32)space + 3) & ~3u;
    u32 tramp = base + ((u32)&guide_tramp - sectionStart);
    u32 stub  = base + ((u32)&overlay_stub - sectionStart);

    // Bake the literals/state into the loader's copy, then copy the whole blob.
    guide_dataAddr_lit   = base + ((u32)&guide_data - sectionStart);
    guide_cardReturn_lit = (u32)cardiReadCard + 4;   // resume at card entry + 4
    guide_replay_slot    = insn0;                    // replay the displaced instruction
    BakeDataField(GD_OVERLAYSTUB, stub);
    BakeDataField(GD_CARDENTRY, (u32)cardiReadCard); // debug
    BakeDataField(GD_ORIGINSN0, insn0);              // debug

    memcpy((void*)base, (const void*)sectionStart, size);

    // Image-patch the card entry with `b guide_tramp` (arm, pc+8 relative).
    u32 branchOffset = (tramp - (u32)cardiReadCard - 8) >> 2;
    cardiReadCard[0] = 0xEA000000u | (branchOffset & 0x00FFFFFFu);

    dc_flushAll();
    dc_drainWriteBuffer();
    ic_invalidateAll();

    LOG_DEBUG("Guide overlay: bootstrap at card 0x%p, blob 0x%08X, stub 0x%08X\n",
        cardiReadCard, base, stub);
}
