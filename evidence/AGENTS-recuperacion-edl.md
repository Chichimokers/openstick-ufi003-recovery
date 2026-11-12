# AGENTS.md — Recuperación módem UFI 4G (Qualcomm MSM8916)

> **Instrucciones permanentes para cualquier agente que trabaje en este proyecto.**
> Proyecto: `C:\UFI-Recovery` · Dispositivo: módem USB 4G-UFI, SoC **MSM8916** (`6VV`), marcados placa `CN89FX`, `K051900`.

---

## 1. ⚠️ RECETA DE LECTURA (USAR SIEMPRE ESTA FORMA)

**La que FUNCIONÓ (comprobada):**

```powershell
py -3.12 C:\UFI-Recovery\Tools\edl\edl.py rs <start_sector> <num_sectors> <fichero> `
  --vid 0x05C6 --pid 0x9008 --memory emmc --sectorsize 512 --debugmode --skipresponse
```

### 🔑 REGLA DE ORO: **NO poner `--loader`**

- Sin `--loader`, edl detecta el HWID (`007050e100000000`), dice
  `Possibly unfused device detected, so any loader should be fine...`,
  lista los candidatos de `Loaders\` y **auto-selecciona el bueno**:
  `Loaders\bkerler\007050e100000000_278448179ac756a1_fhprg_peek.bin`
- Con ese loader el Firehose responde **`TargetName=MSM8916 / MemoryName=eMMC / Version=1`**
  y las lecturas funcionan (`read:0xfa5`, `read:0x200`, `read:0x3fa5`...).
- Si se fuerza `--loader` con otro fichero, las lecturas se cuelgan o el loader es rechazado.

### Parche imprescindible (ya aplicado)
`edlclient/Library/firehose.py` → en `configure()`, el read de storage-init se sustituyó por
`rsp = response(resp=True, data=b"")`. **Sin ese parche, el storage-init consume la única
lectura válida de la sesión y las nuestras expiran.**

### Detalles
- `WorkingDirectory` = `C:\UFI-Recovery\Work` (edl escribe `logs\log.txt` ahí).
- Python **3.12** (`py -3.12`). No usar `python` (3.9).
- Tamaños de lectura que completan bien: **≤ 8-32 sectores** (4-16 KB). Con peticiones grandes
  el dispositivo entrega ~114 KB y se detiene → **leer por tramos**.

### Loader de referencia (el que edl auto-elige)
```
C:\UFI-Recovery\Tools\edl\Loaders\bkerler\007050e100000000_278448179ac756a1_fhprg_peek.bin
SHA256 72c785b2221a8524be61d0fd621dbbcf9e93ecdb9a5dae78deb09386f04e290f · 94 KB · ELF 32-bit
```
(NO hace falta pasarlo con `--loader`: edl lo encuentra solo en `Loaders\`).

## 2. Comando canónico (auto-selección de loader)

```powershell
py -3.12 C:\UFI-Recovery\Tools\edl\edl.py rs <start_sector> <num_sectors> <fichero> `
  --vid 0x05C6 --pid 0x9008 --memory emmc --sectorsize 512 --debugmode --skipresponse
```

- **SIN `--loader`** (ver regla de oro en el punto 1).
- **Siempre** con `WorkingDirectory = C:\UFI-Recovery\Work` (edl escribe `logs\log.txt` ahí).
- Python: **3.12** (`py -3.12`). No usar `python` (3.9) ni `py` a secas.

## 3. Cómo entra el dispositivo en EDL (confirmado por el usuario)

1. **Mantener pulsado el botón** mientras se conecta el USB → aparece `QHSUSB__BULK` (05C6:9008).
2. Se puede **soltar el botón** y el dispositivo permanece en EDL.
3. Driver: **WinUSB** (`oem99.inf`, libwdi/Zadig). El driver serie Qualcomm (`qcwdfser`) fue
   **eliminado a propósito** para que no ganara el PnP. **No reinstalarlo.**

## 4. Hechos confirmados del hardware

