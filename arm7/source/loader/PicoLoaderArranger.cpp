#include "common.h"
#include <memory>
#include <string.h>
#include "PicoLoaderArranger.h"

#define PICO_LOADER_9_PATH    "/_pico/picoLoader9.bin"
#define PICO_LOADER_7_PATH    "/_pico/picoLoader7.bin"
#define PICO_LAUNCHER_FALLBACK_PATH "/_picoboot.nds"

bool PicoLoaderArranger::SetupPicoLoaderInfo(loader_info_t* info, u32& loader7Size, u32& loader7Sum) const
{
    auto file = std::make_unique<FIL>();
    if (f_open(file.get(), PICO_LOADER_9_PATH, FA_OPEN_EXISTING | FA_READ) != FR_OK)
    {
        LOG_FATAL("Failed to open picoLoader9.bin\n");
        return false;
    }

    DWORD* clusterTab = (DWORD*)info->clusterMap9;
    clusterTab[0] = sizeof(info->clusterMap9) / sizeof(u32);
    file->cltbl = clusterTab;
    FRESULT seekResult = f_lseek(file.get(), CREATE_LINKMAP);
    if (seekResult != FR_OK)
    {
        LOG_FATAL("Failed to make picoLoader9 cluster table. Result: %d\n", seekResult);
        return false;
    }

    info->clusterShift = __builtin_ctz(file->obj.fs->csize);
    info->picoLoaderBootDrive = gLoaderHeader.bootDrive;
    info->database = file->obj.fs->database;
    memcpy(info->launcherPath, gLoaderHeader.v2.launcherPath, sizeof(info->launcherPath));
    info->launcherPath[sizeof(info->launcherPath) - 1] = 0;
    if (info->launcherPath[0] == 0)
    {
        strcpy(info->launcherPath, PICO_LAUNCHER_FALLBACK_PATH);
    }

    if (f_close(file.get()) != FR_OK)
    {
        LOG_FATAL("Failed to close picoLoader9 file\n");
        return false;
    }

    if (f_open(file.get(), PICO_LOADER_7_PATH, FA_OPEN_EXISTING | FA_READ) != FR_OK)
    {
        LOG_FATAL("Failed to open picoLoader7.bin\n");
        return false;
    }

    clusterTab = (DWORD*)info->clusterMap7;
    clusterTab[0] = sizeof(info->clusterMap7) / sizeof(u32);
    file->cltbl = clusterTab;
    FRESULT seekResult7 = f_lseek(file.get(), CREATE_LINKMAP);
    if (seekResult7 != FR_OK)
    {
        LOG_FATAL("Failed to make picoLoader7 cluster table. Result: %d\n", seekResult7);
        return false;
    }

    // The retail return hotkey verifies the file it reloads against these
    // (any build, not one fixed binary). 0 = unreadable, hotkey stays off.
    loader7Size = f_size(file.get());
    loader7Sum = 0;
    auto words = std::make_unique_for_overwrite<u32[]>(128);
    UINT bytesRead = 0;
    if (f_lseek(file.get(), 0) != FR_OK)
        loader7Size = 0;
    for (u32 left = loader7Size; left != 0; left -= bytesRead)
    {
        if (f_read(file.get(), words.get(), 512, &bytesRead) != FR_OK || bytesRead == 0)
        {
            loader7Size = 0;
            break;
        }
        for (u32 i = 0; i < bytesRead / 4; i++)
            loader7Sum += words[i];
    }

    if (f_close(file.get()) != FR_OK)
    {
        LOG_FATAL("Failed to close picoLoader7 file\n");
        return false;
    }

    return true;
}
