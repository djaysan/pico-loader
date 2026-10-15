#include "common.h"
#include <string.h>
#include "thumbInstructions.h"
#include "CheatEnginePatchCode.h"
#include "patches/arm7/guide/GuideMonitorPatchCode.h"
#include "patches/arm9/guide/GuideOverlay9.h"
#include "CheatEnginePatch.h"

static const u32 sOSiIrqVBlankPattern0[] = { 0xE92D4008u, 0xE59F2038u, 0xE59F0038u, 0xE5921000u };
static const u32 sOSiIrqVBlankPattern1[] = { 0xE92D4000u, 0xE24DD004u, 0xE59F003Cu, 0xE5902060u };
static const u32 sOSiIrqVBlankPatternThumb0[] = { 0x4809B508u, 0x69024909u, 0x1C406808u, 0x2A006008u };

bool CheatEnginePatch::FindPatchTarget(PatchContext& patchContext)
{
    _vblankIrqHandler = patchContext.FindPattern32(sOSiIrqVBlankPattern0, sizeof(sOSiIrqVBlankPattern0));
    if (_vblankIrqHandler)
    {
        _foundPattern = sOSiIrqVBlankPattern0;
    }
    if (!_vblankIrqHandler)
    {
        _vblankIrqHandler = patchContext.FindPattern32(sOSiIrqVBlankPattern1, sizeof(sOSiIrqVBlankPattern1));
        if (_vblankIrqHandler)
        {
            _foundPattern = sOSiIrqVBlankPattern1;
        }
    }
    if (!_vblankIrqHandler)
    {
        _vblankIrqHandler = patchContext.FindPattern32(sOSiIrqVBlankPatternThumb0, sizeof(sOSiIrqVBlankPatternThumb0));
        if (_vblankIrqHandler)
        {
            _foundPattern = sOSiIrqVBlankPatternThumb0;
            _thumb = true;
        }
    }

    if (_vblankIrqHandler)
    {
        LOG_DEBUG("ARM7 OSi_IrqVBlank found at 0x%p\n", _vblankIrqHandler);
    }

    // A miss is only fatal when cheats are active; the guide monitor
    // degrades gracefully on games with an unknown OSi_IrqVBlank signature.
    return _vblankIrqHandler != nullptr || _cheats == nullptr;
}

void CheatEnginePatch::ApplyPatch(PatchContext& patchContext)
{
    if (!_vblankIrqHandler || (!_cheats && !_guideMonitorTarget))
        return;

    const void* hookTarget = nullptr;
    const void* hookTargetArm = nullptr;

    if (_cheats)
    {
        auto cheatEnginePatchCode = patchContext.GetPatchCodeCollection().AddUniquePatchCode<CheatEnginePatchCode>
        (
            patchContext.GetPatchHeap(),
            _cheats
        );
        hookTarget = cheatEnginePatchCode->GetCheatEngineFunction();
        hookTargetArm = cheatEnginePatchCode->GetCheatEngineFunctionArm();
    }

    if (_guideMonitorTarget)
    {
        // The guide monitor is copied to reserved main memory (not the wram
        // patch heap) and chains to the cheat engine when cheats are active.
        guidemonitor_guideInfoPtr = _guideInfo;
        guidemonitor_chainPtr = hookTarget;
#if GUIDE_ARENA_PROOF
        // Hand the arm7 monitor the canary part of the arm9 reservation for the
        // residency check.
        guidemonitor_reserveScanStart = gGuideReserveScanStart;
        guidemonitor_reserveEnd = gGuideReserveEnd;
#endif
        memcpy(_guideMonitorTarget, SECTION_START(patch_guidemonitor), SECTION_SIZE(patch_guidemonitor));
        u32 targetDelta = (u32)_guideMonitorTarget - (u32)SECTION_START(patch_guidemonitor);
        hookTarget = (const void*)((u32)guidemonitor_entry + targetDelta);
        hookTargetArm = (const void*)((u32)guidemonitor_entry_arm + targetDelta);
        LOG_DEBUG("Guide monitor placed at 0x%p\n", _guideMonitorTarget);
    }

    int patchOffset;
    if (_foundPattern == sOSiIrqVBlankPattern0)
    {
        patchOffset = 0x3C;
    }
    else if (_foundPattern == sOSiIrqVBlankPattern1)
    {
        patchOffset = 0x40;
    }
    else if (_foundPattern == sOSiIrqVBlankPatternThumb0)
    {
        patchOffset = 0x20;
    }
    else
    {
        LOG_ERROR("ARM7 OSi_IrqVBlank signature not implemented\n");
        return;
    }

    if (_thumb)
    {
        *(u16*)((u8*)_vblankIrqHandler + patchOffset + 0) = THUMB_LDR_PC_IMM(THUMB_R1, 0); // ldr r1,= address
        *(u16*)((u8*)_vblankIrqHandler + patchOffset + 2) = THUMB_BX(THUMB_R1); // bx r1
        *(u32*)((u8*)_vblankIrqHandler + patchOffset + 4) = (u32)hookTarget; // address
    }
    else
    {
        *(u32*)((u8*)_vblankIrqHandler + patchOffset + 0) = 0xE51FF004; // ldr pc,= address
        *(u32*)((u8*)_vblankIrqHandler + patchOffset + 4) = (u32)hookTargetArm; // address
    }
    LOG_DEBUG("VBlank hook enabled\n");
}
