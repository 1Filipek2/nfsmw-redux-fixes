param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Name,
    [int]$Seconds = 75,
    [int]$Delay = 10,
    [string]$Process,
    [string]$GameDir = "D:\NFSMW",
    [string]$Hotkey,
    [string]$PresentMon = "D:\tools\PresentMon-2.5.1-x64.exe"
)

if ($Name -match '[\/:\*\?"<>\|]') {
    Write-Host "error    run name must not contain path characters"
    exit 1
}

if (-not (Test-Path $PresentMon)) {
    $found = Get-Command "PresentMon*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        Write-Host "error    PresentMon not found, pass -PresentMon <path>"
        exit 1
    }
    $PresentMon = $found.Source
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "error    PresentMon needs an elevated shell, start powershell as administrator"
    exit 1
}

# the exe name differs between installs, so take it from the process running out of the game folder
if (-not $Process) {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith("$GameDir\", [StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if (-not $running) {
        Write-Host "error    nothing running out of $GameDir, start the game first or pass -Process <exe>"
        exit 1
    }
    $Process = [IO.Path]::GetFileName($running.Path)
}

$results = Join-Path $PSScriptRoot "results"
if (-not (Test-Path $results)) { New-Item -ItemType Directory -Path $results | Out-Null }
$csv = Join-Path $results ("{0}-{1}.csv" -f $Name, (Get-Date -Format "yyyyMMdd-HHmmss"))

$pmArgs = @(
    "--process_name", $Process,
    "--output_file", $csv,
    "--timed", $Seconds,
    "--terminate_after_timed",
    "--stop_existing_session"
)
# the delay puts every alt-tab and the countdown outside the capture, so the window is always mid race
if ($Hotkey) { $pmArgs += @("--hotkey", $Hotkey) } else { $pmArgs += @("--delay", $Delay) }

Write-Host "run      $Name"
Write-Host "process  $Process"
Write-Host "output   $csv"
if ($Hotkey) {
    Write-Host "press    $Hotkey in the game to start, recording stops after $Seconds s"
} else {
    Write-Host "start    switch to the game and start the race now"
    Write-Host "capture  $Delay s from now, then $Seconds s of frames"
}

& $PresentMon @pmArgs
$code = $LASTEXITCODE

if (-not (Test-Path $csv)) {
    # presentmon writes no file at all when it captured zero frames
    Write-Host "error    no csv written (exit $code), PresentMon saw no frames of $Process"
    exit 1
}
if ($code -ne 0) {
    Write-Host "error    PresentMon exited with $code"
    exit 1
}

$rows = (Get-Content $csv | Measure-Object -Line).Lines - 1
Write-Host "done     $rows frames in $([IO.Path]::GetFileName($csv))"
exit 0
