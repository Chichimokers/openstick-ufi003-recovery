#Requires -Version 5.1
<#
  UFI-LiveView2.ps1 -- Ventana con el log de la ESCRITURA en vivo.
#>
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\UFI-Recovery\Diagnostico\Reports\escritura-boot3.txt'
$Host.UI.RawUI.WindowTitle = 'UFI 4G - ESCRITURA DE BOOT EN VIVO'
while ($true) {
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  UFI 4G - ESCRITURA DE BOOT   |   $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    $d = Get-CimInstance Win32_PnPEntity -Property DeviceID | Where-Object { $_.DeviceID -match 'VID_05C6' }
    if ($d) { Write-Host "  DISPOSITIVO: EDL 9008 conectado" -ForegroundColor Green } else { Write-Host "  DISPOSITIVO: (fuera de EDL)" -ForegroundColor DarkGray }
    $py = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'edl\.py' }
    if ($py) { Write-Host "  PROCESO EDL: ACTIVO" -ForegroundColor Green } else { Write-Host "  PROCESO EDL: terminado" -ForegroundColor Yellow }
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    if (Test-Path $log) {
        # Filtrar solo lineas utiles pero quedarse con las ultimas
        $lineas = Get-Content $log -Tail 400 | Where-Object { $_ -match 'Write \(|firehose -|main -|Error|error|Mode|Loader|Success|100' }
        $lineas | Select-Object -Last 18 | ForEach-Object {
            $t = ($_ -replace "`e\[[0-9;]*m","").Trim()
            $c = 'Gray'
            if ($t -match 'Write \(') { $c = 'Cyan' }
            elseif ($t -match '100.0%') { $c = 'Green' }
            elseif ($t -match 'Error|error') { $c = 'Red' }
            Write-Host ($t.Substring(0, [Math]::Min(110, $t.Length))) -ForegroundColor $c
        }
        $ult = (Get-Content $log -Tail 400 | Where-Object { $_ -match 'Write \(' } | Select-Object -Last 1)
        if ($ult -match '([\d.]+)%') { Write-Host "  >>> PROGRESO: $($Matches[1]) %" -ForegroundColor Yellow }
    } else { Write-Host "(esperando log...)" -ForegroundColor DarkGray }
    Start-Sleep -Seconds 4
}
