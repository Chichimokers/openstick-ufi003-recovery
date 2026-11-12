#Requires -Version 5.1
<#
  UFI-USB-Monitor.ps1  --  Fase 2: monitor Plug and Play / USB para modem 4G-UFI (Qualcomm MSM891x).

  Vigila continuamente los dispositivos PnP presentes y detecta:
    - aparicion / desaparicion de dispositivos
    - cambios de estado y codigos de problema
    - interfaces Qualcomm de interes: VID_05C6&PID_9008 (EDL), QHSUSB_BULK / QUSB_BULK,
      Qualcomm HS-USB QDLoader 9008, Qualcomm Diagnostics, ADB, Fastboot, desconocidos
  Registro: TXT (log legible) + CSV (eventos) + volcado completo de propiedades por alerta.

  NO INSTALA CONTROLADORES NI PROGRAMAS. Solo lectura (Get-PnpDevice / Get-CimInstance).

  Ejemplos:
    pwsh -File .\UFI-USB-Monitor.ps1                         # hasta Ctrl+C
    pwsh -File .\UFI-USB-Monitor.ps1 -DurationSec 900        # 15 minutos
    pwsh -File .\UFI-USB-Monitor.ps1 -DurationSec 900 -ProbeAdbFastboot
#>
[CmdletBinding()]
param(
  [int]$PollIntervalMs = 500,
  [int]$DurationSec = 0,
  [string]$BaselineCsv = 'C:\UFI-Recovery\Diagnostico\Baseline\pnp-baseline.csv',
  [string]$LogDir = 'C:\UFI-Recovery\Diagnostico\Logs',
  [string]$ReportDir = 'C:\UFI-Recovery\Diagnostico\Reports',
  [switch]$ProbeAdbFastboot
)

$ErrorActionPreference = 'Continue'
$stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile     = Join-Path $LogDir    ("usb-monitor-{0}.log"   -f $stamp)
$csvFile     = Join-Path $LogDir    ("eventos-{0}.csv"       -f $stamp)
$alertFile   = Join-Path $LogDir    ("ALERTAS-{0}.txt"       -f $stamp)
$reportFile  = Join-Path $ReportDir ("informe-monitor-{0}.txt" -f $stamp)
$fullSnapCsv = Join-Path $ReportDir ("snapshot-full-{0}.csv" -f $stamp)
New-Item -ItemType Directory -Force -Path $LogDir, $ReportDir | Out-Null

# ----------------------------------------------------------------------------
# Reglas de interes
# ----------------------------------------------------------------------------
$script:Rules = @(
  @{ Name='EDL_9008';     Pattern='VID_05C6&PID_9008|PID_9008';            Severity='ALERT'; Meaning='Qualcomm EDL 9008: el SoC QUALCOMM RESPONDE (Sahara/Firehose accesible por USB)' }
  @{ Name='QUSB_BULK';    Pattern='QHSUSB_BULK|QUSB_BULK';                 Severity='ALERT'; Meaning='Interfaz Sahara/Emergency presente (driver Qualcomm cargado)' }
  @{ Name='QDLOADER';     Pattern='QDLoader|Qualcomm HS-USB';              Severity='ALERT'; Meaning='Dispositivo detectado por driver Qualcomm HS-USB QDLoader 9008' }
  @{ Name='QUALCOMM_PID'; Pattern='VID_05C6&PID_900[67EF]';                Severity='WARN';   Meaning='Otro PID Qualcomm de descarga/diagnostico' }
  @{ Name='QUALCOMM_VID'; Pattern='VID_05C6';                              Severity='WARN';   Meaning='Cualquier dispositivo con VID Qualcomm (05C6)' }
  @{ Name='FASTBOOT';     Pattern='VID_18D1&PID_D00F|fastboot';            Severity='WARN';   Meaning='Interfaz Fastboot (bootloader respondiendo)' }
  @{ Name='ADB';          Pattern='VID_18D1|Android ADB|ADB Interface';    Severity='WARN';   Meaning='Interfaz ADB (sistema operativo arrancado: Debian/Android usable)' }
  @{ Name='UNKNOWN';      Pattern='^Unknown Device|^Dispositivo desconocido'; Severity='WARN'; Meaning='Dispositivo desconocido: falta controlador o fallo de hardware/firmware' }
)

