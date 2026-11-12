#Requires -Version 5.1
<#
  UFI-Backup-ADB.ps1 -- Respalda las particiones criticas del modem via ADB.
  Ahora que el sistema arranca, ADB da acceso root completo y fiable.

  Mapa (GPT real del dispositivo -> mmcblk0pN):
    cdt->p2? no: N = indice GPT + 1
    sbl1(1)->p3  rpm(2)->p4  tz(3)->p5  hyp(4)->p6  sec(5)->p7
    modemst1(6)->p8  modemst2(7)->p9  fsc(8)->p10  fsg(9)->p11
    aboot(10)->p12  boot(11)->p13  devinfo(12)->p14  rootfs(13)->p15
  (rootfs confirmado: /dev/mmcblk0p14 -> indice 13)

  Uso: pwsh -File .\UFI-Backup-ADB.ps1
#>
[CmdletBinding()]
param(
  [string]$Adb = 'D:\Programas\scrcpy-win64-v3.2\scrcpy-win64-v3.2\adb.exe',
  [string]$Destino = 'C:\UFI-Recovery\Backup\adb'
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $Destino | Out-Null
$log = 'C:\UFI-Recovery\Diagnostico\Reports\backup-adb.txt'

function L([string]$m,[string]$Level='INFO') {
  $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $m
  Add-Content -Path $log -Value $line -Encoding UTF8
  $c = switch ($Level) { 'ALERT'{'Red'} 'WARN'{'Yellow'} 'OK'{'Green'} default {'Gray'} }
  Write-Host $line -ForegroundColor $c
}

$dev = (& $Adb devices 2>&1 | Out-String)
if ($dev -notmatch 'device$' -and $dev -notmatch "\sdevice\s") { L "ADB no ve ningun dispositivo. Conecta el modem normalmente." 'ALERT'; exit 1 }
L "ADB conectado ✔" 'OK'
L "Sistema: " + ((& $Adb shell 'cat /etc/os-release | grep PRETTY' 2>&1)) 'INFO'

# nombre logico -> numero de particion mmcblk0pN (indice GPT + 1)
$map = [ordered]@{
  'modemst1' = 8    # 2 MB   IMEI/calibracion
  'modemst2' = 9    # 2 MB   IMEI/calibracion
  'fsg'      = 11   # 2 MB   modem filesystem
  'fsc'      = 10   # 1 KB   modem FS cookie
  'sec'      = 7    # 16 KB  secure storage
  'cdt'      = 2    # 2 KB   config data
  'sbl1'     = 3    # 512 KB bootloader
  'rpm'      = 4    # 512 KB
  'tz'       = 5    # 1 MB
  'hyp'      = 6    # 512 KB
  'aboot'    = 12   # 1 MB   bootloader (LK)
  'boot'     = 13   # 64 MB  kernel+ramdisk
}
$ok = 0; $fail = 0
foreach ($name in $map.Keys) {
  $p = $map[$name]
  $src = "/dev/block/mmcblk0p$p"
  $tmp = "/sdcard/ufi-backup-$name.img"
  $dst = Join-Path $Destino "$name.img"
  if ((Test-Path $dst) -and (Get-Item $dst).Length -gt 0) { L "  $name ya respaldada ($((Get-Item $dst).Length) bytes)" 'OK'; $ok++; continue }

  L "  $name <- $src ..." 'INFO'
  $sz = (& $Adb shell "blockdev --getsize64 $src 2>/dev/null" 2>&1)
  $r = & $Adb shell "dd if=$src of=$tmp bs=1M 2>/dev/null; ls -l $tmp 2>/dev/null" 2>&1
  if ($r -match 'No such file|not found') {
    L "  $name FALLO (particion no accesible: $src)" 'WARN'
    L "     salida: $($r -join ' ')" 'WARN'
    $fail++
    continue
  }
  & $Adb pull $tmp $dst 2>&1 | Out-Null
  & $Adb shell "rm -f $tmp" 2>&1 | Out-Null
  if (Test-Path $dst) {
    $len = (Get-Item $dst).Length
    $h = (Get-FileHash $dst -Algorithm SHA256).Hash
    L ("  {0} OK: {1} bytes (esperados {2})  SHA256={3}" -f $name, $len, $sz, $h.Substring(0,16)) 'OK'
    Add-Content -Path $log -Value ("    sha256 $name $h") -Encoding UTF8
    if ("$len" -ne "$sz".Trim()) { L "     AVISO: el tamano no coincide exactamente" 'WARN' }
    $ok++
  } else { L "  $name FALLO al extraer" 'WARN'; $fail++ }
}

L "BACKUP ADB TERMINADO: $ok OK, $fail fallos. Destino: $Destino" 'ALERT'
L "Ficheros en $Destino con SHA256 en $log" 'INFO'
