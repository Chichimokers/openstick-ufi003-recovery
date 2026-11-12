#Requires -Version 5.1
<#
  UFI-AutoSession.ps1 -- Sesion automatica de diagnostico + captura de oportunidades.

  Hace DOS cosas en paralelo durante -Minutes minutos:
   A) Si el modem aparece como  -> interroga: adb devices, ADB?? interfaces, RNDIS,
      estado del sistema operativo (¿arranca el Debian?).
   B) Si entra en EDL 9008   -> localiza su COMx y REINTENTA "edl.py printgpt"
      (hasta 3 veces por ventana) porque las ventanas EDL son cortas.

  Uso:  pwsh -File .\UFI-AutoSession.ps1 -Minutes 12
#>
[CmdletBinding()]
param(
  [int]$Minutes = 12,
  [string]$Adb = 'D:\Programas\scrcpy-win64-v3.2\scrcpy-win64-v3.2\adb.exe',
  [string]$Py = 'py',
  [string]$PyArgs = '-3.12',
  [string]$Edl = 'C:\UFI-Recovery\Tools\edl\edl.py'
)
$ErrorActionPreference = 'Continue'
$outDir = 'C:\UFI-Recovery\Diagnostico\Reports'
New-Item -ItemType Directory -Force -Path $outDir, 'C:\UFI-Recovery\Diagnostico\Logs' | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $outDir ("auto-session-{0}.txt" -f $stamp)
function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format o), $Level, $m
  Add-Content -Path $out -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

function Get-Dev([string]$rx) { Get-CimInstance Win32_PnPEntity -Property DeviceID,Name,ConfigManagerErrorCode -EA SilentlyContinue | Where-Object { $_.DeviceID -match $rx } }
function Get-Com {
  $d = Get-Dev 'VID_05C6&PID_9008' | Where-Object { $_.Name -match '\(COM\d+\)' }
  if ($d) { $m = [regex]::Match($d[0].Name,'\(COM(\d+)\)'); return "COM$($m.Groups[1].Value)" }
  return $null
}

L ("SESION AUTOMATICA {0} min - CONECTA el modem en FRIO (desenchufado 60 s) y NO lo toques" -f $Minutes) 'ALERT'
$deadline = [Diagnostics.Stopwatch]::StartNew()
$seen18D1 = 0; $seenEDL = 0; $adbOk = $false; $partOk = $false

while ($deadline.Elapsed.TotalMinutes -lt $Minutes -and -not ($partOk -and $adbOk)) {

  # --- A) Modo normal (Android/OpenStick/Debian) -----------------------------
  $normal = Get-Dev 'VID_18D1&PID_D001'
  if ($normal) {
    $seen18D1++
    if ($seen18D1 -le 10) {
      L ("MODO NORMAL detectado ({0}): {1}" -f $seen18D1, $normal[0].DeviceID) 'ALERT'
      $ifs = (Get-Dev 'VID_18D1' | ForEach-Object { "$($_.Name) [$($_.ConfigManagerErrorCode)]" }) -join ' ; '
      L ("  Interfaces del compuesto: {0}" -f $ifs) 'INFO'
      if (-not $adbOk) {
        $l = (& $Adb devices -l 2>&1 | Out-String)
        L ("  adb devices -l: " + (($l -split "`r?`n" | Where-Object { $_ -match 'device|error|offline' }) -join ' / ')) 'INFO'
        if ($l -match 'device$|device\s') { $adbOk = $true; L "  >>> ADB RESPONDE: el sistema arranca y es accesible." 'OK' }
        # Intentar shell directo por si hay interfaz adb sin autorizar
        $r = (& $Adb shell id 2>&1 | Out-String)
        if ($r -match 'uid=') { $adbOk = $true; L ("  adb shell id -> {0}" -f $r.Trim()) 'OK' }
      }
      # Red: hay adaptador RNDIS nuevo?
      $nic = Get-NetAdapter -EA SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'RNDIS|Remote NDIS' -or $_.Name -match 'RNDIS|Ethernet \d' }
      if ($nic) { L ("  Adaptador de red candidato: {0} ({1}) estado={2}" -f $nic.Name, $nic.InterfaceDescription, $nic.Status) 'INFO'
        if ($nic.Status -eq 'Up') {
          $ip = (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -EA SilentlyContinue | Select-Object -First 1).IPAddress
          L ("  IP: {0}" -f $ip) 'OK'
        }
      } else { L "  Sin adaptador RNDIS (Code 28 = Windows no enlazo driver; el sistema no llega a red)" 'WARN' }
    }
  }

  # --- B) Modo EDL 9008 ------------------------------------------------------
  $edlDev = Get-Dev 'VID_05C6&PID_9008'
  if ($edlDev) {
    $seenEDL++
    L ("EDL 9008 detectado ({0}): {1}" -f $seenEDL, $edlDev[0].DeviceID) 'ALERT'
    $com = $null; $w = [Diagnostics.Stopwatch]::StartNew()
    while ($w.Elapsed.TotalSeconds -lt 10 -and -not $com) { $com = Get-Com; if (-not $com) { Start-Sleep -Milliseconds 400 } }
    if ($com) {
      L ("  Puerto: {0} - reintentando printgpt..." -f $com) 'OK'
      for ($t = 1; $t -le 3 -and -not $partOk; $t++) {
        if (-not (Get-Dev 'VID_05C6&PID_9008')) { L "  ventana EDL cerrada" 'WARN'; break }
        L ("  printgpt intento {0}/3..." -f $t) 'INFO'
        $res = & $Py $PyArgs $Edl printgpt --serial --portname $com --debugmode 2>&1 | Out-String
        $res | Add-Content -Path $out -Encoding UTF8
        if ($res -match 'Partition|partition table|gpt|storage' -and $res -notmatch 'Traceback') { $partOk = $true; L "  >>> TABLA DE PARTICIONES LEIDA" 'ALERT' }
        else { L ("  fallo: {0}" -f (($res -split "`r?`n" | Where-Object { $_ -match 'Error|error|Traceback|Timeout|timeout' } | Select-Object -Last 2) -join ' / ')) 'WARN' }
      }
    } else { L "  sin COMx (driver aun enlazando)" 'WARN' }
  }

  Start-Sleep -Milliseconds 700
}

L "-------------------------------------------------------------" 'OK'
L ("Resumen: ventanas modo-normal vistas: {0} | ventanas EDL: {1}" -f $seen18D1, $seenEDL) 'INFO'
L ("ADB funcional: {0}" -f $adbOk) 'INFO'
L ("Tabla de particiones leida: {0}" -f $partOk) 'INFO'
if ($partOk) { L "SIGUIENTE: backup completo (lectura) y luego decidir escritura." 'OK' }
elseif ($adbOk) { L "SIGUIENTE: entrar por ADB/red al sistema y reparar desde dentro." 'OK' }
else { L "SIGUIENTE: cargar loader Firehose especifico de MSM891x para EDL estable." 'WARN' }
L ("Salida: {0}" -f $out) 'OK'