$script:Alerts = New-Object System.Collections.ArrayList
$script:Counts = @{ New=0; Removed=0; Changed=0; Alerts=0 }
$script:State  = @{}

# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------
function Write-Log {
  param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','OK','WARN','ALERT','EVENT')][string]$Level='INFO')
  $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
  Add-Content -Path $logFile -Value $line -Encoding UTF8
  $color = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $color
}

function Get-ProblemText([int]$Code) {
  switch ($Code) {
    0  { 'OK (sin problema)' }
    1  { 'Code 1: no configurado correctamente' }
    3  { 'Code 3: controlador danado o memoria insuficiente' }
    10 { 'Code 10: el dispositivo no puede iniciar' }
    12 { 'Code 12: recursos insuficientes (USB/energia)' }
    28 { 'Code 28: controladores no instalados' }
    31 { 'Code 31: depende de otro dispositivo que no responde' }
    43 { 'Code 43: hardware detenido por Windows' }
    45 { 'Code 45: no conectado' }
    48 { 'Code 48: bloqueado por filtro de driver' }
    default { "Code $Code" }
  }
}

function Get-VidPid([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $m = [regex]::Match($Text, 'VID_([0-9A-Fa-f]{4})[^0-9A-Fa-f]*PID_([0-9A-Fa-f]{4})')
  if ($m.Success) { return [pscustomobject]@{ Vid=$m.Groups[1].Value.ToUpper(); Pid=$m.Groups[2].Value.ToUpper() } }
  return $null
}

function Get-DeviceTable {
  # Snapshot rapido: UNA sola consulta CIM trae DeviceID, Name, PNPClass,
  # HardwareID, Service, Status y ConfigManagerErrorCode. Los VID/PID van
  # incluidos en DeviceID y HardwareID (p.ej. USB\VID_05C6&PID_9008&MI_00\...).
  $rows = Get-CimInstance Win32_PnPEntity -Property Name,DeviceID,HardwareID,Status,ConfigManagerErrorCode,Service,PNPClass -ErrorAction SilentlyContinue
  $table = @{}
  foreach ($d in $rows) {
    if (-not $d) { continue }
    $hwids = @($d.HardwareID) -join ' ; '
    $candidate = ($d.DeviceID -like 'USB\*') -or ($hwids -match 'VID_') -or
      ($d.PNPClass -in 'USB','PORTS','Modem','Net','Bluetooth','HIDClass','Android','MEDIA','Unknown','USBDevice') -or
      ("$($d.Name)" -match 'Qualcomm|Sahara|Firehose|QDLoader|QUSB|QHSUSB|ADB|Fastboot|Android|desconocido|Unknown')
    $table[$d.DeviceID] = [pscustomobject]@{
      InstanceId=$d.DeviceID; FriendlyName=$d.Name; Class=$d.PNPClass
      Status=$d.Status; Problem=[int]$d.ConfigManagerErrorCode
      ProblemDescription=''; Present=$true
      Service=$d.Service; HardwareIds=$hwids; Candidate=$candidate
    }
  }
  return $table
}

function Get-Tags([pscustomobject]$Dev) {
  $hay = "{0} {1} {2} {3}" -f $Dev.HardwareIds, $Dev.InstanceId, $Dev.FriendlyName, $Dev.Class
  $tags = [System.Collections.ArrayList]@()
  foreach ($r in $script:Rules) { if ($hay -match $r.Pattern) { [void]$tags.Add($r.Name) } }
  return ($tags -join '|')
}

function Save-DeviceDump([string]$InstanceId, [string]$Reason) {
  $safe = ($InstanceId -replace '[\\/:*?"<>| ]','_')
  if ($safe.Length -gt 80) { $safe = $safe.Substring($safe.Length-80) }
  $file = Join-Path $LogDir ("dump-{0}-{1}.txt" -f $safe, (Get-Date -Format 'HHmmss'))
  try {
    $props = Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction SilentlyContinue
    $hdr = "VOLCADO COMPLETO DE PROPIEDADES`nInstancia : $InstanceId`nMotivo    : $Reason`nFecha     : $(Get-Date -Format o)`n"
    $hdr + "`n" + ($props | Select-Object KeyName,Type,Data | Format-List | Out-String) | Set-Content $file -Encoding UTF8
    return $file
  } catch { return $null }
}

function Add-EventRow([string]$EventType,[pscustomobject]$Dev,[string]$Tags,[string]$Extra='') {
  $vp = Get-VidPid -Text (($Dev.HardwareIds) + ' ' + $Dev.InstanceId)
  $row = [pscustomobject]@{
    Timestamp=(Get-Date -Format o); Event=$EventType; Class=$Dev.Class; FriendlyName=$Dev.FriendlyName
    InstanceId=$Dev.InstanceId; Status=$Dev.Status; ProblemCode=$Dev.Problem
    ProblemText=(Get-ProblemText $Dev.Problem); VID=$(if($vp){$vp.Vid}else{''}); PID=$(if($vp){$vp.Pid}else{''})
    Service=$Dev.Service; Tags=$Tags; Detail=$Extra; HardwareIds=$Dev.HardwareIds
  }
  $params = @{ Path=$csvFile; InputObject=$row; NoTypeInformation=$true; Encoding='UTF8' }
  if (Test-Path $csvFile) { $params['Append'] = $true }
  Export-Csv @params
}

function Register-Alert([string]$Tags,[pscustomobject]$Dev,[string]$Meaning) {
  $script:Counts.Alerts++
  [void]$script:Alerts.Add("$Tags -> $($Dev.FriendlyName) [$($Dev.InstanceId)] ($Meaning)")
  $txt = "[{0}] ALERTA {1}`n  FriendlyName : {2}`n  InstanceId   : {3}`n  Clase        : {4}`n  Estado       : {5} / {6}`n  HardwareIds  : {7}`n  Significado  : {8}`n" -f `
    (Get-Date -Format o), $Tags, $Dev.FriendlyName, $Dev.InstanceId, $Dev.Class, $Dev.Status, (Get-ProblemText $Dev.Problem), $Dev.HardwareIds, $Meaning
  Add-Content -Path $alertFile -Value $txt -Encoding UTF8

  if ($ProbeAdbFastboot) {
    if ($Tags -match 'ADB') {
      $out = (& $Adb devices -l 2>&1 | Out-String)
      Add-Content -Path $alertFile -Value ("`n--- adb devices -l ---`n{0}`n" -f $out) -Encoding UTF8
    }
    if ($Tags -match 'FASTBOOT') {
      $out = (& $Fastboot devices 2>&1 | Out-String)
      Add-Content -Path $alertFile -Value ("`n--- fastboot devices ---`n{0}`n" -f $out) -Encoding UTF8
    }
  }
}

