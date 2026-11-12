# UFI-LiveView.ps1 -- Ventana de visualizacion en vivo del cazador EDL.
# Muestra: hora, si hay dispositivo Qualcomm en el bus, y las ultimas lineas del log.
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\UFI-Recovery\Diagnostico\Reports\edl-guard-rs.txt'
$title = 'UFI 4G - CAZADOR EDL EN VIVO'
$Host.UI.RawUI.WindowTitle = $title
while ($true) {
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  UFI 4G - CAZADOR EDL EN VIVO   |   $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    $d = Get-CimInstance Win32_PnPEntity -Property Name,DeviceID,Status | Where-Object { $_.DeviceID -match 'VID_05C6|VID_18D1' }
    if ($d) {
        Write-Host ("  DISPOSITIVO EN BUS : {0}  [{1}]" -f $d[0].Name, $d[0].Status) -ForegroundColor Green
    } else {
        Write-Host "  DISPOSITIVO EN BUS : (ninguno) - conecta el modem" -ForegroundColor DarkGray
    }
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    if (Test-Path $log) {
        Get-Content $log -Tail 20 | ForEach-Object {
            $c = 'Gray'
            if ($_ -match 'ALERT') { $c = 'Red' }
            elseif ($_ -match 'WARN') { $c = 'Yellow' }
            elseif ($_ -match 'OK') { $c = 'Green' }
            elseif ($_ -match 'INFO') { $c = 'White' }
            Write-Host $_ -ForegroundColor $c
        }
    } else {
        Write-Host "(esperando log...)" -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds 5
}