| Dato | Valor | Origen |
|---|---|---|
| HWID | `0x007050e100000000` (MSM_ID 0x007050e1) | Sahara `cmdexec_get_msm_hwid` |
| PK_HASH | `cc3153a80293939b90d02d3bf8b23e0292e452fef662c74998421adad42a380f` | = hash raíz **público** de Qualcomm → **dispositivo NO fusionado** |
| Almacenamiento | eMMC · 7 634 944 sectores · 512 B/sector · 3 particiones físicas | Firehose `<getstorageinfo>` |
| USB | 2.0 · 1 interfaz vendor (0xFF) · EP 0x81 IN / 0x01 OUT bulk 512 B | descriptor |
| Modo normal | compuesto `18D1:D001` con **solo RNDIS** (sin ADB, sin CDC-ACM) | monitor PnP |
| Síntoma | arranca el kernel ~1 s y se reinicia en bucle; antes cae a EDL | monitor PnP |

## 5. Tabla de particiones REAL (leída del dispositivo)

| Partición | Inicio (LBA) | Sectores | Bytes |
|---|---|---|---|
| cdt | 131072 | 4 | 2 048 |
| sbl1 | 262144 | 1 024 | 524 288 |
| rpm | 263168 | 1 024 | 524 288 |
| tz | 264192 | 2 048 | 1 048 576 |
| hyp | 266240 | 1 024 | 524 288 |
| sec | 267264 | 32 | 16 384 |
| modemst1 | 267296 | 4 096 | 2 097 152 |
| modemst2 | 271392 | 4 096 | 2 097 152 |
| fsc | 275488 | 2 | 1 024 |
| fsg | 393216 | 4 096 | 2 097 152 |
| aboot | 524288 | 2 048 | 1 048 576 |
| boot | 526336 | 131 072 | 67 108 864 |
| devinfo | 657408 | 2 048 | 1 048 576 |
| rootfs | 659456 | 6 975 455 | 3 573 432 320 |

⚠️ `modemst1`, `modemst2`, `fsc`, `fsg` contienen **IMEI/calibración RF**: nunca sustituir por las de otro dispositivo.

## 6. Parches aplicados a edl (todos documentados)

| Fichero | Cambio | Motivo |
|---|---|---|
| `edlclient/Library/Connection/usblib.py` | `close()`: `_ifn = getattr(self.interface,'bInterfaceNumber', self.interface)` | `is_kernel_driver_active()` esperaba int y recibía objeto Interface |
| `edlclient/Library/Connection/usblib.py` | `usbread()` envuelto en try/except con traza | capturar TypeError real sin perder datos |
| `edlclient/Library/firehose.py` | `configure()`: sustituir el read de storage-init por `response(resp=True, data=b"")` | ese read consume la única lectura útil por sesión |
| `edlclient/Library/firehose.py` | `configure()`: `parse_storage()` comentado | `getstorageinfo` provoca TypeError y no es Needed |
| `edlclient/Library/firehose.py` | `configure()`: `getluns()` en try/except | `get_gpt` provocaba el mismo TypeError |
| `edlclient/Library/firehose.py` | `writedata()`: `wf.flush()` tras cada write | los datos quedaban en buffer si el proceso se detenía |
| `edlclient/Library/firehose.py` | `xmlsend()`: coerción `str → bytes` | defensivo |

Originales preservados como `*.orig` junto a cada fichero.

## 7. Estrategia de lectura (IMPORTANTE)

- El boot ROM admite **UNA subida de loader por ciclo de energía**; después las sesiones nuevas
  entran en "Mode detected: firehose" (sesión residente) y siguen funcionando.
- **Las lecturas SÍ funcionan** dentro de una sesión (varias seguidas).
- El dispositivo entrega ~16 KB por ráfaga; el `<read>` de sectores arbitrarios funciona.
- **Orden de prioridad de lectura** (usar `rs`):
  1. Cadena de arranque: sectores **262144 → 266295** (sbl1, rpm, tz, hyp, sec) ≈ 2 MB
  2. Identidad: **267296 → 275489** (modemst1, modemst2, fsc) y **393216 → 397311** (fsg)
  3. `aboot`: **524288 → 526335** (1 MB)
  4. `boot`: **526336 → 657407** (64 MB)
  5. `devinfo`: **657408 → 659455**
  6. `rootfs`: **659456 → 7634911** (3,33 GB — solo si hace falta)

