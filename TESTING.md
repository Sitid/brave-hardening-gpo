# Workflow — Armado y testeo local del paquete

Flujo completo para construir y probar el paquete en una PC local (la tuya o una VM
de prueba) **antes** de tocar GPO. Todo es reversible; la Fase 5 deja la máquina como
estaba.

> Convenciones: todos los comandos van en **PowerShell como Administrador**, parado
> en la raíz del repo (`brave-hardening-gpo`). Los checkpoints (✔) son la salida
> esperada; si no coincide, no avances de fase.

---

## Fase 0 — Requisitos

- Windows 10/11 x64 con permisos de administrador.
- El repo clonado o copiado localmente.
- `dist\brave\BraveBrowserStandaloneSilentSetup.exe` presente (no viaja por git;
  si falta, seguí `dist\brave\PLACEHOLDER.txt` para descargarlo).

```powershell
cd "C:\ruta\a\brave-hardening-gpo"
Test-Path .\dist\brave\BraveBrowserStandaloneSilentSetup.exe   # ✔ True
```

---

## Fase 1 — Armado del MSI de políticas

El MSI no se versiona: se genera en esta fase desde `src\BraveHardening.wxs`.

**1.1 — Obtener WiX v3 portable** (sin instalación, sin admin):

```powershell
$wix = "$env:TEMP\wix314"
New-Item -ItemType Directory -Force $wix | Out-Null
Invoke-WebRequest "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip" -OutFile "$wix\wix.zip"
Expand-Archive "$wix\wix.zip" -DestinationPath $wix -Force
```

**1.2 — Compilar:**

```powershell
.\build.ps1 -WixBin $wix
# ✔ "OK -> dist\BraveHardeningPolicies.msi"
# Warnings esperados (ignorar): LGHT1079 (cab vacío, no lleva archivos)
#                               LGHT1105 (validación ICE requiere admin)
```

**1.3 — Checkpoint del build** — 13 filas en la tabla Registry y Template x64:

```powershell
$msi = (Resolve-Path .\dist\BraveHardeningPolicies.msi).Path
$i = New-Object -ComObject WindowsInstaller.Installer
$db = $i.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$i,@($msi,0))
$si = $db.GetType().InvokeMember('SummaryInformation','GetProperty',$null,$db,$null)
$si.GetType().InvokeMember('Property','GetProperty',$null,$si,@(7))   # ✔ x64;1033
$v = $db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,@("SELECT ``Name`` FROM ``Registry``"))
$v.GetType().InvokeMember('Execute','InvokeMethod',$null,$v,$null)
$n = 0; while ($v.GetType().InvokeMember('Fetch','InvokeMethod',$null,$v,$null)) { $n++ }
$n                                                                    # ✔ 13
```

---

## Fase 2 — Verificación del instalador de Brave

Nunca desplegar un binario sin verificar. Dos controles independientes:

```powershell
# 2.1 — Hash contra el manifiesto (y contra el publicado por Brave en el release)
$h = (Get-FileHash .\dist\brave\BraveBrowserStandaloneSilentSetup.exe -Algorithm SHA256).Hash.ToLower()
$h                                    # ✔ aca365fb42fcc09f3c13358743790e9b23e237f626eb0f91b686bbd4c00aea40
Select-String $h .\dist\brave\SHA256SUMS   # ✔ matchea la línea del manifiesto

# 2.2 — Firma Authenticode
(Get-AuthenticodeSignature .\dist\brave\BraveBrowserStandaloneSilentSetup.exe) |
  Select-Object Status, @{n='Firmante';e={$_.SignerCertificate.Subject}}
# ✔ Status: Valid   Firmante: CN="Brave Software, Inc.", ...
```

---

## Fase 3 — Instalación local (simula lo que hará el GPO)

Probá las dos piezas **por separado**, porque en producción llegan por vías distintas
(startup script el navegador, Software Installation el MSI).

**3.1 — Navegador** (elevado ⇒ instala per-machine, sin UI; tarda ~1 min):

```powershell
Start-Process .\dist\brave\BraveBrowserStandaloneSilentSetup.exe -Wait
Test-Path "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"   # ✔ True
```

**3.2 — Políticas** (exactamente el comando que ejecuta GPO):

