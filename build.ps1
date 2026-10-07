# build.ps1 — compila src/BraveHardening.wxs a dist/BraveHardeningPolicies.msi
# Requiere WiX Toolset v3 (candle/light). Si no esta en PATH, pasar -WixBin con la
# carpeta de los binarios (p.ej. los portables wix314-binaries.zip de wixtoolset/wix3).
param([string]$WixBin = "")

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$candle = if ($WixBin) { Join-Path $WixBin "candle.exe" } else { "candle.exe" }
$light  = if ($WixBin) { Join-Path $WixBin "light.exe" }  else { "light.exe" }

$obj = Join-Path $env:TEMP "BraveHardening.wixobj"
& $candle -arch x64 -out $obj "$root\src\BraveHardening.wxs"
if ($LASTEXITCODE -ne 0) { throw "candle fallo ($LASTEXITCODE)" }
& $light -out "$root\dist\BraveHardeningPolicies.msi" $obj
if ($LASTEXITCODE -ne 0) { throw "light fallo ($LASTEXITCODE)" }
Write-Host "OK -> dist\BraveHardeningPolicies.msi"
