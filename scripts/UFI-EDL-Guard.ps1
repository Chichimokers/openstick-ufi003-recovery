#Requires -Version 5.1
<#
  UFI-EDL-Guard.ps1 -- GUARDIA EDL automatico (el usuario SOLO enchufa/desenchufa).

  1) Vigila el bus USB cada 0,5 s.
  2) Si aparece el EDL 9008 (VID_05C6&PID_9008) -> lanza edl.py por USB (WinUSB)
     con el loader rotativo. edl espera al dispositivo y conecta solo.
  3) Si sale con tabla de particiones -> GUARDA el GPT y lanza BACKUP (solo lectura).
  4) Si el loader es rechazado -> siguiente loader. Repite indefinidamente.

  Uso:  pwsh -File .\UFI-EDL-Guard.ps1 -Hours 6
#>
[CmdletBinding()]
param(
  [double]$Hours = 6,
  [int]$PerAttemptSec = 110,
  [string]$LoadersDir = 'C:\UFI-Recovery\Tools\edl\Loaders\manual',
  [string]$Edl = 'C:\UFI-Recovery\Tools\edl\edl.py',
  [string]$WorkDir = 'C:\UFI-Recovery\Work',
  [string]$LogDir = 'C:\UFI-Recovery\Diagnostico\Reports',
  [string]$BackupDir = 'C:\UFI-Recovery\Backup'
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $LogDir,$BackupDir,$WorkDir,"$WorkDir\logs" | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $LogDir "edl-guard-$stamp.txt"

function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $m
  Add-Content -Path $logFile -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

$loaders = Get-ChildItem $LoadersDir -File -EA SilentlyContinue | Where-Object { $_.Extension -in '.mbn','.bin' -and $_.Name -like '*gucci*' } | Sort-Object Name
if (-not $loaders) { $loaders = Get-ChildItem $LoadersDir -File -EA SilentlyContinue | Where-Object { $_.Extension -in '.mbn','.bin' } | Sort-Object Name }
if (-not $loaders) { L "SIN LOADERS en $LoadersDir" 'ALERT'; exit 1 }

L ("GUARDIA EDL iniciado - {0} loaders - el usuario solo enchufa/desenchufa" -f $loaders.Count) 'ALERT'
L "Informe: $logFile" 'INFO'

function Get-EdlPresent {
  [bool](Get-CimInstance Win32_PnPEntity -Property DeviceID -EA SilentlyContinue |
    Where-Object { $_.DeviceID -match 'VID_05C6&PID_9008' })
}
function Get-NormalPresent {
  [bool](Get-CimInstance Win32_PnPEntity -Property DeviceID -EA SilentlyContinue |
    Where-Object { $_.DeviceID -match 'VID_18D1&PID_D001' })
}

$rnd = 0
$deadline = (Get-Date).AddHours($Hours)
$logContent = ''

while ((Get-Date) -lt $deadline) {
  if (Get-EdlPresent) {
    $loader = $loaders[$rnd % $loaders.Count].FullName; $rnd++
    L "EDL 9008 EN EL BUS -> leyendo GPT (sectores 1-34) con $(Split-Path $loader -Leaf)" 'ALERT'
    $gdir = Join-Path $BackupDir 'gpt'
    New-Item -ItemType Directory -Force -Path $gdir | Out-Null
    $gfile = Join-Path $gdir 'gpt-sectors-1-34.bin'
    Remove-Item $gfile -Force -EA SilentlyContinue
    $psi = @{
      FilePath='py'; ArgumentList=@('-3.12',$Edl,'rs','1','34',$gfile,'--vid','0x05C6','--pid','0x9008',
        '--memory','emmc','--sectorsize','512','--loader',$loader,'--debugmode','--skipresponse')
      WorkingDirectory=$WorkDir; NoNewWindow=$true; Wait=$true
      RedirectStandardOutput="$env:TEMP\edl-rs.txt"; RedirectStandardError="$env:TEMP\edl-rse.txt"
    }
    Start-Process @psi | Out-Null
    $out = (Get-Content "$env:TEMP\edl-rs.txt" -Raw -EA SilentlyContinue) + (Get-Content "$env:TEMP\edl-rse.txt" -Raw -EA SilentlyContinue)
    Add-Content -Path $logFile -Value $out -Encoding UTF8
    if ((Test-Path $gfile) -and (Get-Item $gfile).Length -ge 34816) {
      L ">>> EXITO: GPT COMPLETO CAPTURADO ($([math]::Round((Get-Item $gfile).Length/1KB,1)) KB) <<<" 'ALERT'
      L "Fichero: $gfile" 'OK'
      L "MISION CUMPLIDA - informe: $logFile" 'OK'
      exit 0
    }
    L "GPT incompleto (ventana cerrada). Reintento en 3 s." 'WARN'
    Start-Sleep -Seconds 3
    continue
  }
  if (Get-NormalPresent) {
    L "Modem en modo normal (sistema arrancado). Esperando ventana EDL..." 'INFO'
    Start-Sleep -Seconds 3
    continue
  }
  Start-Sleep -Milliseconds 500
}
L "Guardia finalizado por tiempo. Informe: $logFile" 'OK'
