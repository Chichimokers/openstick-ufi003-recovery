#Requires -Version 5.1
<#
  UFI-EDL-Blast.ps1 -- Ciclo EDL automatizado completo (una sola orden = todo):
    1) Espera a que el modem entre en EDL 9008 (ventanas de ~1 s, se reintenta).
    2) En cuanto aparece: instala/binding del driver (Zadig en modo automatico si soporta CLI,
       o pnputil con INF firmado si el paquete Qualcomm esta presente).
    3) EJECUTA edl.py printgpt EN EL MISMO instante (solo lectura).
    4) Si falla, reintenta hasta -Attempts veces (cada nueva conexion EDL es una oportunidad).

  IMPORTANTE: acompañado de "conecta el modem" cada ~30 s (ver instrucciones).

  Uso:
    pwsh -File .\UFI-EDL-Blast.ps1 -Attempts 8
#>
[CmdletBinding()]
param(
  [int]$Attempts = 8,
  [int]$PerAttemptSec = 20,
  [string]$VidPidPattern = 'VID_05C6&PID_9008',
  [string]$Zadig = 'C:\UFI-Recovery\Tools\zadig.exe',
  [string]$QualcommDir = 'C:\UFI-Recovery\Tools\qud',
  [string]$Py = 'py',
  [string]$PyArgs = '-3.12',
  [string]$Edl = 'C:\UFI-Recovery\Tools\edl\edl.py'
)
$ErrorActionPreference = 'Continue'
$outDir = 'C:\UFI-Recovery\Diagnostico\Reports'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir ("edl-blast-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format o), $Level, $m
  Add-Content -Path $out -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

function Get-EdlDevice {
  Get-CimInstance Win32_PnPEntity -Property DeviceID,Name,ConfigManagerErrorCode -EA SilentlyContinue |
    Where-Object { $_.DeviceID -match $VidPidPattern }
}

function Try-ZadigCli {
  if (-not (Test-Path $Zadig)) { return $false }
  $h = & $Zadig --help 2>&1 | Out-String
  return ($h -match 'vid|pid|install')
}

function Bind-WinUsb {
  # 1) INF firmado de Qualcomm (si se extrajo)
  if (Test-Path $QualcommDir) {
    $inf = Get-ChildItem $QualcommDir -Filter '*.inf' -Recurse | Select-Object -First 1
    if ($inf) {
      $r = & pnputil /add-driver "$($inf.FullName)" /install 2>&1 | Out-String
      L ("pnputil INF firmado: {0}" -f ($r -replace "`r?`n",' | ')) 'INFO'
      if ($r -match 'correctamente|successfully|agregado|added') { return 'pnp-signed' }
    }
  }
  # 2) INF propio WinUSB (no firmado)
  $my = 'C:\UFI-Recovery\Tools\WinUSB-EDL.inf'
  if (Test-Path $my) {
    $r = & pnputil /add-driver "$my" /install 2>&1 | Out-String
    L ("pnputil INF propio: {0}" -f ($r -replace "`r?`n",' | ')) 'INFO'
    if ($r -match 'correctamente|successfully|agregado|added') { return 'pnp-own' }
  }
  return $false
}

function Test-WinUsbBound {
  $d = Get-EdlDevice
  if (-not $d) { return $false }
  $svc = (Get-PnpDeviceProperty -InstanceId $d[0].DeviceID -KeyName 'DEVPKEY_Device_Service' -EA SilentlyContinue).Data
  return ("$svc".ToLower() -eq 'winusb')
}

$zadigOk = Try-ZadigCli
L ("Zadig CLI disponible: {0}" -f $zadigOk)
if (-not $zadigOk -and -not (Test-Path $QualcommDir)) {
  L 'AVISO: sin Qualcomm firmado NI Zadig-CLI. Abriremos Zadig GUI cuando haga falta.' 'WARN'
}

L ("Ciclo EDL automatico: {0} intentos x {1}s. CONECTA Y DESCONECTA el modem cada ~20 s." -f $Attempts, $PerAttemptSec) 'ALERT'

for ($i = 1; $i -le $Attempts; $i++) {
  $deadline = [Diagnostics.Stopwatch]::StartNew()
  $dev = $null
  while ($deadline.Elapsed.TotalSeconds -lt $PerAttemptSec) {
    $dev = Get-EdlDevice
    if ($dev) { break }
    Start-Sleep -Milliseconds 300
  }
  if (-not $dev) { L ("Intento {0}/{1}: sin EDL en {2}s - reconecta el modem" -f $i,$Attempts,$PerAttemptSec) 'WARN'; continue }

  L ("Intento {0}/{1}: EDL detectado {2}" -f $i,$Attempts,$dev[0].DeviceID) 'ALERT'
  $bound = $false
  if (-not (Test-WinUsbBound)) {
    $res = Bind-WinUsb
    if ($res) { $bound = $true }
    elseif ($zadigOk) {
      L 'Lanzando Zadig (CLI) para enlazar WinUSB...' 'WARN'
      & $Zadig --vid 0x05C6 --pid 0x9008 --install 2>&1 | Out-Null
      $bound = Test-WinUsbBound
    } elseif (Test-Path $Zadig) {
      L 'Abriendo Zadig GUI: selecciona "Qualcomm HS-USB QDLoader 9008" -> WinUSB -> Install Driver' 'WARN'
      Start-Process $Zadig
      Start-Sleep -Seconds 12
      $bound = Test-WinUsbBound
    }
  } else { $bound = $true; L 'WinUSB ya vinculado' 'OK' }
  if (-not $bound) { L 'WinUSB NO vinculado tras intento de binding' 'ALERT'; continue }

  L 'Ejecutando printgpt (solo lectura)...' 'OK'
  $res = & $Py $PyArgs $Edl printgpt --debugmode 2>&1 | Out-String
  $res | Add-Content -Path $out -Encoding UTF8
  if ($res -match 'NotImplementedError|Operation not supported') {
    L 'Sin acceso raw USB. Reintentando en la siguiente ventana EDL.' 'WARN'
    continue
  }
  if ($res -match 'GPT|Partition|firehose|Sahara') {
    L '>>> EXITO: Sahara/Firehose responde. Tabla de particiones obtenida. <<<' 'ALERT'
    L "Siguiente paso SEGURO (solo lectura): py -3.12 edl.py rf C:\UFI-Recovery\Backup\emmc-full.img" 'OK'
    L ("Salida: {0}" -f $out) 'OK'
    exit 0
  }
  L 'Salida sin datos utiles; ver fichero.' 'WARN'
}
L ("NO se logro acceso en {0} intentos. Revisar {1}" -f $Attempts,$out) 'ALERT'
exit 3
