#pragma once
#include "../Patch.h"
#include "LoaderInfo.h"

/// @brief Arm9 patch to make OS_ResetSystem reboot into Pico Loader.
class OSResetSystemPatch : public Patch
{
public:
    OSResetSystemPatch(const loader_info_t* loaderInfo, bool runInDSiMode)
        : _runInDSiMode(runInDSiMode), _loaderInfo(loaderInfo) { }

    bool FindPatchTarget(PatchContext& patchContext) override;
    void ApplyPatch(PatchContext& patchContext) override;

    void** GetCheatsPointerAtTarget() const
    {
        return _cheatsPointer;
    }

    /// @brief Runtime address of the patched OS_ResetSystem tail in the game's
    ///        memory, thumb bit set, or 0 when the patch did not apply.
    ///        Branching here reboots into Pico Loader; it never returns.
    u32 GetRebootEntry() const
    {
        return _rebootEntry;
    }

private:
    u32* _osResetSystem = nullptr;
    u32 _rebootEntry = 0;
    u16 _hybrid = false;
    u16 _runInDSiMode;
    const loader_info_t* _loaderInfo;
    void** _cheatsPointer = nullptr;
};
