#Requires -Version 5.1
<#
  UFI-EDL-Analyze.ps1  --  Fase 3: diagnostico Qualcomm del modem 4G-UFI (MSM891x).

  Espera (hasta -TimeoutSec) a que aparezca una interfaz del modem, la identifica
  y ejecuta los sondeos posibles sin instalar nada:
    - EDL 9008  (VID_05C6&PID_9008) / QHSUSB_BULK / QDLoader
    - ADB       (dispositivo Android/Debian arrancado)
    - Fastboot  (bootloader)
    - Desconocido (Code 28 = falta driver, etc.)

  Si no aparece nada: emite el checklist de alimentacion/hardware.

  NO INSTALA CONTROLADORES NI PROGRAMAS. Sahara/Firehose requieren herramientas
  externas (edl.py / QPST) que NO se instalan sin autorizacion explicita.

  Ejemplos:
    pwsh -File .\UFI-EDL-Analyze.ps1 -TimeoutSec 600
    pwsh -File .\UFI-EDL-Analyze.ps1 -TimeoutSec 600 -SkipAdbFastboot
#>
[CmdletBinding()]
param(
  [int]$TimeoutSec = 600,
  [string]$Adb = 'adb',
  [string]$Fastboot = 'fastboot',
  [switch]$SkipAdbFastboot
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dir = 'C:\UFI-Recovery\Diagnostico\Reports'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$reportFile = Join-Path $dir ("informe-analisis-{0}.txt" -f $stamp)
$dumpDir = 'C:\UFI-Recovery\Diagnostico\Logs'

$out = [System.Collections.ArrayList]@()
function Say([string]$Msg, [ValidateSet('INFO','OK','WARN','ALERT')][string]$Level='INFO') {
  $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
  [void]$out.Add($line)
  $color = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $color
}
function Flush { $out | Set-Content -Path $reportFile -Encoding UTF8; Say "Informe guardado en: $reportFile" 'OK' }

# --- 0. Entorno -------------------------------------------------------------
Say "Windows $([System.Environment]::OSVersion.Version) / PowerShell $($PSVersionTable.PSVersion)"
foreach ($c in 'adb','fastboot','pnputil') {
  $cmd = Get-Command $c -ErrorAction SilentlyContinue
  if ($cmd) { Say "Herramienta disponible: $c -> $($cmd.Source)" 'OK' } else { Say "Herramienta NO disponible: $c" 'WARN' }
}
$drv = & pnputil /enum-drivers 2>&1 | Out-String
if ($drv -match 'qualcomm|qcusb|qdloader|QHSUSB') { Say 'Drivers Qualcomm presentes en el sistema.' 'OK' }
else { Say 'NO hay drivers Qualcomm instalados: si el modem aparece en 9008 se vera como "Desconocido" (Code 28) y Windows podria intentar descargar driver por Windows Update.' 'WARN' }

# --- 1. Espera y deteccion --------------------------------------------------
Say ("Esperando interfaz del modem (timeout {0}s)... CONECTA EL MODEM AHORA" -f $TimeoutSec) 'OK'
$targets = 'VID_05C6|QHSUSB_BULK|QUSB_BULK|QDLoader|Qualcomm|Android ADB|fastboot|VID_18D1'
$found = $null
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
  $dev = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
         Where-Object { ("$($_.InstanceId)$($_.FriendlyName)") -match $targets }
  if ($dev) { $found = $dev | Select-Object -First 1; break }
  Start-Sleep -Milliseconds 600
  if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) { break }
}

# --- 2. Clasificacion -------------------------------------------------------
$stamp = Get-Date -Format o
$cls = @{}
$stmt = @"
============================================================
 INFORME DIAGNOSTICO CUALCOMM - UFI 4G (MSM891x)
============================================================
"@
[void]$out.Add($stmt)

