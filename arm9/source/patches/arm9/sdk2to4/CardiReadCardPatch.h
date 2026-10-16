#pragma once
#include "patches/Patch.h"

/// @brief Arm9 patch to redirect card reads on SDK 2-4.
class CardiReadCardPatch : public Patch
{
public:
    bool FindPatchTarget(PatchContext& patchContext) override;
    void ApplyPatch(PatchContext& patchContext) override;

    /// @brief The located CARDi_ReadCard entry, or nullptr if not found.
    u32* GetCardiReadCard() const { return _cardiReadCard; }
    /// @brief Whether the located CARDi_ReadCard is thumb code.
    bool IsThumb() const { return _thumb; }
    /// @brief Thumb only: the literal in the game's CARDi_ReadCard holding the
    ///        address its `ldr r0,=entry ; blx r0` calls, or nullptr.
    u32* GetLoaderEntryLiteral() const { return _loaderEntryLiteral; }

private:
    u32* _cardiReadCard = nullptr;
    u16 _thumb = false;
    const u32* _foundPattern = nullptr;
    u32* _loaderEntryLiteral = nullptr;

    void TryPattern(PatchContext& patchContext, const u32* pattern, u32 byteLength);
};