#pragma once
#include "sharedMemory.h"

struct rom_file_info_t
{
    u32 clusterShift;
    u32 database;
    u32 clusterMask;
    u32 clusterMap[124];
    u32 fileSize;
};

struct save_file_info_t
{
    u32 clusterShift;
    u32 database;
    u32 clusterMask;
    u32 clusterMap[29];
};

// Cluster map for an in-game guide text file. Unlike the rom and save
// file info this has no fixed shared memory slot (both are exactly full);
// it is placed in reserved main memory by the arm7 patcher instead.
struct guide_file_info_t
{
    u32 clusterShift;
    u32 database;
    u32 clusterMask;
    u32 fileSize;
    u32 clusterMap[29];
};

#define SHARED_ROM_FILE_INFO   ((rom_file_info_t*)TWL_SHARED_MEMORY->ntrSharedMem.gap0)
#define SHARED_SAVE_FILE_INFO  ((save_file_info_t*)TWL_SHARED_MEMORY->ntrSharedMem.gap200)