$Adb = 'adb'; $Fastboot = 'fastboot'

# ----------------------------------------------------------------------------
# Comparacion de estados
# ----------------------------------------------------------------------------
function Compare-State([hashtable]$New) {
  foreach ($kv in $New.GetEnumerator()) {
    if (-not $script:State.ContainsKey($kv.Key)) {
      $dev = $kv.Value
      if (-not $dev.Candidate) { continue }   # ruido: tarjetas de red virtuales, buses, etc.
      $script:Counts.New++
      $tags = Get-Tags -Dev $dev
      Write-Log ("NUEVO    [{0}] {1} | {2} | {3}/{4} | TAGS={5}" -f $dev.Class, $dev.FriendlyName, $dev.InstanceId, $dev.Status, (Get-ProblemText $dev.Problem), $tags) 'EVENT'
      Add-EventRow -EventType 'NEW' -Dev $dev -Tags $tags
      if ($tags) {
        $meaning = ($script:Rules | Where-Object { $tags -split '\|' -contains $_.Name } | ForEach-Object Meaning) -join ' ; '
        Register-Alert -Tags $tags -Dev $dev -Meaning $meaning
        $sev = 'WARN'
        foreach ($t in ($tags -split '\|')) { $r = $script:Rules | Where-Object Name -eq $t; if ($r -and $r.Severity -eq 'ALERT') { $sev = 'ALERT' } }
        Write-Log ("INTERES  {0} :: {1}" -f $tags, $meaning) $sev
      }
      if ($dev.Candidate -and ($tags -or $dev.Class -in 'USB','Unknown','Ports','Modem')) {
        $f = Save-DeviceDump -InstanceId $dev.InstanceId -Reason ("NEW tags={0}" -f $tags)
        if ($f) { Write-Log ("VOLCADO  {0}" -f $f) 'INFO' }
      }
    }
  }
  foreach ($id in @($script:State.Keys)) {
    if (-not $New.ContainsKey($id)) {
      $dev = $script:State[$id]
      if (-not $dev.Candidate) { continue }
      $script:Counts.Removed++
      Write-Log ("REMOVIDO [{0}] {1} | {2}" -f $dev.Class, $dev.FriendlyName, $dev.InstanceId) 'EVENT'
      Add-EventRow -EventType 'REMOVED' -Dev $dev -Tags '' -Extra 'desaparicion durante la monitorizacion'
    }
  }
  foreach ($kv in $New.GetEnumerator()) {
    $old = $script:State[$kv.Key]
    if ($old -and ($old.Status -ne $kv.Value.Status -or $old.Problem -ne $kv.Value.Problem)) {
      $dev = $kv.Value
      if (-not $dev.Candidate) { continue }
      $script:Counts.Changed++
      Write-Log ("CAMBIO   [{0}] {1} | {2} :: {3}/{4} -> {5}/{6}" -f $dev.Class, $dev.FriendlyName, $dev.InstanceId, $old.Status, (Get-ProblemText $old.Problem), $dev.Status, (Get-ProblemText $dev.Problem)) 'EVENT'
      Add-EventRow -EventType 'CHANGED' -Dev $dev -Tags '' -Extra ("{0} -> {1}" -f (Get-ProblemText $old.Problem), (Get-ProblemText $dev.Problem))
    }
  }
  $script:State = $New
}

