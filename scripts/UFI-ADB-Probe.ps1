#Requires -Version 5.1
<#
  UFI-ADB-Probe.ps1 -- Espera a que el modem aparezca como dispositivo ADB y lo interroga.
  Salida: Logs\adb-probe-<fecha>.txt  (y Logs\adb-getprop-<fecha>.txt)
  NO instala nada.
#>
[CmdletBinding()]
param(
  [int]$TimeoutSec = 600,
  [string]$Adb = 'D:\Programas\scrcpy-win64-v3.2\scrcpy-win64-v3.2\adb.exe'
)
$ErrorActionPreference = 'Continue'
$dir = 'C:\UFI-Recovery\Diagnostico\Logs'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir ("adb-probe-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function L([string]$m) { Add-Content -Path $out -Value ("[{0}] {1}" -f (Get-Date -Format o), $m) -Encoding UTF8; Write-Host $m }

if (-not (Test-Path $Adb)) { $c = Get-Command adb -ErrorAction SilentlyContinue; if ($c) { $Adb = $c.Source } else { L "FATAL: adb no encontrado"; exit 1 } }
L "ADB: $Adb"
& $Adb start-server 2>&1 | Out-Null

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$dev = $null
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
  $l = (& $Adb devices 2>&1 | Out-String)
  $line = ($l -split "`r?`n" | Where-Object { $_ -match '\s+device$' } | Select-Object -First 1)
  if ($line) { $dev = ($line -split '\s+')[0]; break }
  Start-Sleep -Milliseconds 800
}
if (-not $dev) { L "TIMEOUT: no aparecio ningun dispositivo ADB en $TimeoutSec s"; exit 2 }

L ("DISPOSITIVO ADB DETECTADO: {0}" -f $dev)
L ("--- adb devices -l ---`n" + (& $Adb devices -l 2>&1 | Out-String))

$cmds = @(
  @('identidad','id'),
  @('root?','id -u'),
  @('plataforma','getprop ro.board.platform'),
  @('hardware','getprop ro.hardware'),
  @('modelo','getprop ro.product.model'),
  @('fabricante','getprop ro.product.manufacturer'),
  @('android/debian','getprop ro.build.version.release'),
  @('fingerprint','getprop ro.build.fingerprint'),
  @('adbd','getprop init.svc.adbd'),
  @('usb functions','cat /sys/class/android_usb/android0/functions'),
  @('usb state','cat /sys/class/android_usb/android0/state'),
  @('cmdline','cat /proc/cmdline'),
  @('particiones','cat /proc/partitions'),
  @('bloques eMMC','ls -l /dev/block/by-name/ 2>/dev/null || ls -l /dev/block/platform/*/by-name/ 2>/dev/null'),
  @('rootfs','mount | head -20'),
  @('uptime','uptime')
)
foreach ($c in $cmds) {
  $r = (& $Adb -s $dev shell $c[1] 2>&1 | Out-String).Trim()
  L ("shell {0} => {1}" -f $c[0], ($r -replace "`r?`n", ' | '))
}

$gp = Join-Path $dir ("adb-getprop-{0}.txt" -f (Get-Date -Format 'HHmmss'))
& $Adb -s $dev shell getprop 2>&1 | Out-File $gp -Encoding UTF8
L ("getprop completo: {0}" -f $gp)
L ('NOTA: si getprop devuelve vacio, el dispositivo NO es Android (p.ej. Debian con busybox): probar "adb shell uname -a" y "adb shell cat /etc/os-release".')
