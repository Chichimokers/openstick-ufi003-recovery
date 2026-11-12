# OpenStick UFI003 — Recuperación, Módem y Administración

Repositorio de trabajo sobre un **OpenStick UFI003-CT-PRX-V1.0** (Qualcomm MSM8916)
convertido en servidor Debian: recuperación del arranque por EDL, módem celular
(QMI/AT), kernel 6.12, servicios Go y panel web de administración.

> **Convención de estados usada en todo el repo**
>
> - ✅ **VERIFICADO**: ejecutado y comprobado en el hardware durante estas sesiones.
> - 🟡 **REPORTADO**: procedente de sesiones previas; codificado o diseñado pero **no
>   reconfirmado** aquí. Tratado como pendiente de prueba.
> - ❌ **NO HECHO**: rechazado o descartado explícitamente.

---

## 1. Hardware y sistema

| Componente | Valor | Estado |
|---|---|---|
| Placa | `UFI003-CT-PRX-V1.0` | ✅ verificado (compatible DTB) |
| SoC | Qualcomm MSM8916 (`HWID 0x007050e1`) | ✅ verificado |
| eMMC | 3,65 GB (7.634.944 sectores × 512 B), 14 particiones | ✅ leído |
| RAM | ~380 MB (+zram) | ✅ verificado |
| Sistema | Debian 11 (bullseye), ARM64 | ✅ verificado |
| Kernel | `6.12.49-msm8916-g93a71ee9468d` | ✅ verificado |
| Acceso | ADB + `su` | ✅ verificado |
| Entrada EDL | mantener pulsado el botón al conectar el USB | ✅ verificado |

### 1.1 Lo que ocurrió

El modem llegó sin señal de vida: sin enumeración USB, sin LED. El diagnóstico
descartó hardware y alimentación, y se llegó al modo **EDL 9008** con el SoC
respondiendo. Por EDL se leyó la tabla GPT real, se identificó la partición
`boot` corrupta y se restauró con `boot-ufi001c.img` (OpenStick), con verificación
de firma `ANDROID!`. El equipo arrancó y quedó accesible por ADB, RNDIS y WiFi.

Detalles y evidencia: [`docs/01-recuperacion-edl.md`](docs/01-recuperacion-edl.md)

---

## 2. Módem celular y SIM

| Elemento | Estado |
|---|---|
| Kernel MSM8916 / remoteproc | ✅ MBA (230.272 B) y MPSS cargando, `remoteproc0/1 running` |
| Firmware de banda base | ✅ `UFI003_CT 20211210` (exclusivamente UFI003; nunca UZ801) |
| BAM-DMUX | ✅ `wwan wwan0: port ... attached` |
| QMI | ✅ qmicli devuelve estado completo |
| AT (`/dev/wwan0at0`) | ✅ `AT` → `OK`, `AT+CPIN?` → `+CME ERROR: 10` (SIM no insertada) |
| Errores `no-atr` en kernel | ✅ ninguno |
| **Detección de SIM** | ❌ **PENDIENTE** — `Card state: error: no-atr-received (3)` |

### 2.1 Causa raíz encontrada (diagnóstico de solo-lectura)

La placa alimenta y selecciona la SIM por **GPIO**, no por el módem:

| GPIO | Función | Nivel medido |
|---|---|---|
| **gpio1** | `sim:en` → alimentación del slot | **`out low` ← apagado** ❌ |
| gpio2 | `sim:sel` → selector de slot 1 | `out high` ✔ |
| gpio0 | `sim:sel2` | `out low` ✔ |
| gpio3 | `sim:en2` | `out low` ✔ |

Los nodos `sim:*` existen en el DTS `msm8916-handsome-openstick-ufi001c.dts`
(OpenStick/linux) con `gpios = <&msmgpio 1 GPIO_ACTIVE_HIGH>` para `sim:en`.
El DTB en uso (`thwc,ufi003`, del repo de KyonLi) **no los declara**, por lo que
nadie activa `gpio1` y el lector no entrega ATR. Comparación: la imagen de
arranque original del equipo contiene las cadenas `sim:en`/`sim:sel`; la actual,
0.

Detalles: [`docs/02-modem-y-sim.md`](docs/02-modem-y-sim.md)

