# INFORME — Instalación firmware de módem UFI003

Fecha: 12-nov-2026 | Dispositivo: OpenStick UFI003-CT-PRX-V1.0 | SoC: Qualcomm MSM8916

## Archivos descargados

| Fichero | Tamaño | SHA256 | Origen |
|---|---|---|---|
| `openstick-ufi003-modem.bin` | 67.108.864 B (64 MB) | `0F2E4425F13BBDA6029B677208ABCFFCFB2E93E64F266D5A26C039009413F20F` | github.com/HandsomeMod/qcom-firmware |
| MD5 verificado tras transferencia | 64 MB | `07caf04801eed2fef666c81d29efa744` | local == modem ✔ |

Formato: imagen **FAT16** (montable `mount -o ro,loop`), contiene `image/` con los blobs
`modem.mdt`, `modem.b00-b26`, `mba.mbn`, `wcnss.*`, `playread.*`, `widevine.*`,
`keymaste.*`, `isdbtmm.*`, `cmnlib.*` + `modem_pr/mcfg/configs/` (MCFG por operador).

## Firmware instalado

| Dato | Antes (UZ801) | Después (**UFI003**) |
|---|---|---|
| `firmware revision` | `UZ801_V3.0_21_V01R01B10` | **`UFI003_CT 20211210 1 [Nov 04 2016]`** |
| `mba.mbn` | 234.176 B | **230.272 B** (fichero UFI003) |
| `modem.b00/b01/b05/b06...` | set UZ801 | **set UFI003** (ver diff abajo) |
| Ficheros copiados | — | 57 blobs + árbol MCFG (67 ficheros) |
| initramfs | no requiere rebuild (el firmware no está en el initramfs) | — |

Diferencias detectadas (muestra): `mba.mbn` 234176→230272, `modem.b04` 139616→205152,
`modem.b05` 81920→338764, `modem.b06` 3099238→175904, `modem.b08` 172560→44880.

## Copias de seguridad

| Ruta en el modem | Contenido |
|---|---|
| `/root/backup-fw-pre-ufi003` | `/lib/firmware` completo previo (141 ficheros, 57 MB) |
| `/root/backup-firmware` | `/lib/firmware` original de fábrica (141 ficheros) |
| `/root/backup-firmware-v30-pre` | estado previo al V3.0 |
| `C:\UFI003\backup\boot-orig-5.15.img` | partición `boot` original (64 MB) |

Restauración (ADB root):
```
adb shell "cp -a /root/backup-fw-pre-ufi003/. /lib/firmware/; reboot"
```

## Resultado del arranque

| Comprobación | Resultado |
|---|---|
| Kernel | `6.12.49-msm8916-g93a71ee9468d` (sin cambios) |
| `remoteproc0/state` | **running** |
| `remoteproc1/state` (WCNSS) | **running** |
| dmesg MBA | `Booting fw image mba.mbn, size 230272` |
| dmesg MPSS | `MBA booted without debug policy, loading mpss` → `remote processor 4080000.remoteproc is now up` |
| Puertos QMI/AT | `wwan0`, `wwan0at0`, `wwan0at1`, `wwan0qmi0` |
| Errores `no-atr` en kernel | **ninguno** |

## Detección de SIM (QMI)

```
qmicli -d /dev/wwan0qmi0 --uim-get-card-status
  Slot [1]: Card state: 'error: no-atr-received (3)'
  Primary GW / 1X / Secondary GW / 1X: session doesn't exist
```

**Comparación clave**: con el firmware UZ801 el servicio UIM no era accesible
(`CID allocation failed in the CTL client: endpoint hangup`). Con el firmware
**UFI003_CT** el servicio UIM **responde** y devuelve el estado real de la tarjeta.

## Conclusiones

| Punto | Estado |
|---|---|
| Firmware UFI003 específico descargado e instalado | **CONFIRMADO** (SHA256 verificado, versión `UFI003_CT`) |
| MBA y MPSS cargan correctamente | **CONFIRMADO** (remoteproc running, dmesg limpio) |
| Servicio UIM accesible por QMI | **CONFIRMADO** (mejora frente a UZ801) |
| `no-atr-received` en el kernel | **DESAPARECIDO** (0 líneas en dmesg) |
| `no-atr-received` en QMI (estado de tarjeta) | **PRESENTE** (`error: no-atr-received (3)`) |
| SIM detectada | **NO** — el slot informa que no hay tarjeta |

### Problema raíz restante
El módem está correctamente configurado (firmware UFI003_CT + DTB UFI003) pero
**el lector de SIM no entrega ATR**: el slot sigue sin detectar tarjeta. Las causas
posibles, en orden:
1. **No hay tarjeta SIM insertada** (el hardware reporta `slot 1: none (active)`).
2. Contactos del slot sucios/oxidados (limpiar con aire comprimido y alcohol).
3. Alimentación del slot controlada por GPIO del DTB (revisar `sim_en`/`sim_sel` en
   `thwc,ufi003.dtb` frente a la revisión CT-PRX de la placa).
4. Slot físicamente dañado.

### Próximo paso exacto
Insertar una tarjeta SIM y ejecutar:
```
adb shell "qmicli -d /dev/wwan0qmi0 --uim-get-card-status; mmcli -m 0"
```
Si aparece `Card state: 'present'` + ATR → resuelto. Si sigue `no-atr-received`,
el problema es del lector/GPIO (punto 3/4), no del firmware.

## Restricciones cumplidas

- ✔ Firmware exclusivamente identificado como UFI003 (`openstick-ufi003-modem.bin`).
- ✘ No se usó firmware UZ801, genérico MSM8916 ni de otras placas.
- ✘ No se copió `openstick-ufi003-nv.bin` ni se modificó NV de otra unidad.
- ✘ No se modificaron modemst1, modemst2, fsg, fsc ni persist (solo `/lib/firmware`).
- ✘ No se reinstaló Debian ni se cambió el kernel.
- ✔ Backup completo antes y después.
