#pragma once
#include "patches/Patch.h"

/// @brief Arm9 patch to redirect card reads on SDK 2-4.
class CardiReadRomWithCpuPatch : public Patch
{
public:
    bool FindPatchTarget(PatchContext& patchContext) override;
    void ApplyPatch(PatchContext& patchContext) override;

    /// @brief The located CARDi_ReadRomWithCPU entry, or nullptr if not found.
    u32* GetCardiReadRomWithCpu() const { return _cardiReadRomWithCpu; }
    /// @brief Whether the located CARDi_ReadRomWithCPU is thumb code.
    bool IsThumb() const { return _thumb; }

private:
    u32* _cardiReadRomWithCpu = nullptr;
    u16 _thumb = false;
    const u32* _foundPattern = nullptr;

    void TryPattern(PatchContext& patchContext, const u32* pattern);
};
