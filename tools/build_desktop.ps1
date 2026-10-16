# Exports the Windows and macOS versions to build/desktop and zips them as
# nyc-heroes-windows.zip and nyc-heroes-macos.zip, for the downloads page
# (tools/web/download.html; tools/deploy_cloudflare.ps1 -Desktop uploads them).
# They stream the city tiles from https://nycheroes.party like the web build
# (scripts/world/city_streamer.gd), so the tiles aren't in the zips.
# Usage: tools\build_desktop.ps1 [-Windows] [-Mac] (both when neither is given)
# Windows: one .exe with the game packed in, and the WebRTC extension's DLL
# beside it. macOS: a universal app (Apple silicon and Intel), ad-hoc signed by
# Godot, not notarized (see "Mac and Windows versions" in docs/ROADMAP.md).
# Both zips also hold the game's credits and the engine's and the WebRTC
# extension's licenses.
# Set $env:GODOT to use a different Godot executable.
param([switch]$Windows, [switch]$Mac)
$ErrorActionPreference = "Stop"
if (-not $Windows -and -not $Mac) { $Windows = $true; $Mac = $true }

$root = Split-Path $PSScriptRoot -Parent
$godot = if ($env:GODOT) { $env:GODOT } else { "C:\Users\gmeyp\Downloads\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe" }
$out = Join-Path $root "build\desktop"
New-Item -ItemType Directory -Force $out | Out-Null
# Godot must not import what's in build/ (see tools/build_web.ps1).
$marker = Join-Path $root "build\.gdignore"
if (-not (Test-Path $marker)) { New-Item -ItemType File $marker | Out-Null }

# What goes beside the game in both zips.
$extras = Join-Path $out "extras"
Remove-Item -Recurse -Force $extras -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $extras "licenses") | Out-Null
Copy-Item (Join-Path $root "CREDITS.md") $extras
Get-ChildItem (Join-Path $root "addons\webrtc_native\LICENSE.*") | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $extras "licenses\$($_.Name.Replace('LICENSE.', '')).txt")
}
& $godot --headless --path $root --script res://tools/engine_licenses.gd -- (Join-Path $extras "licenses\godot.txt") | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Writing the engine's licenses failed (exit code $LASTEXITCODE)" }

function Export-Preset([string]$preset, [string]$path) {
    & $godot --headless --path $root --export-release $preset $path
    if ($LASTEXITCODE -ne 0) { throw "Godot export of '$preset' failed (exit code $LASTEXITCODE)" }
}

if ($Windows) {
    $folder = Join-Path $out "windows\NYC Heroes"
    Remove-Item -Recurse -Force (Join-Path $out "windows") -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $folder | Out-Null
    Export-Preset "Windows Desktop" "build/desktop/windows/NYC Heroes/NYC Heroes.exe"
    Copy-Item -Recurse (Join-Path $extras "*") $folder
    $zip = Join-Path $out "nyc-heroes-windows.zip"
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path $folder -DestinationPath $zip -CompressionLevel Optimal
}

if ($Mac) {
    # Godot zips the app itself, keeping the executables' permissions (a zip
    # made or rewritten here wouldn't); the extras are added to it beside the
    # app, outside its signature (Python's zipfile leaves the rest alone).
    $zip = Join-Path $out "nyc-heroes-macos.zip"
    Remove-Item $zip -ErrorAction SilentlyContinue
    Export-Preset "macOS" "build/desktop/nyc-heroes-macos.zip"
    python -I (Join-Path $PSScriptRoot "zip_add.py") $zip $extras
    if ($LASTEXITCODE -ne 0) { throw "Adding the credits and licenses to the Mac zip failed" }
}

Get-ChildItem (Join-Path $out "nyc-heroes-*.zip") | ForEach-Object {
    Write-Host ("{0}: {1:N1} MB" -f $_.Name, ($_.Length / 1MB))
}
Write-Host "Desktop builds ready in $out"
