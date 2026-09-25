# bench

Measurement kit for the ablation runs. Raw captures land in `bench/results/`, which is not committed.

## Requirements

- PresentMon 2.x (tested with 2.5.1), path passed with `-PresentMon` if it is not `D:\tools\PresentMon-2.5.1-x64.exe`
- Python 3.10 or newer, standard library only
- an elevated PowerShell, PresentMon needs it to open the ETW session

## Recording

```
.\bench\record.ps1 s0-stock
```

- start the game first and sit on the race start screen, the exe name is taken from the process running out of `-GameDir`
- the script waits `-Delay` seconds (10 by default), so switching to the game stays outside the capture
- then records `-Seconds` (75 by default) and PresentMon exits on its own
- the race has to last longer than delay plus capture, otherwise the window ends up in the results screen
- the defaults are set for the Boundary & Marina sprint, which takes 98 to 104 s
- PresentMon writes no file at all when it captured zero frames, the script reports that as an error
- options: `-Delay`, `-Seconds`, `-GameDir`, `-Process`, `-PresentMon`, `-Hotkey MOD+KEY` to start on a key press instead of the delay

## Stats

```
py bench\stats.py bench\results\s0-stock-*.csv --label "S0 stock"
```

- drops the first 5 s of every capture by time (`--warmup`)
- prints one markdown row: avg FPS, 1% low FPS, p99 frame time, median CPU busy, median GPU busy, frames over 33 ms
- several files are averaged into one row with the min-max range in brackets, `--per-run` adds a row per capture
