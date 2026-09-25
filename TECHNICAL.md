# Technical details

All addresses assume the default image base `0x10000000`. File offsets are raw offsets in the file.

## How the problems were found

- PresentMon: frame times, CPU busy time and GPU time per frame
- Per thread CPU usage of the game process
- Thread start addresses to find which module created each busy thread
- Sampling the instruction pointer and stack of busy threads to find the exact loops
- Windows Performance Recorder CPU traces for the main thread: where it runs and why it waits

## NFSMWGraphics.asi

- SHA-256 original: `9a62a02e2a5bd405549e6e12d737f8cea8982c94c3aa115a0bc862898a233619`
- SHA-256 patched: `9d0f21454d77f0f41998819f2e76e5f3bb8d815be58fd95c8c92319969e07928`
- The thread created with `CreateThread` at RVA `0x23A0` polls hotkeys with `GetAsyncKeyState`
- The loop calls `Sleep(0)`, which only yields and returns right away, so the thread uses a full core
- Patch:

| VA | File offset | Before | After |
|---|---|---|---|
| `0x100023C7` | `0x17C7` | `push 0` (`6A 00`) | `push 10` (`6A 0A`) |
| `0x10002415` | `0x1815` | `push 0` (`6A 00`) | `push 10` (`6A 0A`) |

## NextGenGraphics.MostWanted.asi

- SHA-256 original: `f9752191ba30e75e8ec489743f5a20a517b006e3f81e45efc5f0e29441d26cd0`
- SHA-256 patched: `403faf38ab2dbd3be3a66a622f399d147a9876daf292da140e7d914529f20e69`
- SHA-256 patched by v1.0.0 (worker thread only): `73eef80cb79cc3f8b58ad4babf65aec72ada80f7b3fd16fd36a5d1a540c81bcc`, the patcher updates it

### Worker thread

- A worker thread runs an ASIO `io_context` in a loop starting at `0x1007EC10`
- `run()` returns immediately when there is no pending work, the loop calls it again with no wait
- Result: one core at 100% for the whole session
- Patch: the loop back jump goes through a small stub that calls `Sleep(1)`
- The stub is placed after the `noreturn` exception call, where the bytes were unreachable
- `Sleep` is called through the existing import thunk at `0x100D7540` with a relative call, so no new relocations are needed

Before:

```
1007EC3D  cmp  dword ptr [esp+4], 0
1007EC42  je   1007EC16            ; 74 D2
1007EC44  lea  eax, [esp+4]
1007EC48  push eax
1007EC49  call 1000AECF            ; throws, does not return
1007EC4E  pop  esi                 ; unreachable
1007EC4F  int3 padding
```

After:

```
1007EC3D  cmp  dword ptr [esp+4], 0
1007EC42  je   1007EC4E            ; 74 0A
1007EC44  lea  eax, [esp+4]
1007EC48  push eax
1007EC49  call 1000AECF
1007EC4E  push 1                   ; 6A 01
1007EC50  call 100D7540            ; E8 EB 88 05 00, jmp [Sleep]
1007EC55  jmp  1007EC16            ; EB BF
```

### Material walk

- `0x100706E0` runs every frame and updates the NGG shader values
- It first calls `0x100705B0`, which walks the game's model list (`0x91A0D0`), every mesh and every material entry (`0x68` bytes each)
- For entries with effect id `[+0x30] == 0` it hashes `ANM_WATERA_` and `ANM_WATERA_001` with the game's string hash (`0x460BF0`), sets id 8 on a match and writes the effect pointer `[+0x34]` from the game's effect table (`0x93DE78`)
- The game already writes `[+0x34]` from the same table when it loads the material chunk (`0x134B02`, loop at `0x6E3F90` in the exe), so for everything except new water materials the write changes nothing
- Most of the cost is cache misses while walking the lists, around 8.5% of main thread samples at `0x100705F2`, `0x100705FA`, `0x10070607`
- Patch: the call goes through a stub in the `int3` padding at `0x100706B0` that counts frames and calls the walk every 8th frame
- The counter is at `0x1011AFFC`, unused space after the end of `.data` (virtual size `0x8DE0`) inside the same writable page
- The module gets loaded at a different base in game, so the stub finds the counter relative to its own address with `call` / `pop eax`, no new relocations are needed
- New water materials get their shader within 8 frames of loading

Before:

```
100706B0  int3 padding
100706FC  call 100705B0                  ; E8 AF FE FF FF
```

After:

```
100706B0  call 100706B5                  ; E8 00 00 00 00
100706B5  pop  eax                       ; 58
100706B6  inc  dword ptr [eax+0AA947h]   ; FF 80 47 A9 0A 00, 1011AFFC
100706BC  test byte ptr [eax+0AA947h], 7 ; F6 80 47 A9 0A 00 07
100706C3  jne  100706CA                  ; 75 05
100706C5  jmp  100705B0                  ; E9 E6 FE FF FF
100706CA  ret                            ; C3
100706FC  call 100706B0                  ; E8 AF FF FF FF
```

