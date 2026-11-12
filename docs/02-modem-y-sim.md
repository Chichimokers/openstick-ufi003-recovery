# Módem celular y detección de SIM

## Estado funcional del módem ✅

| Componente | Evidencia |
|---|---|
| `remoteproc0` (MBA→MPSS) | `running` |
| `remoteproc1` (WCNSS) | `running` |
| dmesg | `Booting fw image mba.mbn, size 230272` → `MBA booted without debug policy, loading mpss` → `remote processor 4080000.remoteproc is now up` |
| BAM-DMUX | `wwan wwan0: port wwan0at0 attached` / `wwan0at1` / `wwan0qmi0` |
| QMI | `qmicli -d /dev/wwan0qmi0 --uim-get-card-status` responde |
| AT | `AT` → `OK` |
| Firmware | `UFI003_CT 20211210 1 [Nov 04 2016]` |

Nota: con el firmware UZ861 previo el servicio UIM colgaba
(`CID allocation failed / endpoint hangup`). Con el UFI003 responde y devuelve
el estado real de la tarjeta: **el cambio de firmware fue necesario**.

## Problema abierto: la SIM ❌

```
mmcli -m 0       → state: failed / failed reason: sim-missing / power state: off
qmicli UIM       → Slot [1]: Card state: 'error: no-atr-received (3)'
AT+CPIN?         → +CME ERROR: 10   (3GPP TS 27.007: SIM not inserted)
dmesg            → sin líneas "no-atr" (el kernel no logra el fallo)
```

## Investigación de los controles que pediste

Los controles que pediste revisar **no existen en el sistema actual**:

```
/sys/class/leds/  →  blue:   green:wan   mmc0::   red:
```

No hay `sim:en`, `sim:en2`, `sim:sel`, `sim:sel2`. El DTB activo no los declara.

## Evidencia del Device Tree

- DTB activo: `UFI003 4G Modem Stick`, compatible `thwc,ufi003`
  (repo `KyonLi/ufi003-kernel`, DTS `msm8916-thwc-ufi003.dts` + `msm8916-ufi003.dtsi`)
  → **cero nodos SIM**.
- `/proc/device-tree` → `find -iname "*sim*"` no devuelve nada.

El DTS que **sí** los define es el de OpenStick
(`OpenStick/linux`, `arch/arm64/boot/dts/qcom/msm8916-handsome-openstick-ufi001c.dts`):

```
sim_sel  { label = "sim:sel";  gpios = <&msmgpio 2 GPIO_ACTIVE_HIGH>; default-state = "on";  }
sim_en   { label = "sim:en";   gpios = <&msmgpio 1 GPIO_ACTIVE_HIGH>; default-state = "off"; }
sim_sel2 { label = "sim:sel2"; gpios = <&msmgpio 0 GPIO_ACTIVE_HIGH>; default-state = "off"; }
sim_en2  { label = "sim:en2";  gpios = <&msmgpio 3 GPIO_ACTIVE_HIGH>; default-state = "off"; }
```

## Nivel eléctrico real medido

Vía `/sys/kernel/debug/gpio` (solo lectura):

```
gpio0  : out low    <- sim:sel2
gpio1  : out low    <- sim:en    ALIMENTACIÓN DEL SLOT INACTIVA
gpio2  : out high   <- sim:sel   slot 1 seleccionado
gpio3  : out low    <- sim:en2
```

## Conclusión técnica

El fallo **no está en el módem ni en el firmware**: MBA, MPSS, BAM-DMUX, QMI y AT
funcionan. El fallo está en la **alimentación/selección del slot SIM**, que se
gobierna por GPIO (`gpio1`) y que el DTB en uso no controla. Sin alimentación el
lector no entrega ATR, incluso con tarjeta insertada.

## Reguladores

Revisados todos los carriles del PMIC (`s1..s4`, `l1..l18`, `regulator-dummy`):
ninguno aparece como dedicado de SIM; no hay evidencia de un carril de SIM
desactivado por software. Coherente con un control por GPIO y no por regulador.

## Pendiente de confirmar

1. **Hipótesis principal (evidencia fuerte):** falta de alimentación del slot.
   Prueba: con `gpio1` en alto, el QMI debería recibir ATR si hay tarjeta.
2. **Hipótesis secundaria:** no hay tarjeta insertada. Prueba: insertar una SIM
   y repetir `AT+CPIN?`.
3. Sin evidencia aún: fallo mecánico del slot o de los contactos.

Nota: no se ejecutó ninguna escritura de GPIO ni modificación del DTB durante
este diagnóstico (fue estrictamente de lectura).