## 8. Reglas de seguridad (obligatorias)

- **NUNCA** ejecutar `w`, `wl`, `wf`, `ws`, `e`, `es`, `ep`, `erase` sin backup verificado.
- **NUNCA** modificar GPT ni `modemst1/modemst2/fsg/fsc/persist`.
- **NUNCA** instalar drivers/programas sin autorización explícita del usuario.
- **NUNCA** matar procesos Python sin identificar su línea de comandos (`Get-CimInstance Win32_Process`).
- Detección de presencia: **PnP/CIM de Windows**, no polling PyUSB (provoca resets USB).
- No reiniciar el dispositivo durante una lectura.

## 9. Utilidades creadas

| Script | Uso |
|---|---|
| `Diagnostico\Scripts\UFI-USB-Monitor.ps1` | monitor PnP no intrusivo (eventos + CSV) |
| `Diagnostico\Scripts\UFI-Backup-Partitions.ps1` | volcado secuencial por partición |
| `Diagnostico\Scripts\UFI-LiveView.ps1` | ventana con el log en vivo |
| `Tools\gpt_decode.py` | decodifica una imagen GPT |
| `Tools\usb_describe.py` | volcado de descriptores USB (una sola apertura) |
| `Tools\edl_usb_fast.py` | cazador USB caliente (NO usar: su polling molesta al dispositivo) |

## 10. ESTADO FINAL

- **CONSEGUIDO - MODEM ARREGLADO**: la particion `boot` estaba corrupta. Se restauro
  con `boot-ufi001c.img` (oficial OpenStick, SHA256 A2B527E9...) mediante:
  `py -3.12 edl.py ws 526336 <img> --vid 0x05C6 --pid 0x9008 --memory emmc
  --sectorsize 512 --debugmode` con `PYTHONIOENCODING=utf-8` (si no, la barra de
  progreso con caracteres Unicode rompe la ejecucion).
  Verificado: el sistema arranca Debian solo y responde por ADB, RNDIS y WiFi.
- **Placa identificada**: familia **UFI001B / UFI001C** (kernel 5.15.0-handsomekernel+,
  IMEI 861323067221469, particiones rootfs/devinfo/cdt, sufijo SoC 0VV).
- Pendiente opcional: backup completo via EDL, APN del SIM, instalacion limpia.

## 11. ACCESO AL MODEM (estado actual)

| Vía | Dirección | Credenciales |
|---|---|---|
| **USB RNDIS** | PC `192.168.68.193` → modem `192.168.68.1` | `ssh user@192.168.68.1` / clave `1` |
| **WiFi AP** | modem `192.168.100.1` | `ssh user@192.168.100.1` / clave `1` |
| ADB | `0123456789` | sin clave |

- **WiFi**: SSID `4G-UFI`, clave `1234567890`, canal 6.
- **RNDIS en Windows**: NO se instala solo (el gadget no expone el descriptor MS-OS).
  Se instaló **manualmente** vía Administrador de dispositivos → Actualizar controlador →
  Buscar en mi equipo → Elegir de una lista → **Adaptadores de red** → Fabricante
  **Microsoft** → Modelo **Remote NDIS Compatible Device** (aceptar la advertencia).
  Queda como adaptador `Ethernet 7` con IP por DHCP. **NO usar Zadig** (rompe otras interfaces).
- SSH habilitado y persistentente (`systemctl enable ssh`).

- **CONSEGUIDO**: Sahara completo, loader subido, Firehose ACK, lectura de sectores 1, 2-9 y 267264-267295 (`sec.img` 16 KB ✔), tabla de particiones, info de almacenamiento.
- **SIGUIENTE**: leer la cadena de arranque (262144 +4104 sectores) → comparar con firmware original → identificar la partición corrupta → restaurar.
- Informe completo: `Diagnostico\Reports\INFORME_FINAL.md`
