"""Turn PresentMon CSV captures into one markdown table row per configuration."""

import argparse
import csv
import glob
import statistics
import sys
from pathlib import Path

WARMUP_DEFAULT = 5.0
STUTTER_MS = 33.0


def read_frames(path, process, warmup):
    """Return (frametimes, cpu_busy, gpu_busy, seconds) with the warmup cut by time."""
    times, frametimes, cpu, gpu = [], [], [], []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            if process and row.get("Application", "").lower() != process.lower():
                continue
            try:
                t = float(row["TimeInMs"])
                ft = float(row["MsBetweenPresents"])
            except (KeyError, ValueError):
                continue
            times.append(t)
            frametimes.append(ft)
            cpu.append(to_float(row.get("MsCPUBusy")))
            gpu.append(to_float(row.get("MsGPUBusy")))

    if not times:
        raise SystemExit(f"error: no frames for process {process!r} in {path}")

    start = times[0] + warmup * 1000.0
    keep = [i for i, t in enumerate(times) if t >= start]
    if len(keep) < 2:
        raise SystemExit(f"error: {path} is shorter than the {warmup} s warmup")

    frametimes = [frametimes[i] for i in keep]
    cpu = [c for i in keep if (c := cpu[i]) is not None]
    gpu = [g for i in keep if (g := gpu[i]) is not None]
    seconds = (times[keep[-1]] - times[keep[0]]) / 1000.0
    return frametimes, cpu, gpu, seconds


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def percentile(values, q):
    """Nearest-rank percentile, q in 0..1."""
    ordered = sorted(values)
    rank = max(1, min(len(ordered), round(q * len(ordered))))
    return ordered[rank - 1]


def analyse(path, process, warmup):
    frametimes, cpu, gpu, seconds = read_frames(path, process, warmup)
    worst = sorted(frametimes, reverse=True)
    low_count = max(1, len(frametimes) // 100)
    return {
        "name": Path(path).stem,
        "frames": len(frametimes),
        "seconds": seconds,
        "avg_fps": len(frametimes) / seconds if seconds > 0 else 0.0,
        "p99_ms": percentile(frametimes, 0.99),
        "low1_fps": 1000.0 / statistics.fmean(worst[:low_count]),
        "cpu_ms": statistics.median(cpu) if cpu else float("nan"),
        "gpu_ms": statistics.median(gpu) if gpu else float("nan"),
        "stutters": sum(1 for ft in frametimes if ft > STUTTER_MS),
    }


def spread(runs, key, fmt):
    values = [r[key] for r in runs]
    mean = statistics.fmean(values)
    if len(values) == 1:
        return fmt.format(mean)
    return f"{fmt.format(mean)} ({fmt.format(min(values))}-{fmt.format(max(values))})"


def row(label, runs):
    cells = [
        label,
        str(len(runs)),
        spread(runs, "avg_fps", "{:.1f}"),
        spread(runs, "low1_fps", "{:.1f}"),
        spread(runs, "p99_ms", "{:.1f}"),
        spread(runs, "cpu_ms", "{:.1f}"),
        spread(runs, "gpu_ms", "{:.1f}"),
        spread(runs, "stutters", "{:.0f}"),
    ]
    return "| " + " | ".join(cells) + " |"


HEADER = [
    "| Config | Runs | Avg FPS | 1% low FPS | p99 frame ms | CPU busy ms | GPU busy ms | Frames >33 ms |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", nargs="+", help="PresentMon csv files, one per run")
    parser.add_argument("--label", help="row label, defaults to the shared file name prefix")
    parser.add_argument("--process", default="", help="keep only this Application, empty keeps all")
    parser.add_argument("--warmup", type=float, default=WARMUP_DEFAULT,
                        help="seconds dropped at the start of every run")
    parser.add_argument("--per-run", action="store_true", help="also print a row for every run")
    parser.add_argument("--no-header", action="store_true")
    args = parser.parse_args()

    # powershell does not expand wildcards for native commands, so do it here
    paths = []
    for pattern in args.csv:
        matches = sorted(glob.glob(pattern))
        if not matches:
            raise SystemExit(f"error: no file matches {pattern}")
        paths += matches

    runs = [analyse(p, args.process, args.warmup) for p in paths]
    label = args.label or runs[0]["name"].rsplit("-", 2)[0]

    for r in runs:
        print(f"# {r['name']}: {r['frames']} frames, {r['seconds']:.1f} s after warmup",
              file=sys.stderr)

    if not args.no_header:
        print("\n".join(HEADER))
    if args.per_run:
        for r in runs:
            print(row(r["name"], [r]))
    print(row(label, runs))


if __name__ == "__main__":
    main()
