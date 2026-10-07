# Brave endurecido — Paquete de despliegue por GPO

> **EN:** Hardened Brave Browser rollout for an Active Directory domain. A WiX-built MSI enforces 13
> machine-wide policies (consumer services and telemetry off, sync blocked, Shields left on), deployed
> through Group Policy, with a PowerShell fallback for RMM tools. Docs are in Spanish.

Paquete para instalar **Brave Browser endurecido** en las PCs de un dominio AD (Windows 11 Pro,
en los ejemplos `contoso.local`), gestionado por GPO. Capa de navegador complementaria a Kaspersky
KES: bloqueo de malvertising/ads con las features de consumidor de Brave deshabilitadas
por política.

## Contenido

```
brave-hardening-gpo/
├─ src/BraveHardening.wxs              # fuente WiX v3 de las políticas
├─ scripts/Deploy-BraveHardened.ps1    # despliegue alternativo (RMM / KSC / startup script)
├─ dist/
│  ├─ brave/
│  │  ├─ BraveBrowserStandaloneSilentSetup.exe   # instalador oficial de Brave (v1.91.180)
│  │  └─ SHA256SUMS                              # hash verificado contra el publicado por Brave
│  └─ BraveHardeningPolicies.msi       # MSI de políticas (se genera con build.ps1 / build.sh)
├─ build.ps1                           # rebuild en Windows (WiX v3 candle/light)
├─ build.sh                            # rebuild en Linux (msitools/wixl)
└─ README.md
```

## Las dos piezas (diseño)

| Pieza | Qué hace | Origen |
|-------|----------|--------|
| `BraveBrowserStandaloneSilentSetup.exe` | Instala el navegador, silencioso | **Descargado** del release oficial `v1.91.180` de `brave/brave-browser` (GitHub). SHA256 verificado contra el publicado por Brave; firma Authenticode válida de "Brave Software, Inc." |
| `BraveHardeningPolicies.msi` | Aplica 13 políticas de hardening en `HKLM\SOFTWARE\Policies\BraveSoftware\Brave` | **Construido** desde `src/BraveHardening.wxs` |

El navegador se autoactualiza solo tras la instalación inicial; el MSI de políticas queda
fijo y aplica sin importar la versión de Brave. **No se reempaqueta Brave en un MSI
propio** (congelaría la versión y rompería en cada update).

> **Nota importante:** Brave **no publica un MSI oficial** para Windows (el endpoint
> "msi" de su servidor de descargas entrega el stub `.exe` online). El instalador
> enterprise oficial es `BraveBrowserStandaloneSilentSetup.exe` (offline, silencioso).
> Por eso el navegador se despliega por **startup script** y no por Software Installation
> (que solo acepta MSI). El MSI de políticas sí va por Software Installation.

### Comando de instalación silenciosa

```
# Navegador (ejecutar elevado / como SYSTEM → instalación per-machine, sin UI):
BraveBrowserStandaloneSilentSetup.exe

# Políticas:
msiexec /i "BraveHardeningPolicies.msi" /qn /norestart
```

## Despliegue por GPO

