# Updates the vendored VD.ahk library (lib/VD.ah2) from upstream.
# Usage:  powershell -ExecutionPolicy Bypass -File .\update-vendor.ps1
#
# Clones the upstream repo shallowly into a temp dir, copies VD.ah2 + LICENSE
# into lib/, and prints the commit you should record in lib/UPSTREAM.md.

$ErrorActionPreference = 'Stop'

$repo   = 'https://github.com/FuPeiJiang/VD.ahk.git'
$branch = 'v2_port'
$root   = $PSScriptRoot
$lib    = Join-Path $root 'lib'
$tmp    = Join-Path $env:TEMP ("vdahk-" + [Guid]::NewGuid().ToString('N'))

Write-Host "Cloning $repo ($branch)..."
git clone --depth 1 --branch $branch $repo $tmp | Out-Null

$commit = (git -C $tmp rev-parse HEAD).Trim()

Copy-Item (Join-Path $tmp 'VD.ah2')   (Join-Path $lib 'VD.ah2')          -Force
Copy-Item (Join-Path $tmp 'LICENSE')  (Join-Path $lib 'VD.ahk-LICENSE')  -Force

Remove-Item $tmp -Recurse -Force

Write-Host ""
Write-Host "Updated lib/VD.ah2 to upstream commit:" -ForegroundColor Green
Write-Host "  $commit"
Write-Host ""
Write-Host "Now update the 'Pinned commit' row in lib/UPSTREAM.md and smoke-test the suite."
