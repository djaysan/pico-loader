#include "common.h"
#include <string.h>
#include "thumbInstructions.h"
#include "cache.h"
#include "GuideOverlay9PatchCode.h"
#include "GuideOverlay9.h"

// Same signatures as the arm7 cheat engine hook (CheatEnginePatch.cpp).
// The SDK OS library is built from the same source for both CPUs, so the
// arm9 OSi_IrqVBlank is expected to match the same patterns; the epilogue
// check in GuideOverlay9Install catches the case where it doesn't.
static const u32 sOSiIrqVBlankPattern0[] = { 0xE92D4008u, 0xE59F2038u, 0xE59F0038u, 0xE5921000u };
static const u32 sOSiIrqVBlankPattern1[] = { 0xE92D4000u, 0xE24DD004u, 0xE59F003Cu, 0xE5902060u };
static const u32 sOSiIrqVBlankPatternThumb0[] = { 0x4809B508u, 0x69024909u, 0x1C406808u, 0x2A006008u };

static u32* sHookSite = nullptr;
static u32 sPatchOffset = 0;
static bool sThumb = false;

void GuideOverlay9FindHookSite(PatchContext& patchContext)
{
    sHookSite = patchContext.FindPattern32(sOSiIrqVBlankPattern0, sizeof(sOSiIrqVBlankPattern0));
    if (sHookSite)
    {
        sPatchOffset = 0x3C;
    }
    else if ((sHookSite = patchContext.FindPattern32(sOSiIrqVBlankPattern1, sizeof(sOSiIrqVBlankPattern1))))
    {
        sPatchOffset = 0x40;
    }
    else if ((sHookSite = patchContext.FindPattern32(sOSiIrqVBlankPatternThumb0, sizeof(sOSiIrqVBlankPatternThumb0))))
    {
        sPatchOffset = 0x20;
        sThumb = true;
    }

    if (sHookSite)
    {
        LOG_DEBUG("ARM9 OSi_IrqVBlank found at 0x%p\n", sHookSite);
    }
    else
    {
        LOG_DEBUG("ARM9 OSi_IrqVBlank not found; guide overlay disabled\n");
    }
}

void GuideOverlay9Install(void* target)
{
    if (!sHookSite)
        return;

    // The hook offsets were measured on the arm7 build of OSi_IrqVBlank.
    // Only hook when the bytes there look like the function epilogue
    // (ldmfd sp! / add sp adjustment, or pop / add sp in thumb); anything
    // else means the arm9 build differs and overwriting it would crash the
    // game at the first vblank. Skipping leaves the game fully playable.
    u8* hookAt = (u8*)sHookSite + sPatchOffset;
    bool looksLikeEpilogue;
    if (sThumb)
    {
        u16 firstInstruction = *(u16*)hookAt;
        looksLikeEpilogue = (firstInstruction & 0xFE00) == 0xBC00 || // pop {...}
                            (firstInstruction & 0xFF80) == 0xB000;   // add sp, #imm
    }
    else
    {
        u32 firstInstruction = *(u32*)hookAt;
        looksLikeEpilogue = (firstInstruction & 0xFFFF0000) == 0xE8BD0000 || // ldmfd sp!, {...}
                            firstInstruction == 0xE28DD004;                  // add sp, sp, #4
    }
    if (!looksLikeEpilogue)
    {
        LOG_ERROR("ARM9 OSi_IrqVBlank epilogue mismatch at 0x%p, guide overlay disabled\n", hookAt);
        return;
    }

    memcpy(target, SECTION_START(patch_guideoverlay9), SECTION_SIZE(patch_guideoverlay9));
    u32 targetDelta = (u32)target - (u32)SECTION_START(patch_guideoverlay9);
    if (sThumb)
    {
        *(u16*)(hookAt + 0) = THUMB_LDR_PC_IMM(THUMB_R1, 0); // ldr r1,= address
        *(u16*)(hookAt + 2) = THUMB_BX(THUMB_R1); // bx r1
        *(u32*)(hookAt + 4) = (u32)guideoverlay9_entry + targetDelta; // address
    }
    else
    {
        *(u32*)(hookAt + 0) = 0xE51FF004; // ldr pc,= address
        *(u32*)(hookAt + 4) = (u32)guideoverlay9_entry_arm + targetDelta; // address
    }
    dc_flushAll();
    dc_drainWriteBuffer();
    ic_invalidateAll();
    LOG_DEBUG("Guide overlay placed at 0x%p\n", target);
}
