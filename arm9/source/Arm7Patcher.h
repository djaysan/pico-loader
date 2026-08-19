#pragma once

class LoaderPlatform;

/// @brief Class for patching the arm7 of retail roms.
class Arm7Patcher
{
public:
    /// @brief Applies arm7 patches using the given \p loaderPlatform.
    /// @param loaderPlatform The loader platform to use.
    /// @param cheatsLength The length of the cheats data, or zero when there are no cheats.
    /// @param cheatsPtr Pointer to where the cheats need to be stored, or \c nullptr when there are no cheats.
    /// @param guideInfoLength The length of the guide file info, or zero when there is no guide.
    /// @param guideInfoPtr Pointer to where the guide file info needs to be stored, or \c nullptr when there is no guide.
    /// @param guideOverlay9Ptr Reserved main memory for the arm9 overlay stub, or \c nullptr when there is no guide.
    /// @param runInDSiMode \c true if the rom should be loaded in DSi mode, or \c false otherwise.
    /// @return A pointer to the patch space in IWRAM, or \c nullptr if the patches have been placed in main memory.
    void* ApplyPatches(const LoaderPlatform* loaderPlatform, u32 cheatsLength, void*& cheatsPtr,
        u32 guideInfoLength, void*& guideInfoPtr, void*& guideOverlay9Ptr, bool runInDSiMode) const;
};
