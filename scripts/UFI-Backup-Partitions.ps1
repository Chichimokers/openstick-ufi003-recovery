#Requires -Version 5.1
<#
  UFI-Backup-Partitions.ps1 -- Vuelca secuencialmente las particiones del UFI por EDL.
  Tabla obtenida de la GPT REAL del dispositivo (ver INFORME_FINAL.md).

  Uso: pwsh -File .\UFI-Backup-Partitions.ps1 [-IncludeBoot] [-IncludeRootfs]
#>
[CmdletBinding()]
param(
  [switch]$IncludeBoot,      # boot = 64 MB (~1 h)
  [switch]$IncludeRootfs,    # rootfs = 3,33 GB (muy largo)
  [int]$SectorTimeoutSec = 900
)
$ErrorActionPreference = 'Continue'
$outDir = 'C:\UFI-Recovery\Backup\particiones'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$log = 'C:\UFI-Recovery\Diagnostico\Reports\backup-particiones.txt'

function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $m
  Add-Content -Path $log -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

# nombre, inicio (LBA), sectores, bytes esperados
$parts = @(
  @('cdt',       131072,     4,      2048),
  @('sbl1',      262144,  1024,    524288),
  @('rpm',       263168,  1024,    524288),
  @('tz',        264192,  2048,   1048576),
  @('hyp',       266240,  1024,    524288),
  @('sec',       267264,    32,     16384),
  @('modemst1',  267296,  4096,   2097152),
  @('modemst2',  271392,  4096,   2097152),
  @('fsc',       275488,     2,      1024),
  @('fsg',       393216,  4096,   2097152),
  @('aboot',     524288,  2048,   1048576),
  @('devinfo',   657408,  2048,   1048576)
)
if ($IncludeBoot)   { $parts += @('boot',      526336, 131072, 67108864) }
if ($IncludeRootfs) { $parts += @('rootfs',    659456,6975455,3573432320) }

L "BACKUP DE PARTICIONES iniciado - $($parts.Count) objetivos" 'ALERT'
L "El modem debe estar en EDL (QHSUSB__BULK)" 'ALERT'

$ok = 0; $fail = 0
foreach ($p in $parts) {
  $name = $p[0]; $start = $p[1]; $sectors = $p[2]; $expected = $p[3]
  $file = Join-Path $outDir "$name.img"

  if ((Test-Path $file) -and (Get-Item $file).Length -eq $expected) {
    L "  $name YA COMPLETA ($expected bytes)" 'OK'; $ok++; continue
  }
  Remove-Item $file -Force -EA SilentlyContinue

  $u = Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_05C6' }
  if (-not $u) { L "  $name OMITIDA - el modem salio de EDL. Reconecta y relanza." 'ALERT'; break }

  L "  $name : leyendo sectores $start +$sectors ($([math]::Round($expected/1KB,0)) KB)..." 'INFO'
  $o = "$env:TEMP\bk-$name.txt"
  $psi = @{
    FilePath='py'; ArgumentList=@('-3.12','C:\UFI-Recovery\Tools\edl\edl.py','rs',"$start","$sectors",$file,
      '--vid','0x05C6','--pid','0x9008','--memory','emmc','--sectorsize','512','--debugmode','--skipresponse')
    WorkingDirectory='C:\UFI-Recovery\Work'; NoNewWindow=$true; Wait=$true
    RedirectStandardOutput=$o; RedirectStandardError="$env:TEMP\bk-$name-err.txt"
  }
  Start-Process @psi | Out-Null
  $got = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
  if ($got -eq $expected) {
    $h = (Get-FileHash $file -Algorithm SHA256).Hash
    L "  $name COMPLETA ($got bytes) SHA256=$h" 'OK'; $ok++
    Add-Content -Path $log -Value ("    sha256 $name $h") -Encoding UTF8
  } else {
    L "  $name INCOMPLETA ($got / $expected bytes)" 'WARN'; $fail++
    Add-Content -Path $log -Value ((Get-Content $o -EA SilentlyContinue | Select-Object -Last 6) -join "`n") -Encoding UTF8
  }
  Start-Sleep -Seconds 2
}

L "BACKUP TERMINADO: $ok completas, $fail incompletas. Informe: $log" 'ALERT'