1. Copiar `BraveBrowserStandaloneSilentSetup.exe` y `BraveHardeningPolicies.msi` a un
   share legible por las cuentas de equipo, ej.
   `\\contoso.local\SYSVOL\contoso.local\software\brave\`.
2. `gpmc.msc` → sobre la OU de equipos → **Create a GPO in this domain, and Link it here**.
3. **Navegador** — Editar el GPO → *Computer Configuration → Policies → Windows Settings
   → Scripts (Startup/Shutdown) → Startup* → agregar script PowerShell:
   `scripts/Deploy-BraveHardened.ps1` con parámetro
   `-BraveInstaller "\\contoso.local\SYSVOL\contoso.local\software\brave\BraveBrowserStandaloneSilentSetup.exe"`
   (el script no reinstala si ya está y además asegura las políticas por registro), **o**
   un batch propio que ejecute el `.exe` solo si Brave no está instalado.
4. **Políticas** — mismo GPO → *Computer Configuration → Policies → Software Settings →
   Software installation* → New → Package → `BraveHardeningPolicies.msi` → modo
   **Assigned**.
5. Se aplica al próximo boot (asignación por máquina). Forzar con `gpupdate /force` +
   reinicio.

### Alternativa sin GPO (RMM / Kaspersky Security Center)

`scripts/Deploy-BraveHardened.ps1 -BraveInstaller <ruta al exe>` — instala Brave
silencioso y aplica las mismas 13 políticas por registro. Ejecutar como SYSTEM o admin.

## Políticas aplicadas (13)

Todas DWORD en `HKLM\SOFTWARE\Policies\BraveSoftware\Brave` (registro x64 nativo, no
WOW6432Node). Nombres verificados contra la documentación de Group Policy de Brave.

```
# Servicios de consumidor apagados
TorDisabled               = 1   # canal de salida anonimizado. CRÍTICO en red con datos sensibles
IPFSEnabled               = 0   # red P2P de contenido
BraveWalletDisabled       = 1   # billetera cripto
BraveVPNDisabled          = 1   # VPN paga de Brave
BraveRewardsDisabled      = 1   # tokens BAT
BraveAIChatEnabled        = 0   # Leo AI
BraveNewsDisabled         = 1   # feed de noticias
BraveTalkDisabled         = 1   # videollamadas

# Telemetría apagada
BraveP3AEnabled           = 0
BraveStatsPingEnabled     = 0
BraveWebDiscoveryEnabled  = 0
MetricsReportingEnabled   = 0   # métrica Chromium estándar

# Anti-fuga de datos
SyncDisabled              = 1   # impide sync de datos de la empresa a cuentas personales
```

**Decisiones deliberadas (mantener):**

- **Brave Shields NO se fuerza**: queda activo por defecto, que es lo deseado. Para
  impedir que el usuario lo apague en sitios puntuales existe
  `BraveShieldsDisabledForUrls` (agregar solo si hace falta).
- **DNS over HTTPS NO se toca**: en AD, forzar DoH puede romper la resolución interna
  contra el DC. No agregar `DnsOverHttpsMode`.

## Validación

**Del build** (ya verificado en este paquete):
- Tabla `Registry` del MSI: **13 filas**, todas bajo `SOFTWARE\Policies\BraveSoftware\Brave`,
  valores `#0`/`#1` correctos.
- Summary info Template: **`x64;1033`**.
- En Linux: `msiinfo tables/export/suminfo dist/BraveHardeningPolicies.msi`.
  En Windows: COM `WindowsInstaller.Installer` u Orca.

**En un equipo de prueba** (tras `gpupdate /force` + reiniciar Brave):
- `brave://policy` muestra las 13 políticas activas.
- Banner "Your browser is managed by your organization" → **es normal**, no es error.
- Rewards, Wallet, Tor y Leo ya no aparecen en la UI.

**Del instalador de Brave**:
- `SHA256SUMS` coincide con el `.sha256` publicado en el release de GitHub.
- Firma Authenticode: `Get-AuthenticodeSignature` → Valid, CN="Brave Software, Inc."

## Rebuild del MSI de políticas

- **Windows:** `.\build.ps1` (WiX v3 en PATH) o `.\build.ps1 -WixBin <carpeta wix314-binaries>`.
- **Linux:** `./build.sh` (requiere `apt-get install wixl`).
- Al versionar: generar un **ProductCode** (Product/@Id) nuevo y subir Version; el
  **UpgradeCode debe permanecer constante** para que funcione el upgrade.
- El `.wxs` usa esquema **WiX v3** (`schemas.microsoft.com/wix/2006/wi`). No compilar
  con WiX v4/v5 sin migrar.

## Pendientes / opciones futuras

- Variante por **plantillas ADMX de Brave** en el Central Store (asset
  `policy_templates.zip` del mismo release) en lugar del MSI de políticas.
- `BraveShieldsDisabledForUrls` si algún sistema interno lo requiere.
