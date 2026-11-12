# Red y hotspot

## Cliente WiFi_ETECSA ✅

| Parámetro | Valor |
|---|---|
| SSID | `WIFI_ETECSA` |
| Seguridad | abierta (el primer perfil propio falló con "no secrets"; la conexión directa de nmcli funcionó) |
| IP | `192.168.1.87/24` |
| Puerta de enlace | `192.168.1.1` |
| DNS | `1.1.1.1` |
| BSSID | `30:B5:C2:D4:9F:AC`, canal 2, señal 64 |

### Detalle que costó encontrar

La red **solo es visible con el AP apagado**: con el hotspot activo el escaneo
devolvía únicamente el SSID propio. Apagando `Hotspot` con
`nmcli con down Hotspot` y haciendo rescan, apareció `WIFI_ETECSA`.

El perfil queda con `connection.autoconnect yes` y el `Hotspot` con
`connection.autoconnect no`, de modo que tras un reinicio el equipo se conecta a
la red externa y no vuelve a levantar el AP.

### Verificación de conectividad

```
ping 1.1.1.1        → 0 % packet loss, ~250 ms
ping google.com     → resuelve y responde
/dev/tcp/google.com/80 → "HTTP/1.0 301 Moved Permanently"   (salida real)
```

Nota: el stick no trae `curl` ni `wget`; la prueba HTTP se hizo con `/dev/tcp`.

## Hotspot propio

| Elemento | Estado |
|---|---|
| AP con IP fija `192.168.100.1/24` en `wlan0` | ✅ funcionó |
| Perfil `Hotspot` de NetworkManager | ✅ usado; `autoconnect` desactivado a petición |
| Gestor real del AP | 🟡 el servidor Go buscaba `hostapd.conf`; **no demostrado** que el sistema use `hostapd` |

## RNDIS por USB ✅

El adaptador de red RNDIS **no se crea automáticamente** en Windows
(`CM_PROB_FAILED_INSTALL`): el gadget no expone el descriptor MS-OS que el
sistema necesita. Se resolvió por instalación manual:

1. Administrador de dispositivos → dispositivo `RNDIS` (error).
2. Actualizar controlador → Buscar en mi equipo → Elegir de una lista.
3. **Adaptadores de red** → Fabricante **Microsoft** → Modelo
   **Remote NDIS Compatible Device**.
4. Aceptar la advertencia de compatibilidad.

Resultado: adaptador `Ethernet 7` con IP por DHCP del modem (`192.168.68.x`).

## Listado de clientes (🟡)

Vías consideradas para el panel:

```
iw dev INTERFAZ station dump
ip neigh show        /  /proc/net/arp
```

Limitación real: una estación asociada no siempre tiene IP en la tabla de
vecinos, así que "clientes con IP" y "clientes asociados" son conjuntos distintos.

## Cambio de MAC (🟡)

Procedimiento diseñado: bajar el AP, `ip link set dev wlan0 down`, cambiar la
dirección, subir la interfaz, reiniciar el servicio. No está demostrado que el
driver Qualcomm del equipo lo permita.
