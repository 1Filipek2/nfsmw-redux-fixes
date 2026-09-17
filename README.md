# nfsmw-redux-fixes

Byte patches for three mods in the Need for Speed Most Wanted (2005) Redux V3 modpack that waste CPU time. On my laptop the game went from 20-40 FPS in races to 60-80 FPS, without changing how it looks.

The patcher only touches files that match the exact known version (SHA-256), keeps a `.orig` backup next to each patched file and can restore them.

## What's wrong with Redux V3

- The GPU sits at ~15% usage, the CPU is the bottleneck
- `NFSMWGraphics.asi` polls hotkeys in a loop with `Sleep(0)`, which doesn't actually wait, one core stays at 100% the whole session
- `NextGenGraphics.MostWanted.asi` has a worker thread that keeps calling `io_context::run()` with no pause when there is no work, another core at 100%
- `NextGenGraphics.MostWanted.asi` also walks every material of every loaded model each frame to assign the water shader, around 8% of the main thread in races, the game already assigns shaders when a track section loads
- `MW360Tweaks.asi` tries to load `BlurMask.png`, `ColorTint.png`, `RocksTex.png` and `RocksNormal.png` every frame, these files aren't in Redux V3, so the load fails and runs again next frame, around a third of the main thread time in races went there
- On a 4 core CPU that leaves the game's main thread fighting for what's left

## What the patches do

- `NFSMWGraphics.asi`: `Sleep(0)` becomes `Sleep(10)`, hotkeys work the same
- `NextGenGraphics.MostWanted.asi`: the worker loop sleeps 1 ms before asking for work again, the material walk runs every 8th frame instead of every frame
- `MW360Tweaks.asi`: the load of the missing textures is skipped, they never loaded before anyway so nothing changes visually

Offsets, disassembly and measurements are in [TECHNICAL.md](TECHNICAL.md).

## Usage

Close the game first, then run `patch.bat` from the repo folder. If the game folder isn't found, it asks for the path (the folder that contains `scripts`).

```
patch.bat -GameDir "D:\Games\NFSMW"
```

```
game folder: D:\Games\NFSMW
patched  NFSMWGraphics.asi (hotkey thread Sleep(0) -> Sleep(10))
patched  NextGenGraphics.MostWanted.asi (worker thread sleeps 1 ms when idle, material fixup every 8th frame)
patched  MW360Tweaks.asi (no more per-frame loading of missing png textures)
```

Running it again prints `skip ... (already patched)`. A `NextGenGraphics.MostWanted.asi` patched by v1.0.0 gets `updated` to the current patch. A file with a different hash is left alone with `skip ... (unknown version, not touched)`.

To undo everything:

```
restore.bat -GameDir "D:\Games\NFSMW"
```

Files without a `.orig` backup, for example patched by hand, are restored by writing the original bytes back, the result has to match the original hash or nothing is written.

## Optional settings for smoother frame times

Not changed by the patcher. The two reflection settings trade some reflection quality for fewer stutters, everything else can stay on max.

- `SAVE\NFS Most Wanted\Settings.ini`, edit only while the game is closed because it gets rewritten on exit
  - `g_CarEnvironmentMapEnable= 1` (car reflection update rate, at 3 the scene around the car gets re-rendered very often)
  - `g_RoadReflectionEnable= 2` (road reflections without cars)
  - Average FPS stayed about the same, but frames over 33 ms went from 237 to 0 in a 2 min race
- `scripts\NFSMostWanted.WidescreenFix.ini`
  - `SimRate = -1` (monitor refresh rate) instead of `60`
  - At 60 the engine sleeps until the next simulation step, about 5 ms per frame, so FPS stays far below what the CPU can do
  - On a 144 Hz display: 84 FPS to 146 FPS, 99th percentile frame time 19 ms to 10.4 ms, gameplay speed unchanged
  - `WindowedMode = 0`, exclusive fullscreen presents through independent flip instead of a GDI copy
  - Same FPS, but a frame reached the display in 3.7 ms instead of 8.9 ms on average

## Requirements

- Redux V3 (v3.03)
- Windows 10 or 11

## Project layout

```
scripts/        nfsmw_fixes.ps1, the patcher (patch table, hash checks, backup/restore)
patch.bat       applies the patches
restore.bat     restores the .orig backups
TECHNICAL.md    offsets, disassembly before/after, measurements
```

## Testing & Verification

- Hardware: i5-11300H, RTX 3060 Laptop, 1080p 144 Hz
- Busy threads found by per-thread CPU time, the owning module from the thread start address (`NtQueryInformationThread`, `ThreadQuerySetWin32StartAddress`)
- Hot spots found by sampling `EIP` and scanning the stack of the busy threads, file names for the `NtCreateFile` calls read straight from `OBJECT_ATTRIBUTES` on the stack
- Frame times captured with PresentMon, 2 min per run, later runs 90 s on the same sprint race, two runs per setup
- Main thread profiled with Windows Performance Recorder (`wpr -start CPU`), samples and context switches grouped by module and return address
- Patcher tested on clean copies: patch, second run, restore, modified file, wrong path, game running
- Patched files are byte-identical to the ones used for the in-game tests
- Numbers for every run are in [TECHNICAL.md](TECHNICAL.md#measurements)
- DXVK was tested too and made it worse with this modpack
- The game process sometimes hangs on exit, if the patcher says the game is running, end it in Task Manager

The mods belong to their authors, this only patches performance bugs in them. Keep your own copy of `scripts` if you care about it.
