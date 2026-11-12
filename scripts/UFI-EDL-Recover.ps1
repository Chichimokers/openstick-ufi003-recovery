#Requires -Version 5.1
<#
  UFI-EDL-Recover.ps1 -- Espera a que el modem entre en EDL 9008, instala (si se autoriza)
  el driver WinUSB para ese dispositivo y ejecuta AUTOMATICAMENTE "edl.py printgpt" (SR).

  NO escribe nada en el modem. printgpt solo lee la tabla de particiones.

  Uso:  pwsh -File .\UFI-EDL-Recover.ps1 -TimeoutSec 900 -InstallWinUsb
#>
[CmdletBinding()]
param(
  [int]$TimeoutSec = 900,
  [switch]$InstallWinUsb,
  [string]$Inf = 'C:\UFI-Recovery\Tools\WinUSB-EDL.inf',
  [string]$Py = 'py',
  [string]$PyArgs = '-3.12',
  [string]$Edl = 'C:\UFI-Recovery\Tools\edl\edl.py'
)
$ErrorActionPreference = 'Continue'
$dir = 'C:\UFI-Recovery\Diagnostico\Reports'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $dir ("edl-recover-{0}.txt" -f $stamp)
function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format o), $Level, $m
  Add-Content -Path $out -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

$idAdm = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ("Administrador: {0}" -f $idAdm)
if (-not $idAdm) { L "AVISO: sin admin no se podra instalar el driver (pnputil)." 'WARN' }

L ("Esperando EDL 9008 (timeout {0}s) - CONECTA EL MODEM EN MODO EDL" -f $TimeoutSec) 'OK'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
  $d = Get-CimInstance Win32_PnPEntity -Property DeviceID,Name -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -match 'VID_05C6&PID_9008' }
  if ($d) { break }
  Start-Sleep -Milliseconds 500
}
if (-not $d) { L "TIMEOUT: no aparecio EDL 9008" 'ALERT'; exit 2 }
L ("EDL 9008 presente: {0}" -f $d.DeviceID) 'ALERT'

if ($InstallWinUsb) {
  L ("Instalando driver WinUSB desde {0} ..." -f $Inf) 'WARN'
  $pr = Start-Process -FilePath 'pnputil' -ArgumentList ('/add-driver','"{0}"' -f $Inf,'/install') -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\pnpout.txt" -RedirectStandardError "$env:TEMP\pnperr.txt"
  L ("pnputil salida: " + (Get-Content "$env:TEMP\pnpout.txt" -Raw -EA SilentlyContinue).Trim() + (Get-Content "$env:TEMP\pnperr.txt" -Raw -EA SilentlyContinue).Trim()) 'INFO'
  $svc = (Get-PnpDeviceProperty -InstanceId $d.DeviceID -KeyName 'DEVPKEY_Device_Service' -EA SilentlyContinue).Data
  L ("Servicio asociado ahora: {0} (WinUsb = OK)" -f $svc) 'OK'
  Start-Sleep -Seconds 2
}

L "Ejecutando: edl.py printgpt --debugmode (SOLO LECTURA)..." 'OK'
$res = & $Py $PyArgs $Edl printgpt --debugmode 2>&1 | Out-String
$res | Add-Content -Path $out -Encoding UTF8
Write-Host ($res -split "`r?`n" | Select-Object -Last 40)

if ($res -match 'NotImplementedError|Operation not supported') {
  L "EDL sin acceso raw USB: el driver WinUSB no quedo enlazado. Revisar salida pnputil arriba." 'ALERT'
} elseif ($res -match 'firehose|Firehose|Sahara|GPT|Partition') {
  L "printgpt OK: Sahara responde y tenemos la tabla de particiones." 'OK'
  L "SIGUIENTE PASO SEGURO: backup completo -> py -3.12 edl.py rf C:\UFI-Recovery\Backup\emmc-full.img" 'OK'
} else {
  L "Revisar salida completa en: $out" 'WARN'
}
L ("Salida: {0}" -f $out) 'OK'
