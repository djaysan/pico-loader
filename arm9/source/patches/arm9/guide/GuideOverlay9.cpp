#include "common.h"
#include <string.h>
#include "thumbInstructions.h"
#include "cache.h"
#include "GuideOverlay9PatchCode.h"
#include "GuideOverlay9.h"

// Full-prologue signatures of the SDK's per-frame vblank wait function on
// the arm9 (derived from rom disassembly across SDK generations; each is
// the first 16 bytes of the function). Unlike the arm7 OSi_IrqVBlank this
// function differs per SDK generation, but is bit-identical between games
// of the same generation. All variants take no arguments.
//
// sdk2: push {r4,r5,lr}; sub sp,#4; ldr r1,[pc,#0x98]; ldrh r0,[r1]
static const u32 sVBlankWaitSdk2[] = { 0xE92D4030, 0xE24DD004, 0xE59F1098, 0xE1D100B0 };
// sdk5: push {r4,r5,r6,lr}; ldr r0,[pc,#0x7C]; ldrh r1,[r0]; cmp r1,#0
static const u32 sVBlankWaitSdk5[] = { 0xE92D4070, 0xE59F007C, 0xE1D010B0, 0xE3510000 };
// sdk4 thumb: push {r3,r4,r5,lr}; ldr r0,[pc,#0x4C]; ldrh r1,[r0]; cmp r1,#0
static const u32 sVBlankWaitSdk4Thumb[] = { 0x4813B538, 0x29008801, 0x2101D121, 0x21008001 };

enum class Variant { None, Sdk2, Sdk5, Sdk4Thumb };

static u32* sHookSite = nullptr;
static Variant sVariant = Variant::None;
static void* sStubTarget = nullptr;

void GuideOverlay9FindHookSite(PatchContext& patchContext)
{
    if ((sHookSite = patchContext.FindPattern32(sVBlankWaitSdk2, sizeof(sVBlankWaitSdk2))))
    {
        sVariant = Variant::Sdk2;
    }
    else if ((sHookSite = patchContext.FindPattern32(sVBlankWaitSdk5, sizeof(sVBlankWaitSdk5))))
    {
        sVariant = Variant::Sdk5;
    }
    else if ((sHookSite = patchContext.FindPattern32(sVBlankWaitSdk4Thumb, sizeof(sVBlankWaitSdk4Thumb))))
    {
        sVariant = Variant::Sdk4Thumb;
    }

    if (sHookSite)
    {
        LOG_DEBUG("ARM9 vblank wait found at 0x%p\n", sHookSite);
    }
    else
    {
        LOG_DEBUG("ARM9 vblank wait not found; guide overlay disabled\n");
    }
}

void GuideOverlay9ReserveStub(PatchContext& patchContext)
{
    if (!sHookSite)
        return;
    // +4 so the stub can be aligned; the heap gives no alignment guarantee.
    void* space = patchContext.GetPatchHeap().Alloc(SECTION_SIZE(patch_guideoverlay9) + 4);
    if (space)
    {
        sStubTarget = (void*)(((u32)space + 3) & ~3u);
        LOG_DEBUG("Guide overlay stub space at 0x%p\n", sStubTarget);
    }
    else
    {
        LOG_DEBUG("No patch heap space for the guide overlay stub\n");
    }
}

void GuideOverlay9Install()
{
    if (!sHookSite || sVariant == Variant::None || !sStubTarget)
        return;

    // Bake the variant's literal slots into the loader's copy of the stub,
    // then place it. The displaced prologue instructions with pc-relative
    // loads are replayed from these slots (see GuideOverlay9PatchCode.s).
    void* target = sStubTarget;
    u32 site = (u32)sHookSite;
    u32 runDelta = (u32)target - (u32)SECTION_START(patch_guideoverlay9);
    const void* entry;
    switch (sVariant)
    {
        case Variant::Sdk2:
            guideoverlay9_sdk2Return = site + 8;
            entry = (const void*)((u32)guideoverlay9_entry_sdk2 + runDelta);
            break;
        case Variant::Sdk5:
            guideoverlay9_sdk5Return = site + 8;
            guideoverlay9_sdk5PoolValue = *(u32*)(site + 0x88); // pool word read by the displaced ldr r0
            entry = (const void*)((u32)guideoverlay9_entry_sdk5 + runDelta);
            break;
        case Variant::Sdk4Thumb:
            guideoverlay9_sdk4tReturn = (site + 8) | 1;
            guideoverlay9_sdk4tPoolValue = *(u32*)(site + 0x50); // pool word read by the displaced ldr r0
            entry = (const void*)((u32)guideoverlay9_entry_sdk4t + runDelta);
            break;
        default:
            return;
    }

    memcpy(target, SECTION_START(patch_guideoverlay9), SECTION_SIZE(patch_guideoverlay9));

    if (sVariant == Variant::Sdk4Thumb)
    {
        // r1 is clobbered, which is safe at the entry of a void function.
        // The stub entry is arm code, so the address keeps bit 0 clear.
        *(u16*)(site + 0) = THUMB_LDR_PC_IMM(THUMB_R1, 0); // ldr r1,= address
        *(u16*)(site + 2) = THUMB_BX(THUMB_R1); // bx r1
        *(u32*)(site + 4) = (u32)entry; // address
    }
    else
    {
        *(u32*)(site + 0) = 0xE51FF004; // ldr pc,= address
        *(u32*)(site + 4) = (u32)entry; // address
    }
    dc_flushAll();
    dc_drainWriteBuffer();
    ic_invalidateAll();
    LOG_DEBUG("Guide overlay placed at 0x%p\n", target);
}
