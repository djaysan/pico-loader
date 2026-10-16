#pragma once
#include "LoaderInfo.h"

/// @brief Class for setting up \see loader_info_t.
class PicoLoaderArranger
{
public:
    /// @brief Sets up the given \p info for being able to reload Pico Loader at a later time.
    /// @param info The \see loader_info_t struct to fill.
    /// @param loader7Size Set to the size of picoLoader7.bin, or 0 if it could not be read.
    /// @param loader7Sum Set to the sum of its little-endian words, mod 2^32.
    /// @return \c true when setting up was successful, or \c false otherwise.
    bool SetupPicoLoaderInfo(loader_info_t* info, u32& loader7Size, u32& loader7Sum) const;
};
