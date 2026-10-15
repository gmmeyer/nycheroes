# Exports the web build to build/web and copies the city tiles next to it.
# Usage: tools\build_web.ps1 [-Serve] [-Port 8060] [-Aerial]
# -Serve also runs the co-op signaling server (tools/signaling, needs Node.js).
# -Aerial also copies the aerial photos (1.2 GB; the game only shows them with
# ?aerial=1, for comparison).
# Set $env:GODOT to use a different Godot executable.
param([switch]$Serve, [int]$Port = 8060, [switch]$Aerial)
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

# Mirror the tiles (copies only what changed; the full city is about 1 GB).
$skip = if ($Aerial) { @() } else { @("/XD", (Join-Path $tiles "nyc\aerial")) }
robocopy $tiles (Join-Path $out "tiles") /MIR /NFL /NDL /NJH /NJS /NP @skip | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copying tiles failed (robocopy exit code $LASTEXITCODE)" }
$global:LASTEXITCODE = 0
Write-Host "Web build ready in $out"

if ($Serve) {
    # The co-op signaling server runs alongside (port 8070), so hosting works locally.
    $signaling = Join-Path $root "tools\signaling"
    if (-not (Test-Path (Join-Path $signaling "node_modules"))) {
        npm install --prefix $signaling --no-fund --no-audit | Out-Null
    }
    $server = Start-Process node -ArgumentList "server.mjs" -WorkingDirectory $signaling -NoNewWindow -PassThru
    Write-Host "Serving at http://localhost:$Port (co-op signaling on port 8070)"
    try {
        python -m http.server $Port --bind 127.0.0.1 --directory $out
    } finally {
        Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
    }
}