| VA | File offset | Before | After |
|---|---|---|---|
| `0x100706B0` | `0x6FAB0` | 27 x `CC` | stub above |
| `0x100706FE` | `0x6FAFE` | `FE` | `FF` |

## MW360Tweaks.asi

- SHA-256 original: `7784a333b1e1e8765ce788ce1f97c5ccec7c4e602ac813485eb4f6d8b4cb5ca4`
- SHA-256 patched: `c15364f2c3c267b2fd33ab415207a9864669ec1cc6da3ab081eac6e1a9572c06`
- Each frame the mod checks 4 texture pointers and calls `D3DXCreateTextureFromFileA` (from `d3dx9_26.dll`) for any that are null
- Files: `BlurMask.png`, `ColorTint.png`, `RocksTex.png`, `RocksNormal.png`
- These files are not part of Redux V3, the load fails and the pointer stays null, so the load runs again next frame
- In a race around 37% of main thread samples were inside `NtCreateFile` from these calls
- Patch: the 4 `jne` checks become `jmp`, so the load is always skipped
- Textures were never loaded before, so nothing changes visually
- If you add the PNG files yourself, do not use this patch for that file

| VA | File offset | Before | After |
|---|---|---|---|
| `0x100015D5` | `0x9D5` | `jne` (`75`) | `jmp` (`EB`) |
| `0x10001611` | `0xA11` | `jne` (`75`) | `jmp` (`EB`) |
| `0x1000163F` | `0xA3F` | `jne` (`75`) | `jmp` (`EB`) |
| `0x1000166D` | `0xA6D` | `jne` (`75`) | `jmp` (`EB`) |

## Measurements

### Benchmark scenario

Everything from the ablation onwards uses this scenario. The two tables further down are older and were recorded before it.

- Quick Race, sprint, Boundary & Marina, Porsche Cayman S, no tuning
- The race takes 98 s at best and about 104 s when not pushed, so the capture window has to fit inside that
- `bench/record.ps1 <name>` waits 10 s, then captures 75 s with PresentMon 2.5.1
- `bench/stats.py` drops the first 5 s of every capture by time, so 70 s is analysed
- 3 runs per configuration, the laptop on mains, no overlay or driver changes between runs
- 1920x1080 at 144 Hz, `ResX` and `ResY` left at 0 so the game takes the desktop resolution
- `Settings.ini`: `g_VSyncOn = 0`, `g_PerformanceLevel = 5`, `g_WorldLodLevel = 3`, `g_CarLodLevel = 1`, `g_ShadowDetail = 2`, `g_RoadReflectionEnable = 2`
- The game runs on the discrete GPU, `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` has `GpuPreference=2` for the exe
- With every patch applied and `SimRate = -1` the frame rate sits near the 144 Hz the `SimRate` patch derives from the display, so the fastest configurations can run into that ceiling. Configurations S0 to S5 use `SimRate = 60` for that reason

A check capture with every patch applied and `SimRate = -1` gave 141.8 avg FPS, 86.4 1% low, 10.4 ms 99th percentile, 6.6 ms median CPU busy, 4.5 ms median GPU busy and no frame over 33 ms. It used the older 25 s plus 90 s window and is a single run, so it is not an ablation result.

### Same sprint race, 90 s per run, two runs per setup

| Setup | Avg FPS | 99th percentile frame time | 1% low FPS | CPU busy per frame |
|---|---|---|---|---|
| Patches v1.0.0, `SimRate = 60` | 84.4 / 84.6 | 19.2 / 18.5 ms | 29.3 / 46.6 | 11.4 / 11.3 ms |
| `SimRate = -1` (144 Hz) | 146.1 / 146.5 | 10.1 / 10.7 ms | 62.6 / 75.1 | 6.5 / 6.5 ms |
| Same + material walk patch | 150.1 / 147.7 | 10.9 / 11.0 ms | 67.6 / 72.8 | 6.3 / 6.4 ms |

- At `SimRate = 60` the main thread ran about 58% of the time, 29% of the trace was `Sleep` called from the simulation step wait at `0x642E60` in the exe
- At `SimRate = -1` the main thread runs 92-95% of the time and FPS sits at the 144 Hz step, so CPU savings show up in CPU busy time more than in average FPS
- WPR traces before and after the material walk patch: `NextGenGraphics.MostWanted.asi` went from 15.2% to 7.6% of main thread samples

### Earlier runs

Same laptop, 2 min PresentMon captures, different races so treat it as a rough comparison.

| Setup | Avg FPS | 99th percentile frame time | Frames over 33 ms |
|---|---|---|---|
| Stock Redux V3 | 20-40 (in-game counter) | - | - |
| Patches | 74 | 39.3 ms | 237 |
| Patches + lower reflection settings | 72 | 23.7 ms | 0 |
| Same + exclusive fullscreen | 71 | 24.9 ms | 13 |

- The Patches run also includes about 10 s of menu at 95-100 FPS
- The fullscreen run includes the first seconds of loading into the race
- Present to display time (PresentMon `MsUntilDisplayed`): 8.9 ms borderless windowed (Composed: Copy with GPU GDI), 3.7 ms exclusive fullscreen (Hardware Composed: Independent Flip)