if (-not $found) {
  Say 'NO aparecio ninguna interfaz utilizable en el bus USB durante el tiempo de espera.' 'ALERT'
  $cls['1_Alimentacion']  = 'NO DEMOSTRADA'
  $cls['2_Cambio_bus_USB']= 'NO'
  $cls['3_SoC_responde']  = 'INDETERMINADO (sin senal USB)'
  $cls['4_EDL_9008']      = 'NO'
  $cls['5_ADB_Fastboot']  = 'NO'
  $cls['6_Causa_probable']= 'ALIMENTACION o HARDWARE (prioritario)'
  Say 'CHECKLIST HARDWARE (hazlos en orden):' 'WARN'
  @(
    '1. Probar otro cable USB (muchos cables son solo de carga: falta linea de datos) y otro puerto.',
    '2. Probar puerto USB 2.0 trasero (placa base), no hub frontal ni USB 3 azul.',
    '3. Probar en otro PC para descartar driver/OS.',
    '4. Mantener pulsado el boton de encendido 10-15 s (algunos UFI tienen bateria interna).',
    '5. Medir con multimetro/tester USB: 5 V (+-0.25) en los pines VCC/GND del conector del modem.',
    '6. Si el equipo estuvo instalado con OpenStick: puede exigir bateria o energia estable para arrancar.',
    '7. Observar LED: si ni parpadea con energia suficiente -> SoC/eMMC/boot muerto o PMIC averiado.'
  ) | ForEach-Object { [void]$out.Add("   $_") }
  Flush; return
}

