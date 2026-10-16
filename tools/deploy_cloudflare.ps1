# Publishes the web build to https://nycheroes.party on Cloudflare
# (tools/cloudflare): the game and city tiles as Worker static assets,
# index.wasm in the R2 bucket, co-op signaling in a Durable Object. Wrangler
# uploads only files that changed.
# Usage: tools\deploy_cloudflare.ps1 [-Build] [-Web <dir>] [-Tiles <dir>] [-Desktop]
# -Build runs tools\build_web.ps1 first. -Web is the exported game (default
# build\web), -Tiles the city tiles (default: the tiles next to the game).
# -Desktop also uploads the Windows and Mac versions (build\desktop\nyc-heroes-
# windows.zip and nyc-heroes-macos.zip, from tools\build_desktop.ps1) to the
# R2 bucket under downloads/, where download.html links to them (each is over
# the 25 MiB asset limit); only zips that changed are sent.
# Needs `npx wrangler login`, or a `cf auth login` (the Cloudflare CLI),
# whose login it then lends to Wrangler.
param([switch]$Build, [string]$Web, [string]$Tiles, [switch]$Desktop)
$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
if (-not $Web) { $Web = Join-Path $root "build\web" }
if (-not $Tiles) { $Tiles = Join-Path $Web "tiles" }
$stage = Join-Path $root "build\cloudflare"
$config = Join-Path $PSScriptRoot "cloudflare\wrangler.jsonc"
$bucket = "nyc-hero-files"

if ($Build) { & (Join-Path $PSScriptRoot "build_web.ps1") }
if (-not (Test-Path (Join-Path $Web "index.wasm"))) { throw "No web build in $Web. Run tools\build_web.ps1 first." }
$zips = @()
if ($Desktop) {
    $zips = "nyc-heroes-windows.zip", "nyc-heroes-macos.zip" | ForEach-Object { Join-Path $root "build\desktop\$_" }
    foreach ($zip in $zips) {
        if (-not (Test-Path $zip)) { throw "No $zip. Run tools\build_desktop.ps1 first." }
    }
}

# Wrangler's own login, else the Cloudflare CLI's (its OAuth token works as
# an API token; `cf auth whoami` refreshes it when it has expired).
function Use-Login {
    if ($env:CLOUDFLARE_API_TOKEN) { return }
    $cfConfig = Join-Path $env:APPDATA "xdg.config\cloudflare\config\default.json"
    if (-not (Get-Command cf -ErrorAction SilentlyContinue) -or -not (Test-Path $cfConfig)) { return }
    $who = cf auth whoami | ConvertFrom-Json
    if (-not $who.authenticated) { return }
    $script:lent = $true
    $env:CLOUDFLARE_API_TOKEN = (Get-Content $cfConfig -Raw | ConvertFrom-Json).oauth_token
    $env:CLOUDFLARE_ACCOUNT_ID = $who.accounts[0].id
}
function Clear-Login {
    if ($script:lent) { Remove-Item Env:CLOUDFLARE_API_TOKEN, Env:CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue }
}

# Stage the game (without the engine) and the tiles (without aerial photos).
robocopy $Web $stage /MIR /NFL /NDL /NJH /NJS /NP /XD (Join-Path $Web "tiles") /XF index.wasm | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Staging the game failed (robocopy exit code $LASTEXITCODE)" }
robocopy $Tiles (Join-Path $stage "tiles") /MIR /NFL /NDL /NJH /NJS /NP /XD (Join-Path $Tiles "nyc\aerial") | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Staging the tiles failed (robocopy exit code $LASTEXITCODE)" }
$global:LASTEXITCODE = 0

try {
    Use-Login
    # The engine goes to R2, only when it changed.
    $hash = (Get-FileHash (Join-Path $Web "index.wasm") -Algorithm SHA256).Hash
    $hashFile = Join-Path $root "build\cloudflare-wasm.sha256"
    if (-not (Test-Path $hashFile) -or (Get-Content $hashFile) -ne $hash) {
        npx wrangler r2 bucket create $bucket --config $config 2>$null | Out-Null  # first time only
        npx wrangler r2 object put "$bucket/index.wasm" --file (Join-Path $Web "index.wasm") --content-type application/wasm --remote --config $config
        if ($LASTEXITCODE -ne 0) { throw "Uploading index.wasm failed" }
        Set-Content $hashFile $hash
    }
    # The desktop versions, likewise.
    foreach ($zip in $zips) {
        $name = Split-Path $zip -Leaf
        $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
        $hashFile = Join-Path $root "build\cloudflare-$name.sha256"
        if ((Test-Path $hashFile) -and (Get-Content $hashFile) -eq $hash) { continue }
        npx wrangler r2 object put "$bucket/downloads/$name" --file $zip --content-type application/zip --remote --config $config
        if ($LASTEXITCODE -ne 0) { throw "Uploading $name failed" }
        Set-Content $hashFile $hash
    }
    # A long first upload can outlast a borrowed login; files already sent
    # aren't sent again, so a retry with a fresh one finishes quickly.
    for ($try = 1; $try -le 3; $try++) {
        npx wrangler deploy --config $config
        if ($LASTEXITCODE -eq 0) { break }
        if ($try -eq 3 -or -not $script:lent) { throw "wrangler deploy failed" }
        Clear-Login
        Use-Login
    }
} finally {
    Clear-Login
}
Write-Host "Deployed to https://nycheroes.party"