# ----------------------------------------------------------------------------
# Informe final
# ----------------------------------------------------------------------------
function Write-Report {
  $v = @()
  if ($script:Counts.Alerts -gt 0) {
    $v += 'VEREDICTO_PRIMARIO: SE DETECTO UNA INTERFAZ QUALCOMM/DE ARRANQUE.'
    $v += ($script:Alerts -join "`n")
    $v += 'ACCION: el modem responde a nivel USB -> pasar a Fase 3 (Sahara/Firehose o ADB/Fastboot).'
  } elseif ($script:Counts.New -gt 0) {
    $v += 'VEREDICTO: APARECIERON DISPOSITIVOS NUEVOS SIN ETIQUETAS DE INTERES.'
    $v += 'Revisar eventos-*.csv: si hay "Desconocido" con Code 28 -> falta driver; si Code 12 -> problema de energia.'
  } elseif ($script:Counts.Changed -gt 0) {
    $v += 'VEREDICTO: SOLO CAMBIOS DE ESTADO EN DISPOSITIVOS EXISTENTES.'
  } else {
    $v += 'VEREDICTO: AUSENCIA TOTAL DE DETECCION USB.'
    $v += 'Windows no registro NINGUN cambio en el bus PnP al conectar el modem.'
    $v += 'Hipotesis prioritaria: ALIMENTACION o HARDWARE (NO concluir "muerto": probar otros'
    $v += 'cables/puertos/hub alimentado, mantener pulsador de encendido 10-15 s, comprobar'
    $v += 'bateria interna y medir 5 V en el conector USB del modem).'
  }
  $lines = @()
  $lines += '==============================================================='
  $lines += ' INFORME MONITOR UFI 4G (Qualcomm MSM8915/MSM8916)'
  $lines += '==============================================================='
  $lines += ("Inicio      : {0}" -f $startTime)
  $lines += ("Fin         : {0}" -f (Get-Date -Format o))
  $lines += ("Intervalo   : {0} ms (sondeo adaptativo)" -f $PollIntervalMs)
  $lines += ("Nuevos      : {0}" -f $script:Counts.New)
  $lines += ("Removidos   : {0}" -f $script:Counts.Removed)
  $lines += ("Cambios     : {0}" -f $script:Counts.Changed)
  $lines += ("Alertas     : {0}" -f $script:Counts.Alerts)
  $lines += '---------------------------------------------------------------'
  $lines += $v
  $lines += '---------------------------------------------------------------'
  $lines += 'Ficheros generados:'
  $lines += "  Log     : $logFile"
  $lines += "  Eventos : $csvFile"
  $lines += "  Alertas : $alertFile (solo si hubo)"
  $lines += "  Snapshot: $fullSnapCsv"
  $lines | Set-Content -Path $reportFile -Encoding UTF8
  Write-Host ($lines -join "`n")
}