$hwids = ((Get-PnpDeviceProperty -InstanceId $found.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data -join ' ; ')
$prob = [int]$found.Problem
$vp = $null
$m = [regex]::Match("$hwids $($found.InstanceId)", 'VID_([0-9A-Fa-f]{4})[^0-9A-Fa-f]*PID_([0-9A-Fa-f]{4})')
if ($m.Success) { $vp = "{0}:{1}" -f $m.Groups[1].Value.ToUpper(), $m.Groups[2].Value.ToUpper() }

Say ("DISPOSITIVO DETECTADO: {0}" -f $found.FriendlyName) 'OK'
Say ("  InstanceId : {0}" -f $found.InstanceId) 'INFO'
Say ("  Clase      : {0}" -f $found.Class) 'INFO'
Say ("  Estado     : {0} / Code {1}" -f $found.Status, $prob) 'INFO'
Say ("  VID:PID    : {0}" -f $vp) 'INFO'
Say ("  HardwareIds: {0}" -f $hwids) 'INFO'

# volcado completo
$safe = ($found.InstanceId -replace '[\\/:*?"<>| ]','_'); if ($safe.Length -gt 80) { $safe = $safe.Substring($safe.Length-80) }
$dumpFile = Join-Path $dumpDir ("dump-analisis-{0}.txt" -f $safe)
$props = Get-PnpDeviceProperty -InstanceId $found.InstanceId -ErrorAction SilentlyContinue
("VOLCADO: $($found.InstanceId)`n$stamp`n" + ($props | Select-Object KeyName,Type,Data | Format-List | Out-String)) | Set-Content $dumpFile -Encoding UTF8
Say ("Volcado de propiedades: {0}" -f $dumpFile) 'INFO'

$kind = 'DESCONOCIDO'
if ("$hwids $($found.InstanceId) $($found.FriendlyName)" -match 'PID_9008|QHSUSB_BULK|QUSB_BULK|QDLoader') { $kind = 'EDL_9008' }
elseif ($found.FriendlyName -match 'ADB|Android') { $kind = 'ADB' }
elseif ($found.FriendlyName -match 'fastboot|Fastboot') { $kind = 'FASTBOOT' }

switch ($kind) {
  'EDL_9008' {
    Say 'MODO EDL 9008 DETECTADO: el procesador Qualcomm RESPONDE y expone Sahara/Firehose.' 'ALERT'
    $cls['1_Alimentacion']   = 'SI'
    $cls['2_Cambio_bus_USB'] = 'SI'
    $cls['3_SoC_responde']   = 'SI'
    $cls['4_EDL_9008']       = 'SI'
    $cls['5_ADB_Fastboot']   = 'NO'
    $cls['6_Causa_probable'] = 'FIRMWARE/BOOTLOADER/EMMC (recuperable por Firehose)'
    Say 'Siguiente nivel (Sahara/Firehose) requiere herramienta externa:' 'WARN'
    @(
      'Opcion A: edl.py / edl (bkerler) -> Python + pip; permite loader, lectura/escritura de particiones, flasheo.',
      'Opcion B: Qualcomm QPST (QSaharaServer + QFIL) -> instalador oficial Qualcomm.',
      'Opcion C: Sahara/Firehose desde scripts propios (handshake 0x01 hello + switch a Firehose con el loader del SoC).',
      'Para MSM8915/MSM8916 se necesita el loader/programmer (prog_firehose_*.mbn) de la familia MSM891x.',
      'NO se instalara nada sin tu autorizacion explicita.'
    ) | ForEach-Object { [void]$out.Add("   $_") }
    if ($prob -eq 28) { Say 'Nota: Windows muestra el EDL como dispositivo desconocido por falta del driver QDLoader (normal).' 'INFO' }
  }
  'ADB' {
    Say 'INTERFAZ ADB DETECTADA: hay sistema operativo arrancado (Debian/Android) -> recuperacion por shell.' 'ALERT'
    $cls['1_Alimentacion']   = 'SI'
    $cls['2_Cambio_bus_USB'] = 'SI'
    $cls['3_SoC_responde']   = 'SI'
    $cls['4_EDL_9008']       = 'NO'
    $cls['5_ADB_Fastboot']   = 'SI (ADB)'
    $cls['6_Causa_probable'] = 'SOFTWARE/FIRMWARE corrompido'
    if (-not $SkipAdbFastboot) {
      $serial = (& $Adb devices 2>&1 | Select-Object -Index 1)
      $cmds = @(
        'adb devices -l',
        'adb shell getprop ro.board.platform',
        'adb shell getprop ro.hardware',
        'adb shell cat /proc/cpuinfo | head -20',
        'adb shell ls -l /dev/block/by-name/   # pone de manifiesto particiones eMMC (boot, recovery, system...)'
      )
      [void]$out.Add("   Pruebas ADB sugeridas (con el modem conectado):")
      $cmds | ForEach-Object { [void]$out.Add("     $_") }
      $try1 = (& $Adb devices -l 2>&1 | Out-String)
      [void]$out.Add("   --- adb devices -l ---`n$try1")
      Say ('adb devices -l ejecutado: {0}' -f (($try1 -split "`n" | Where-Object { $_ -match 'device|error' }) -join ' | ')) 'INFO'
    }
  }
  'FASTBOOT' {
    Say 'INTERFAZ FASTBOOT DETECTADA: el bootloader responde.' 'ALERT'
    $cls['1_Alimentacion']   = 'SI'
    $cls['2_Cambio_bus_USB'] = 'SI'
    $cls['3_SoC_responde']   = 'SI'
    $cls['4_EDL_9008']       = 'NO'
    $cls['5_ADB_Fastboot']   = 'SI (Fastboot)'
    $cls['6_Causa_probable'] = 'BOOTLOADER dañado o bloqueado (a-bootloader operativo)'
    if (-not $SkipAdbFastboot) {
      $f = Get-Command $Fastboot -ErrorAction SilentlyContinue
      if ($f) { [void]$out.Add("   --- fastboot devices / getvar all ---`n" + (& $Fastboot devices 2>&1 | Out-String) + (& $Fastboot getvar all 2>&1 | Out-String)) }
      else { Say 'fastboot NO esta instalado: no se puede sondear el bootloader ahora.' 'WARN' }
    }
  }
  default {
    Say ("APARECE UN DISPOSITIVO PERO NO ES EDL/ADB/FASTBOOT. Code {0}." -f $prob) 'WARN'
    $cls['1_Alimentacion']   = 'PARCIAL (el PC ve algo en el bus)'
    $cls['2_Cambio_bus_USB'] = 'SI'
    $cls['3_SoC_responde']   = 'NO CONFIRMADO'
    $cls['4_EDL_9008']       = 'NO'
    $cls['5_ADB_Fastboot']   = 'NO'
    if ($prob -eq 28) { $cls['6_Causa_probable'] = 'FALTA DE DRIVER o firmware que no inicia interfaz utilizable' }
    elseif ($prob -eq 12 -or $prob -eq 10) { $cls['6_Causa_probable'] = 'ENERGIA (Code 12: recursos USB insuficientes -> hub alimentado)' }
    else { $cls['6_Causa_probable'] = 'FIRMWARE intermedio o hardware (revisar volcado de propiedades)' }
    Say 'Pistas: Code 28=driver ausente; Code 12=energia; Code 43=hardware detenido.' 'INFO'
  }
}

[void]$out.Add('------------------------------------------------------------')
[void]$out.Add(' RESUMEN (6 preguntas del protocolo):')
$cls.Keys | Sort-Object | ForEach-Object { [void]$out.Add("   {0,-18}: {1}" -f $_, $cls[$_]) }
Flush
