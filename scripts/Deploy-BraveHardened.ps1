# Deploy-BraveHardened.ps1
# Instala Brave Browser (silencioso, system-level) y aplica las politicas de hardening
# por registro. Pensado para push por RMM / startup script / tarea remota del KSC.
#
# Nota: Brave NO publica un MSI oficial. El instalador enterprise oficial es
# BraveBrowserStandaloneSilentSetup.exe (releases de brave/brave-browser en GitHub).
# Este script acepta ese .exe; si se le pasa un .msi (p.ej. el MSI de politicas u otro),
# lo instala via msiexec.
#
# Uso:
#   .\Deploy-BraveHardened.ps1 -BraveInstaller "\\contoso.local\...\BraveBrowserStandaloneSilentSetup.exe"
#
# Ejecutar como SYSTEM o administrador (escribe HKLM y hace instalacion per-machine).

param([Parameter(Mandatory=$true)][string]$BraveInstaller)
$ErrorActionPreference = "Stop"
function Write-Log { param($m) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" }

if (-not (Test-Path $BraveInstaller)) { throw "No se encuentra el instalador de Brave en: $BraveInstaller" }

# Idempotente: como startup script corre en cada boot; no reinstalar si ya esta.
$braveExe = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"
if (Test-Path $braveExe) {
    Write-Log "Brave ya instalado (per-machine); se omite la instalacion."
} else {
    Write-Log "Instalando Brave..."
    $ext = [System.IO.Path]::GetExtension($BraveInstaller).ToLower()
    if ($ext -eq ".msi") {
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$BraveInstaller`" /qn /norestart" -Wait -PassThru
        if ($p.ExitCode -notin 0,3010) { throw "Brave install exit $($p.ExitCode)" }
    } else {
        # StandaloneSilentSetup: instala sin UI. Ejecutado elevado/SYSTEM instala per-machine.
        $p = Start-Process $BraveInstaller -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Brave install exit $($p.ExitCode)" }
    }
}

$path = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
$dword = @{
  "TorDisabled"=1; "IPFSEnabled"=0; "BraveWalletDisabled"=1; "BraveVPNDisabled"=1
  "BraveRewardsDisabled"=1; "BraveAIChatEnabled"=0; "BraveNewsDisabled"=1; "BraveTalkDisabled"=1
  "BraveP3AEnabled"=0; "BraveStatsPingEnabled"=0; "BraveWebDiscoveryEnabled"=0
  "MetricsReportingEnabled"=0; "SyncDisabled"=1
}
foreach ($n in $dword.Keys) { Set-ItemProperty -Path $path -Name $n -Type DWord -Value $dword[$n] }
# DoH sin tocar a proposito (AD DNS). Shields default-on.
Write-Log "Hardening aplicado. Verificar en brave://policy."
