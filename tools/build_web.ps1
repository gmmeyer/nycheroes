# Exports the web build to build/web and copies the city tiles next to it.
# Usage: tools\build_web.ps1 [-Serve] [-Port 8060]
# Set $env:GODOT to use a different Godot executable.
param([switch]$Serve, [int]$Port = 8060)
$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$godot = if ($env:GODOT) { $env:GODOT } else { "C:\Users\gmeyp\Downloads\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe" }
$out = Join-Path $root "build\web"
$tiles = Join-Path $root "data\tiles"

if (-not (Test-Path (Join-Path $tiles "nyc\manifest.json"))) {
    throw "No city tiles found. Run tools\citygen\fetch_data.py and build_tiles.py first."
}

New-Item -ItemType Directory -Force $out | Out-Null
& $godot --headless --path $root --export-release "Web" "build/web/index.html"
if ($LASTEXITCODE -ne 0) { throw "Godot export failed (exit code $LASTEXITCODE)" }

# Mirror the tiles (copies only what changed; the full city is several hundred MB).
robocopy $tiles (Join-Path $out "tiles") /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copying tiles failed (robocopy exit code $LASTEXITCODE)" }
$global:LASTEXITCODE = 0
Write-Host "Web build ready in $out"

if ($Serve) {
    Write-Host "Serving at http://localhost:$Port"
    python -m http.server $Port --bind 127.0.0.1 --directory $out
}