# ----------------------------------------------------------------------------
# Programa principal
# ----------------------------------------------------------------------------
$startTime = Get-Date -Format o
Write-Log "=== Monitor UFI iniciado $(Get-Date -Format o) | PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)) | Windows $([System.Environment]::OSVersion.Version) ===" 'OK'

$script:State = Get-DeviceTable
$script:State.Values | Export-Csv -Path $fullSnapCsv -NoTypeInformation -Encoding UTF8
Write-Log "Snapshot inicial: $($script:State.Count) dispositivos PnP presentes." 'OK'

if (Test-Path $BaselineCsv) {
  $base = @{}
  try { Import-Csv $BaselineCsv -ErrorAction SilentlyContinue | ForEach-Object { $base[$_.InstanceId] = $_ } } catch {}
  foreach ($id in @($base.Keys)) {
    if (-not $script:State.ContainsKey($id)) {
      $script:Counts.Removed++
      Write-Log "REMOVIDO (vs baseline Fase 1): $id" 'EVENT'
    }
  }
  foreach ($kv in $script:State.GetEnumerator()) {
    if (-not $base.ContainsKey($kv.Key) -and $kv.Value.Candidate) {
      $script:Counts.New++
      $tags = Get-Tags -Dev $kv.Value
      Write-Log ("NUEVO (vs baseline Fase 1): [{0}] {1} | {2} | TAGS={3}" -f $kv.Value.Class, $kv.Value.FriendlyName, $kv.Value.InstanceId, $tags) 'EVENT'
      Add-EventRow -EventType 'NEW-VS-BASELINE' -Dev $kv.Value -Tags $tags
    }
  }
} else {
  $script:State.Values | Export-Csv -Path $BaselineCsv -NoTypeInformation -Encoding UTF8
  Write-Log "Baseline no encontrado -> creado: $BaselineCsv" 'WARN'
}

if (-not (Test-Path $alertFile)) { New-Item -ItemType File -Path $alertFile -Force | Out-Null }
Write-Log "Monitorizando... (Ctrl+C para detener)" 'OK'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
  while ($true) {
    $pollStart = Get-Date
    $snap = Get-DeviceTable
    Compare-State -New $snap
    if ($DurationSec -gt 0 -and $sw.Elapsed.TotalSeconds -ge $DurationSec) { break }
    $elapsedMs = ((Get-Date) - $pollStart).TotalMilliseconds
    Start-Sleep -Milliseconds ([Math]::Max(50, [int]($PollIntervalMs - $elapsedMs)))
    if ($DurationSec -gt 0 -and $sw.Elapsed.TotalSeconds -ge $DurationSec) { break }
  }
} finally {
  Write-Report
  Write-Log "Fin de monitorizacion." 'OK'
}
