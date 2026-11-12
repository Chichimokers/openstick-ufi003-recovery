#Requires -Version 5.1
<#
  UFI-EDL-Watchdog.ps1 -- Espera a que el modem entre en EDL 9008 y ejecuta
  AUTOMATICAMENTE "edl.py printgpt" (SOLO LECTURA: lista la tabla de particiones).

  Uso:
    pwsh -File .\UFI-EDL-Watchdog.ps1 -TimeoutSec 600
    (mientras tanto, pon el modem en EDL: "adb reboot edl", combinacion de botones
     o el metodo que ya funciono una vez)

  NO escribe nada en el modem. Para leer particiones o backup completo se ejecutan
  comandos apartes, requieren tu confirmacion.
#>
[CmdletBinding()]
param(
  [int]$TimeoutSec = 600,
  [string]$Py = 'py',
  [string]$PyArgs = '-3.12',
  [string]$Edl = 'C:\UFI-Recovery\Tools\edl\edl.py'
)
$ErrorActionPreference = 'Continue'
$dir = 'C:\UFI-Recovery\Diagnostico\Logs'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir ("edl-printgpt-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format o), $Level, $m
  Add-Content -Path $out -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

if (-not (Test-Path $Edl)) { L "FATAL: no existe $Edl" 'ALERT'; exit 1 }

L ("Esperando EDL 9008 (timeout {0}s)... PON EL MODEM EN MODO EDL AHORA" -f $TimeoutSec) 'OK'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$found = $null
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
  $d = Get-CimInstance Win32_PnPEntity -Property Name,DeviceID,ConfigManagerErrorCode -ErrorAction SilentlyContinue |
       Where-Object { $_.DeviceID -match 'VID_05C6&PID_9008' }
  if ($d) { $found = $d | Select-Object -First 1; break }
  Start-Sleep -Milliseconds 500
}
if (-not $found) { L "TIMEOUT: el modem no entro en EDL 9008" 'ALERT'; exit 2 }

L ("EDL 9008 DETECTADO: {0}" -f $found.DeviceID) 'ALERT'
Start-Sleep -Seconds 2
L "Ejecutando: edl.py printgpt (solo lectura)..." 'OK'
$res = & $Py $PyArgs $Edl printgpt --debugmode 2>&1 | Out-String
$res | Add-Content -Path $out -Encoding UTF8
Write-Host $res
if ($res -match 'GPT|Partition|table') { L "printgpt OK -> tabla de particiones leida. Revisar el fichero." 'OK' }
else { L "printgpt sin datos utiles: puede requerir loader (prog_firehose_*.mbn) del SoC MSM891x." 'WARN'; L "Alternativa: edl.py rl <dir> (lectura de todas las particiones, tampoco escribe)." 'WARN' }
L ("Salida: {0}" -f $out) 'OK'
