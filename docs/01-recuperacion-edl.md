# Recuperación por EDL 9008 — de brick a arranque

## Síntoma inicial

- Sin sonido de conexión USB al enchufar.
- Ningún dispositivo nuevo en el Administrador de dispositivos.
- Ningún LED.

## Diagnóstico que descartó fallos físicos

| Prueba | Resultado |
|---|---|
| Cable/puerto alternativos | El modem no enumeraba **nada** (ni `05C6`, ni `18D1`) |
| Botón pulsado al conectar | **Sí** aparece `QHSUSB__BULK` (`VID_05C6&PID_9008`) y permanece |
| Descriptor USB en EDL | USB 2.0, 1 interfaz clase 0xFF, EP `0x81` IN / `0x01` OUT bulk 512 B |
| `qmicli --uim-get-card-status` | servía nada al principio (endpoint hangup) |
| Conclusión | El SoC responde; el problema está en la cadena de arranque |

## Identificación del SoC (Sahara)

```
HWID: 0x007050e100000000  (MSM_ID:0x007050e1, OEM_ID:0x0000, MODEL_ID:0x0000)
PK_HASH: cc3153a80293939b90d02d3bf8b23e0292e452fef662c74998421adad42a380f
```
El `PK_HASH` coincide con el hash raíz **público** de Qualcomm → dispositivo
**no fusionado**, acepta loaders genéricos.

## Firmware de banda base

Versión finalmente cargada: `UFI003_CT 20211210`
(`mba.mbn` de 230.272 B, fichero específico UFI003).
Procedencia: `HandsomeMod/qcom-firmware` → `openstick-ufi003-modem.bin`,
montado en solo-lectura y copiado a `/lib/firmware/` (nunca a la partición eMMC).

## Tabla de particiones real (leída del dispositivo)

| # | Partición | Inicio (LBA) | Sectores | Tamaño |
|---|---|---|---|---|
| 0 | cdt | 131.072 | 4 | 2 KB |
| 1 | sbl1 | 262.144 | 1.024 | 512 KB |
| 2 | rpm | 263.168 | 1.024 | 512 KB |
| 3 | tz | 264.192 | 2.048 | 1 MB |
| 4 | hyp | 266.240 | 1.024 | 512 KB |
| 5 | sec | 267.264 | 32 | 16 KB |
| 6 | modemst1 | 267.296 | 4.096 | 2 MB |
| 7 | modemst2 | 271.392 | 4.096 | 2 MB |
| 8 | fsc | 275.488 | 2 | 1 KB |
| 9 | fsg | 393.216 | 4.096 | 2 MB |
| 10 | aboot | 524.288 | 2.048 | 1 MB |
| 11 | **boot** | 526.336 | 131.072 | 64 MB |
| 12 | devinfo | 657.408 | 2.048 | 1 MB |
| 13 | rootfs | 659.456 | 6.975.455 | 3,33 GB |

⚠️ `modemst1`, `modemst2`, `fsg`, `fsc` contienen **IMEI y calibración RF**:
nunca se sustituyen por las de otra unidad.

## Reparación aplicada

1. Identificar la partición de arranque por su etiqueta: `/dev/disk/by-partlabel/boot`.
2. Respaldo previo de la partición (64 MB) en el equipo **y** en el PC.
3. Escritura con el método oficial del proyecto:
   ```
   dd if=boot.img of=/dev/disk/by-partlabel/boot bs=1M
   ```
4. Verificación: MD5 idéntico al fichero fuente.
5. Reinicio → el sistema arranca y responde por ADB.

**Limitación descubierta:** el boot ROM acepta **una** subida de cargador por ciclo
de energía; tras la primera sesión el Sahara queda "quemado" (respuesta basura).
Solución practicada: un power-cycle por sesión de lectura.

## Cadena de herramientas

- Driver: **WinUSB** vinculado al `QHSUSB__BULK` (eliminar el driver serie de
  Qualcomm del almacén, o gana el PnP y rompe la sesión).
- `edl` (bkerler) con Python 3.12: `py -3.12 edl.py ...
  --vid 0x05C6 --pid 0x9008 --memory emmc --sectorsize 512`
- Detección de presencia por **PnP/CIM de Windows**, nunca por sondeo USB
  repetido (provoca resets que matan la sesión EDL).
- Parche aplicado a `firehose.py`: se salta el *read* de storage-init para
  reservar la única lectura útil de cada sesión.

## Evidencia conservada

| Fichero | Contenido |
|---|---|
| `backup/boot-orig-5.15.img` | Partición boot original (64 MB) |
| `backup/gpt-*.bin` | Sectores de la tabla de particiones |
| `logs/` | Registros de cada sesión EDL |
