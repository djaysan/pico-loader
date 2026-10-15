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
#if GUIDE_READER
    // The reading position in <guide>.pos, shared with the guide-reader app:
    // "<offset> <line>\n", kept at GUIDE_POS_SIZE bytes so the arm9 reader can
    // rewrite its first sector in place. Offsets 132/136/140 are used by
    // GuideOverlay9PatchCode.s - keep in sync.
    u32 posSector;  // first sd sector of the file, 0 = no position file
    u32 posOffset;  // byte offset of the saved top line
    u32 posLine;    // its display line number (the app shows it)
#endif
};

#define GUIDE_POS_SIZE  32

#define SHARED_ROM_FILE_INFO   ((rom_file_info_t*)TWL_SHARED_MEMORY->ntrSharedMem.gap0)
#define SHARED_SAVE_FILE_INFO  ((save_file_info_t*)TWL_SHARED_MEMORY->ntrSharedMem.gap200)