```powershell
msiexec /i "dist\BraveHardeningPolicies.msi" /qn /norestart
```

**3.3 — Checkpoint de registro** — las 13 DWORD en HKLM nativo (no WOW6432Node):

```powershell
reg query "HKLM\SOFTWARE\Policies\BraveSoftware\Brave"
# ✔ 13 valores REG_DWORD: TorDisabled=0x1, IPFSEnabled=0x0, BraveWalletDisabled=0x1,
#   BraveVPNDisabled=0x1, BraveRewardsDisabled=0x1, BraveAIChatEnabled=0x0,
#   BraveNewsDisabled=0x1, BraveTalkDisabled=0x1, BraveP3AEnabled=0x0,
#   BraveStatsPingEnabled=0x0, BraveWebDiscoveryEnabled=0x0,
#   MetricsReportingEnabled=0x0, SyncDisabled=0x1

reg query "HKLM\SOFTWARE\WOW6432Node\Policies\BraveSoftware\Brave" 2>$null
# ✔ error / vacío — si aparece acá, el build no fue x64
```

**3.4 —** El MSI queda registrado como programa instalado (así lo va a administrar GPO):

```powershell
Get-Package "Brave Hardening Policies" -ErrorAction SilentlyContinue   # ✔ 1.0.0
```

---

## Fase 4 — Testeo funcional en Brave

Abrí Brave (si estaba abierto, cerralo del todo y reabrí — las políticas se leen al
arrancar).

| # | Dónde | Qué verificar |
|---|-------|---------------|
| 4.1 | `brave://policy` → botón **Reload Policies** | Las **13 políticas** listadas, Source = *Platform*, Status = **OK**, sin errores en rojo |
| 4.2 | Menú ☰ | Aparece "**Managed by your organization**" → es lo esperado, no es error |
| 4.3 | Menú ☰ | **No** aparecen: Brave Rewards, Wallet, Leo AI, Brave VPN |
| 4.4 | Menú ☰ → New private window | Existe ventana privada normal, pero **no** "New private window with Tor" |
| 4.5 | `brave://settings` | Secciones Rewards/Wallet/Leo ocultas o bloqueadas con ícono de "building" (administrado) |
| 4.6 | `brave://settings/privacy` | Opciones de P3A / estadísticas / Web Discovery apagadas y grisadas |
| 4.7 | `brave://settings/braveSync` | Sync deshabilitado (administrado) |
| 4.8 | Cualquier sitio con publicidad | El **león de Shields sigue activo** y bloqueando (no lo tocamos, debe seguir default-on) |
| 4.9 | (solo en máquina del dominio) `nslookup dc01.contoso.local` | Resolución interna intacta — DoH no se forzó |

Si 4.1 muestra alguna política como *Unknown/Invalid*: el nombre no corresponde a esa
versión de Brave — anotar cuál y revisar contra la doc de Group Policy de Brave antes
de desplegar.

---

## Fase 5 — Rollback (validar el ciclo de vida completo)

Esto también valida lo que pasa cuando el día de mañana se quite el paquete del GPO.

```powershell
# 5.1 — Desinstalar el MSI de políticas
msiexec /x "dist\BraveHardeningPolicies.msi" /qn /norestart

# 5.2 — Checkpoint: la clave debe desaparecer completa
reg query "HKLM\SOFTWARE\Policies\BraveSoftware\Brave"
# ✔ ERROR: The system was unable to find the specified registry key or value.

# 5.3 — Reabrir Brave: brave://policy sin políticas, sin banner "managed".
#       Reinstalar (3.2) y deben volver las 13 → ciclo idempotente OK.

# 5.4 — (opcional) Desinstalar Brave para dejar la máquina limpia:
#       Configuración → Aplicaciones → Brave → Desinstalar
```

---

## Fase 6 — Pasa a producción

Con todas las fases en verde, seguí la sección **"Despliegue por GPO"** del
[README](README.md): copiar `BraveBrowserStandaloneSilentSetup.exe` +
`BraveHardeningPolicies.msi` al share, startup script para el navegador, Software
Installation (Assigned) para el MSI. Probar primero con una **OU piloto** de 2-3
máquinas antes de linkear a la OU general.
