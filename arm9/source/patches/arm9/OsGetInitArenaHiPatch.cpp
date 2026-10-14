#include "common.h"
#include "../PatchContext.h"
#include "OsGetInitArenaHiPatch.h"

// OS_GetInitArenaHi is a switch over the arena id; case OS_ARENA_MAIN loads the
// first word of the literal pool, which follows the function's last return. Each
// pattern is that last return plus the 0x023E0000 literal itself, so the match is
// the literal minus 3 words. OS_GetInitArenaLo also holds 0x023E0000 (as the
// MAINEX low), but never as its first pool word, so it cannot match.
static const u32 sOSGetInitArenaHiPattern[] = { 0xE28DD004u, 0xE8BD4000u, 0xE12FFF1Eu, 0x023E0000u }; // sdk 2.1-4
static const u32 sOSGetInitArenaHiPattern2[] = { 0xE8BD8008u, 0xE3A00000u, 0xE8BD8008u, 0x023E0000u }; // sdk 4-5
static const u32 sOSGetInitArenaHiPatternThumb[] = { 0xBD084808u, 0xBD084808u, 0xBD082000u, 0x023E0000u };

bool OsGetInitArenaHiPatch::FindPatchTarget(PatchContext& patchContext)
{
    if (_mainMemoryArenaHiLiteral)
        return true;
    u32* match = patchContext.FindPattern32(sOSGetInitArenaHiPattern, sizeof(sOSGetInitArenaHiPattern));
    if (!match)
        match = patchContext.FindPattern32(sOSGetInitArenaHiPattern2, sizeof(sOSGetInitArenaHiPattern2));
    if (!match)
        match = patchContext.FindPattern32(sOSGetInitArenaHiPatternThumb, sizeof(sOSGetInitArenaHiPatternThumb));
    if (match)
    {
        _mainMemoryArenaHiLiteral = match + 3;
        _mainMemoryArenaHi = (void*)*_mainMemoryArenaHiLiteral;
        LOG_DEBUG("Main memory arena hi literal at 0x%p: 0x%p\n", _mainMemoryArenaHiLiteral, _mainMemoryArenaHi);
    }
    else
    {
        LOG_DEBUG("OS_GetInitArenaHi not found\n");
    }
    return true;
}

void OsGetInitArenaHiPatch::ApplyPatch(PatchContext& patchContext)
{
    if (!_mainMemoryArenaHiLiteral)
        return;
    *_mainMemoryArenaHiLiteral = (u32)_mainMemoryArenaHi;
}
