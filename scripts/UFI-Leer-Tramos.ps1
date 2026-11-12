#Requires -Version 5.1
<#
  UFI-Leer-Tramos.ps1 -- Lectura por tramos con LA RECETA EXACTA (SIN --loader).

  Receta (documentada en AGENTS.md, comprobada):
    py -3.12 edl.py rs <start> <count> <fichero> --vid 0x05C6 --pid 0x9008
        --memory emmc --sectorsize 512 --debugmode --skipresponse
    (SIN --loader: edl auto-selecciona 007050e100000000_278448179ac756a1_fhprg_peek.bin)

  El dispositivo entrega hasta ~114 KB por sesion -> tramos de 200 sectores (100 KB).

  Uso:  pwsh -File .\UFI-Leer-Tramos.ps1 -Start 262144 -Sectors 4104 -Out bootloader-chain.bin
#>
[CmdletBinding()]
param(
  [int]$Start = 262144,
  [int]$Sectors = 4104,
  [string]$Out = 'bootloader-chain.bin',
  [int]$ChunkSectors = 200,      # ~100 KB por sesion (completa bien)
  [int]$ChunkTimeoutSec = 400
)
$ErrorActionPreference = 'Continue'
$dir = 'C:\UFI-Recovery\Backup\particiones'
New-Item -ItemType Directory -Force -Path $dir, 'C:\UFI-Recovery\Work\logs' | Out-Null
$file = Join-Path $dir $Out
$log = 'C:\UFI-Recovery\Diagnostico\Reports\lectura-tramos.txt'

function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $m
  Add-Content -Path $log -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

$total = $Sectors * 512
L ("LECTURA POR TRAMOS: sector {0} + {1} ({2} KB) -> {3} | tramos de {4} sectores" -f $Start, $Sectors, [math]::Round($total/1KB,0), $file, $ChunkSectors) 'ALERT'
L "RECETA: SIN --loader (auto-seleccion). Requiere EDL fresco (boton al conectar)." 'ALERT'

$done = 0
$n = 0
while ($done -lt $Sectors) {
  $n++
  $count = [Math]::Min($ChunkSectors, $Sectors - $done)
  $start = $Start + $done
  $u = Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_05C6' }
  if (-not $u) { L "TRAMO $n OMITIDO - el modem salio de EDL. Reconecta (boton) y relanza." 'ALERT'; break }

  L ("TRAMO {0}: sector {1} +{2} ({3} KB)" -f $n, $start, $count, [math]::Round($count*512/1KB,0)) 'INFO'
  $o = "$env:TEMP\tramo-$n.txt"
  $psi = @{
    FilePath='py'; ArgumentList=@('-3.12','C:\UFI-Recovery\Tools\edl\edl.py','rs',"$start","$count",$file,
      '--vid','0x05C6','--pid','0x9008','--memory','emmc','--sectorsize','512','--debugmode','--skipresponse')
    WorkingDirectory='C:\UFI-Recovery\Work'; NoNewWindow=$true; Wait=$true
    RedirectStandardOutput=$o; RedirectStandardError="$env:TEMP\tramo-$n-err.txt"
  }
  $expect = $count * 512
  $before = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
  Remove-Item $file -Force -EA SilentlyContinue   # cada tramo escribe el fichero completo desde 0
  Start-Process @psi | Out-Null
  $got = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
  if ($got -ge $expect) {
    L ("TRAMO {0} COMPLETO ({1} bytes) -> renombrando y continuando" -f $n, $got) 'OK'
    Rename-Item $file "$Out.tramo$($start.ToString('D8'))" -Force
    $done += $count
  } else {
    L ("TRAMO {0} PARCIAL ({1}/{2} bytes) -Guardado como tramo parcial" -f $n, $got, $expect) 'WARN'
    if ($got -gt 0) { Rename-Item $file "$Out.tramo$($start.ToString('D8')).parcial" -Force }
    $done += $count   # continuar con el siguiente tramo de todas formas
  }
  Start-Sleep -Seconds 2
}

L ("LECTURA TERMINADA: {0}/{1} sectores. Ficheros en {2}" -f $done, $Sectors, $dir) 'ALERT'
L "Une los tramos con:  Get-ChildItem '$Out.tramo*' | Sort-Object Name | ForEach-Object { [IO.File]::AppendAllBytes('$Out',[IO.File]::ReadAllBytes($_.FullName)) }" 'OK'
