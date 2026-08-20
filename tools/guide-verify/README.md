# guide-verify — melonDS + GDB verification for the phase-3 ARM9 overlay

Reproduces the GDB proof in PHASE3-PROGRESS.md (Castlevania: Dawn of Sorrow).

## Setup
- melonDS.toml: `[Instance0.Gdb] Enabled=true`, `[Instance0.Gdb.ARM9] BreakOnStartup=true`.
- SD folder-sync must boot the game headless (autoboot marker + settings.json
  lastUsedFilePath), with the loader at `_pico/picoLoader9.bin`.
- Launch: `melonDS LAUNCHER.nds` (headless), wait ~6s.

## Scripts (GDB stub on port 3333)
- `gdbc.py`            — GDB-RSP client for melonDS (handles its ack quirk).
- `capture_itcm.py`    — boots, dumps ITCM, locates the dispatcher prologue
                         (`E24EE004` then `E92D500F`).
- `inject_overlay.s`   — standalone overlay stub; assemble at 0x01006400 with
                         the BlocksDS gcc-arm-none-eabi toolchain:
                           as -mcpu=arm946e-s -o o.o inject_overlay.s
                           ld -Ttext=0x01006400 -e _start -o o.elf o.o
                           objcopy -O binary o.elf _inject.bin
- `inject_and_verify.py` — injects _inject.bin into free ITCM, detours the
                         dispatcher at 0x010001D8, verifies per-frame firing,
                         freeze (MASTER_BRIGHT 0x8010), and release.
- `check_dispatcher.py`  — checks whether Stage A auto-installed the hook
                         (dispatcher == E51FF004) and whether the blob survived.

Dispatcher address (0x010001D8) and dispatcher+8 return (0x010001E0) are
Castlevania-specific; find them per game with capture_itcm.py.
