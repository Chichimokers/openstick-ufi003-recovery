#Requires -Version 5.1
<#
  UFI-EDL-Serial.ps1 -- Ruta SERIE para EDL 9008 (driver Qualcomm firmado ya precargado).

  Flujo:
    1) Espera a que el modem entre en EDL 9008.
    2) Windows enlaza automaticamente qcwdfser (precargado: oem98.inf) ->
       el dispositivo pasa a ser un puerto COM "Qualcomm HS-USB QDLoader 9008 (COMx)".
    3) Detecta el COMx y ejecuta: edl.py printgpt --serial --portname COMx (SOLO LECTURA).
    4) Reintenta con cada nueva ventana EDL.

  Uso:  pwsh -File .\UFI-EDL-Serial.ps1 -Attempts 10
#>
[CmdletBinding()]
param(
  [int]$Attempts = 10,
  [int]$PerAttemptSec = 25,
  [string]$Py = 'py',
  [string]$PyArgs = '-3.12',
  [string]$Edl = 'C:\UFI-Recovery\Tools\edl\edl.py'
)
$ErrorActionPreference = 'Continue'
$outDir = 'C:\UFI-Recovery\Diagnostico\Reports'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir ("edl-serial-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format o), $Level, $m
  Add-Content -Path $out -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

function Get-EdlDevice {
  Get-CimInstance Win32_PnPEntity -Property DeviceID,Name -EA SilentlyContinue |
    Where-Object { $_.DeviceID -match 'VID_05C6&PID_9008' }
}
function Get-ComPort {
  # 1) El propio dispositivo EDL con nombre amistoso "(COMx)"
  $d = Get-CimInstance Win32_PnPEntity -Property DeviceID,Name -EA SilentlyContinue |
       Where-Object { $_.DeviceID -match 'VID_05C6&PID_9008' -and $_.Name -match '\(COM\d+\)' }
  if ($d) { $m = [regex]::Match($d[0].Name,'\(COM(\d+)\)'); return "COM$($m.Groups[1].Value)" }
  # 2) Puerto serie clase Ports con "QDLoader" o "Qualcomm"
  $p = Get-CimInstance Win32_PnPEntity -Property Name -EA SilentlyContinue |
       Where-Object { $_.Name -match 'COM\d+' -and $_.Name -match 'QDLoader|Qualcomm' }
  if ($p) { $m = [regex]::Match($p[0].Name,'\(COM(\d+)\)'); return "COM$($m.Groups[1].Value)" }
  return $null
}

L "Ruta SERIE. CONECTA/DESCONECTA el modem para generar ventanas EDL." 'ALERT'
for ($i = 1; $i -le $Attempts; $i++) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $dev = $null
  while ($sw.Elapsed.TotalSeconds -lt $PerAttemptSec) {
    $dev = Get-EdlDevice
    if ($dev) { break }
    Start-Sleep -Milliseconds 300
  }
  if (-not $dev) { L ("Intento {0}/{1}: sin EDL. Reconecta el modem." -f $i,$Attempts) 'WARN'; continue }

  L ("Intento {0}/{1}: EDL presente -> {2}" -f $i,$Attempts,$dev[0].DeviceID) 'ALERT'
  # Esperar a que Windows enlace el driver (aparece COMx)
  $com = $null; $w = [Diagnostics.Stopwatch]::StartNew()
  while ($w.Elapsed.TotalSeconds -lt 12) {
    $com = Get-ComPort
    if ($com) { break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $com) {
    L "Sin COMx aun (el driver puede seguir enlazando). Reintento." 'WARN'
    continue
  }
  L ("Puerto detectado: {0}" -f $com) 'OK'
  L 'Ejecutando: edl.py printgpt --serial (SOLO LECTURA)...' 'OK'
  $res = & $Py $PyArgs $Edl printgpt --serial --portname $com --debugmode 2>&1 | Out-String
  $res | Add-Content -Path $out -Encoding UTF8
  if ($res -match 'GPT|Partition|firehose|Sahara|storage') {
    L '>>> EXITO: Sahara/Firehose responde por serie. Particiones leidas. <<<' 'ALERT'
    L "Backup seguro (lectura completa): py -3.12 edl.py rf C:\UFI-Recovery\Backup\emmc-full.img --serial --portname $com" 'OK'
    L ("Salida: {0}" -f $out) 'OK'
    exit 0
  }
  L ("Sin datos utiles por serie. Fragmento: {0}" -f (($res -split "`r?`n" | Select-Object -Last 5) -join ' / ')) 'WARN'
}
L ("No se logro en {0} intentos. Revisar {1}" -f $Attempts,$out) 'ALERT'
exit 3