---

## 3. Kernel, Go y servicios

| Elemento | Estado |
|---|---|
| Kernel `6.12.49` + DTB UFI003 | ✅ instalado por EDL (`dd` sobre la partición con `partlabel boot`) |
| **Go 1.27.2 (linux/arm64)** | ✅ instalado en `/usr/local/go`, **277 MB**, PATH en `/etc/profile` y `/root/.bashrc` |
| Compilación cruzada | ✅ documentada (`GOOS=linux GOARCH=arm64 CGO_ENABLED=0`) |
| systemd | ✅ operativo; estado `degraded` por `dnsmasq.service` y `zramswap.service` 🟡 |
| `openstick-web.service` | 🟡 diseñado; estado final **sin reconfirmar** |

---

## 4. Red

| Elemento | Estado |
|---|---|
| Cliente WiFi `WIFI_ETECSA` | ✅ conectado, **192.168.1.87/24**, GW `192.168.1.1`, DNS `1.1.1.1` |
| Salida a Internet | ✅ ping `1.1.1.1` 0 % pérdida; `google.com` resuelve; HTTP 301 real vía `/dev/tcp` |
| AP propio | ✅ desactivado con `connection.autoconnect no` (no vuelve solo al reiniciar) |
| RNDIS por USB | ✅ adaptador creado en Windows (instalación manual del driver *Remote NDIS Compatible Device*) |

---

## 5. Web y panel de administración

Delimitación mantenida durante todo el trabajo: **solo `info.html`, sus recursos
exclusivos y la API que usa**. No se toca `index.html` ni `/pedido/`.

| Componente | Estado |
|---|---|
| Servidor Go (`OpenStickWeb`) | 🟡 código y despliegue por ADB reportados; integral final sin confirmar |
| Rutas `/`, `/info/`, `/assets/`, `/api/hotspot/*` | 🟡 definidas |
| Token administrativo `291203Er*` en `data/hotspot.token` | 🟡 solicitado y aplicado en código |
| API hotspot (status/enable/disable/config/mac/clients) | 🟡 implementada en código; `hostapd` como gestor real **no demostrado** |
| Cambio de MAC | 🟡 no demostrado que el driver lo permita |
| HTTTPS desde móviles | 🟡 pendiente de verificar |

---

## 6. Restricciones vigentes

1. Hardware: `UFI003-CT-PRX-V1.0`, Qualcomm MSM8916.
2. Firmware: **exclusivamente UFI003**; nunca UZ801 ni genérico.
3. No modificar NV, IMEI, calibración RF, `modemst1/2`, `fsg`, `fsc`, `persist`.
4. No interrumpir ADB sin una vía de recuperación comprobada.
5. No borrar `data/` ni `certs/` en despliegues.
6. Proyecto ligero: Go + SQLite + estáticos. Sin Docker, PostgreSQL, Redis ni microservicios.
7. Mantener el token administrativo cuando se trabaje sobre `OpenStickWeb`.
8. En trabajo administrativo, limitarse a `info.html` y su API.
9. **No confundir código generado con funcionalidad comprobada en el hardware.**

---

## 7. Estructura del repositorio

```
├── README.md                 # este documento
├── docs/
│   ├── 01-recuperacion-edl.md    # brick → EDL → boot restaurada (✅)
│   ├── 02-modem-y-sim.md         # firmware, QMI/AT, GPIO de SIM (✅ / ❌ pendiente)
│   ├── 03-kernel-go-servicios.md # kernel 6.12, Go 1.27.2, systemd (✅)
│   ├── 04-red-y-hotspot.md       # ETECSA, AP, RNDIS (✅)
│   ├── 05-web-panel.md           # servidor, API, panel (🟡)
│   └── 06-pendientes.md          # checklist priorizado
└── scripts/                  # herramientas PowerShell usadas (✅ ejecutadas)
    └── ...
```

## 8. Próximo paso concreto

Ver `docs/06-pendientes.md`. El de mayor impacto es resolver el GPIO `sim:en`
(recompilar el DTB con los nodos `sim:*` o restaurar la imagen de arranque
original) porque es la única función que sigue sin responder en el equipo.
