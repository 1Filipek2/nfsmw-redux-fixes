param(
    [string]$GameDir,
    [switch]$Restore
)

# each patch only applies to the exact file version it was made for
$patches = @(
    @{
        File     = "NFSMWGraphics.asi"
        Info     = "hotkey thread Sleep(0) -> Sleep(10)"
        Original = "9a62a02e2a5bd405549e6e12d737f8cea8982c94c3aa115a0bc862898a233619"
        Patched  = "9d0f21454d77f0f41998819f2e76e5f3bb8d815be58fd95c8c92319969e07928"
        Bytes    = @(
            @{ Offset = 0x17C8; Old = @(0x00); New = @(0x0A) },
            @{ Offset = 0x1816; Old = @(0x00); New = @(0x0A) }
        )
    },
    @{
        File     = "NextGenGraphics.MostWanted.asi"
        Info     = "worker thread sleeps 1 ms when idle"
        Original = "f9752191ba30e75e8ec489743f5a20a517b006e3f81e45efc5f0e29441d26cd0"
        Patched  = "73eef80cb79cc3f8b58ad4babf65aec72ada80f7b3fd16fd36a5d1a540c81bcc"
        Bytes    = @(
            @{ Offset = 0x7E043; Old = @(0xD2); New = @(0x0A) },
            @{ Offset = 0x7E04E; Old = @(0x5E, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC); New = @(0x6A, 0x01, 0xE8, 0xEB, 0x88, 0x05, 0x00, 0xEB, 0xBF) }
        )
    },
    @{
        File     = "MW360Tweaks.asi"
        Info     = "no more per-frame loading of missing png textures"
        Original = "7784a333b1e1e8765ce788ce1f97c5ccec7c4e602ac813485eb4f6d8b4cb5ca4"
        Patched  = "c15364f2c3c267b2fd33ab415207a9864669ec1cc6da3ab081eac6e1a9572c06"
        Bytes    = @(
            @{ Offset = 0x9D5; Old = @(0x75); New = @(0xEB) },
            @{ Offset = 0xA11; Old = @(0x75); New = @(0xEB) },
            @{ Offset = 0xA3F; Old = @(0x75); New = @(0xEB) },
            @{ Offset = 0xA6D; Old = @(0x75); New = @(0xEB) }
        )
    }
)

function Get-Sha256 {
    param([byte[]]$Data)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = ($sha.ComputeHash($Data) | ForEach-Object { $_.ToString("x2") }) -join ""
    $sha.Dispose()
    return $hash
}

function Find-GameDir {
    param([string]$Dir)
    $candidates = if ($Dir) { @($Dir) } else { @((Get-Location).Path, (Split-Path $PSScriptRoot -Parent)) }
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "scripts\*.asi")) { return (Resolve-Path $c).Path }
    }
    $answer = (Read-Host "game folder not found, enter the path to it").Trim('"', ' ')
    if (-not $answer -or -not (Test-Path (Join-Path $answer "scripts\*.asi"))) { return $null }
    return (Resolve-Path $answer).Path
}

function Invoke-Patch {
    param($Patch, [string]$Path)
    $data = [IO.File]::ReadAllBytes($Path)
    $hash = Get-Sha256 $data

    if ($hash -eq $Patch.Patched) { Write-Host "skip     $($Patch.File) (already patched)"; return $true }
    if ($hash -ne $Patch.Original) { Write-Host "skip     $($Patch.File) (unknown version, not touched)"; return $true }

    foreach ($b in $Patch.Bytes) {
        for ($i = 0; $i -lt $b.Old.Count; $i++) {
            if ($data[$b.Offset + $i] -ne $b.Old[$i]) {
                Write-Host "error    $($Patch.File): unexpected byte at offset 0x$('{0:X}' -f ($b.Offset + $i))"
                return $false
            }
            $data[$b.Offset + $i] = [byte]$b.New[$i]
        }
    }
    if ((Get-Sha256 $data) -ne $Patch.Patched) {
        Write-Host "error    $($Patch.File): patched file hash mismatch, nothing written"
        return $false
    }

    if (-not (Test-Path "$Path.orig")) { Copy-Item $Path "$Path.orig" }
    [IO.File]::WriteAllBytes($Path, $data)
    Write-Host "patched  $($Patch.File) ($($Patch.Info))"
    return $true
}

function Invoke-Restore {
    param($Patch, [string]$Path)
    $backup = "$Path.orig"
    if (-not (Test-Path $backup)) { Write-Host "skip     $($Patch.File) (no backup)"; return $true }
    if ((Get-Sha256 ([IO.File]::ReadAllBytes($backup))) -ne $Patch.Original) {
        Write-Host "skip     $($Patch.File) (backup is not the original version)"
        return $true
    }
    Copy-Item $backup $Path -Force
    Remove-Item $backup
    Write-Host "restored $($Patch.File)"
    return $true
}

$game = Find-GameDir $GameDir
if (-not $game) {
    Write-Host "no scripts folder with .asi files found there"
    exit 1
}
Write-Host "game folder: $game"

# patching a loaded asi fails or gets overwritten, so the game has to be closed
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith("$game\", [StringComparison]::OrdinalIgnoreCase)
}
if ($running) {
    Write-Host "the game is running, close it first (check task manager if it hangs on exit)"
    exit 1
}

$failed = $false
foreach ($p in $patches) {
    $path = Join-Path $game "scripts\$($p.File)"
    if (-not (Test-Path $path)) { Write-Host "skip     $($p.File) (not installed)"; continue }
    $ok = if ($Restore) { Invoke-Restore $p $path } else { Invoke-Patch $p $path }
    if (-not $ok) { $failed = $true }
}

if ($failed) { exit 1 }
exit 0
