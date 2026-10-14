#pragma once
#include "../Patch.h"

/// @brief Arm9 patch to get and update the main memory arena high address.
///
/// Lowering it reserves the top of the arm9 main arena: the game's heap never
/// reaches past OS_GetInitArenaHi(OS_ARENA_MAIN), so loader code placed above
/// the new value stays resident during gameplay. Arm9 counterpart of
/// OsGetInitArenaLoPatch.
///
/// Only sdk 2.1+ games are found. Sdk 2.0 returns the arena high with an
/// immediate mov (0x023C0000) instead of a literal, and is left alone.
class OsGetInitArenaHiPatch : public Patch
{
public:
    /// @brief A miss is not fatal; it only means there is no reservation.
    bool FindPatchTarget(PatchContext& patchContext) override;
    void ApplyPatch(PatchContext& patchContext) override;

    bool IsFound() const { return _mainMemoryArenaHiLiteral != nullptr; }
    void* GetMainMemoryArenaHi() const { return _mainMemoryArenaHi; }
    void SetMainMemoryArenaHi(void* mainMemoryArenaHi) { _mainMemoryArenaHi = mainMemoryArenaHi; }

private:
    u32* _mainMemoryArenaHiLiteral = nullptr;
    void* _mainMemoryArenaHi = nullptr;
};
