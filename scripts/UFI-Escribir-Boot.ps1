#Requires -Version 5.1
<#
  UFI-Escribir-Boot.ps1 -- Escribe la imagen boot de OpenStick (UFI001C) en la
  particion boot del dispositivo, por EDL. Precisa confirmacion del usuario.

  NO toca: GPT, modemst1, modemst2, fsg, fsc, sbl1, aboot, tz, hyp, rpm.

  Uso:  pwsh -File .\UFI-Escribir-Boot.ps1 -Confirmar
#>
[CmdletBinding()]
param(
  [switch]$Confirmar,                       # obligatorio para ejecutar
  [int]$Sector = 526336,                    # inicio de 'boot' (GPT real del dispositivo)
  [string]$Imagen = 'C:\UFI-Recovery\Firmware\boot-ufi001c.img',
  [int]$TimeoutSec = 1800
)
$ErrorActionPreference = 'Continue'
$log = 'C:\UFI-Recovery\Diagnostico\Reports\escritura-boot.txt'

function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $m
  Add-Content -Path $log -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

if (-not $Confirmar) { L "FALTA -Confirmar. Operacion abortada por seguridad." 'ALERT'; exit 1 }

L "=== ESCRITURA DE BOOT (OpenStick UFI001C) ===" 'ALERT'
L "Imagen : $Imagen ($([math]::Round((Get-Item $Imagen).Length/1MB,1)) MB, SHA256 $((Get-FileHash $Imagen -Algorithm SHA256).Hash))" 'INFO'
L "Destino: sector $Sector (particion boot, 64 MB)" 'INFO'
L "Intocado: GPT, modemst1/2, fsg, fsc, sbl1, aboot, tz, hyp, rpm" 'INFO'

$u = Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_05C6' }
if (-not $u) { L "El modem no esta en EDL. Conectalo manteniendo el boton y relanza." 'ALERT'; exit 2 }

$tmp = "$env:TEMP\edl-write-boot.txt"
$psi = @{
  FilePath='py'
  ArgumentList=@('-3.12','C:\UFI-Recovery\Tools\edl\edl.py','ws',"$Sector",$Imagen,
    '--vid','0x05C6','--pid','0x9008','--memory','emmc','--sectorsize','512','--debugmode')
  WorkingDirectory='C:\UFI-Recovery\Work'; NoNewWindow=$true; Wait=$true
  RedirectStandardOutput=$tmp; RedirectStandardError="$env:TEMP\edl-write-boot-err.txt"
}
$env:PYTHONIOENCODING = 'utf-8'   # FIX: la barra de progreso usa █ (u2588) y cp1252 falla
L "Ejecutando edl ws ... (puede tardar varios minutos)" 'ALERT'
Start-Process @psi | Out-Null
$env:PYTHONIOENCODING = $null
$out = (Get-Content $tmp -Raw -EA SilentlyContinue) + (Get-Content "$env:TEMP\edl-write-boot-err.txt" -Raw -EA SilentlyContinue)
Add-Content -Path $log -Value $out -Encoding UTF8

# Comprobacion: releer los primeros 8 sectores y verificar la firma ANDROID!
Start-Sleep -Seconds 3
$chk = 'C:\UFI-Recovery\Backup\particiones\boot-verificacion.bin'
Remove-Item $chk -Force -EA SilentlyContinue
$psi2 = @{
  FilePath='py'
  ArgumentList=@('-3.12','C:\UFI-Recovery\Tools\edl\edl.py','rs',"$Sector",'8',$chk,
    '--vid','0x05C6','--pid','0x9008','--memory','emmc','--sectorsize','512','--skipresponse','--debugmode')
  WorkingDirectory='C:\UFI-Recovery\Work'; NoNewWindow=$true; Wait=$true
  RedirectStandardOutput="$env:TEMP\edl-verify.txt"; RedirectStandardError="$env:TEMP\edl-verify-err.txt"
}
Start-Process @psi2 | Out-Null
if (Test-Path $chk) {
  $b = [IO.File]::ReadAllBytes($chk)
  if ($b.Length -ge 8 -and [Text.Encoding]::ASCII.GetString($b[0..7]) -eq 'ANDROID!') {
    L ">>> ESCRITURA VERIFICADA: la particion boot empieza por 'ANDROID!' <<<" 'ALERT'
    L "Reinicia el modem (desenchufar y enchufar SIN boton) y comprueba si aparece la interfaz RNDIS/USB de Debian." 'OK'
  } else {
    L ("Verificacion: la cabecera no es ANDROID! (%s)" -f (($b[0..7] | ForEach-Object { $_.ToString('X2') }) -join ' ')) 'WARN'
  }
} else { L "No se pudo verificar (ventana EDL cerrada)." 'WARN' }

if ($out -match 'error|Error|failed|Failed|not support') {
  L "POSIBLE FALLO EN LA ESCRITURA - revisa el informe completo: $log" 'WARN'
} else {
  L "Escritura completada. Informe: $log" 'OK'
}
