#pragma once
#include "patches/Patch.h"

/// @brief Arm7 patch for injecting the cheat engine and/or the guide monitor
///        in the vblank interrupt handler.
class CheatEnginePatch : public Patch
{
public:
    CheatEnginePatch(const void* cheats, void* guideMonitorTarget, const void* guideInfo, bool chainRetailHotkey)
        : _cheats(cheats), _guideMonitorTarget(guideMonitorTarget), _guideInfo(guideInfo),
          _chainRetailHotkey(chainRetailHotkey) { }

    bool FindPatchTarget(PatchContext& patchContext) override;
    void ApplyPatch(PatchContext& patchContext) override;

private:
    const void* _cheats;
    void* _guideMonitorTarget;
    const void* _guideInfo;
    bool _chainRetailHotkey;
    u32* _vblankIrqHandler = nullptr;
    const u32* _foundPattern = nullptr;
    u16 _thumb = false;
};
