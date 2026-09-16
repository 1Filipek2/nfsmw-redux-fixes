# Technical details

All addresses assume the default image base `0x10000000`. File offsets are raw offsets in the file.

## How the problems were found

- PresentMon: frame times, CPU busy time and GPU time per frame
- Per thread CPU usage of the game process
- Thread start addresses to find which module created each busy thread
- Sampling the instruction pointer and stack of busy threads to find the exact loops

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
- SHA-256 patched: `73eef80cb79cc3f8b58ad4babf65aec72ada80f7b3fd16fd36a5d1a540c81bcc`
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
