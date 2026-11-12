# Pendientes, ordenados por impacto

## 1. SIM sin detectar (bloquea la función 4G del equipo)

Causa sostenida por evidencia: el GPIO `sim:en` (`gpio1`) está en `low` y el DTB
`thwc,ufi003` no declara los nodos `sim:*` necesarios para gobernarlo.

Caminos, del menos al más invasivo:

1. **Probar alimentando el slot**: exportar `gpio1` como salida y ponerlo en alto,
   luego consultar `qmicli --uim-get-card-status`. Si aparece ATR con tarjeta
   insertada, la causa queda confirmada.
2. **Compilar un boot.img con el DTB correcto**: usar el DTS
   `msm8916-handsome-openstick-ufi001c.dts` (que sí define `sim:*`) conservando
   el kernel 6.12. Es la solución limpia y permanente.
3. **Restaurar la partición `boot` original** (backup disponible, 64 MB):
   recupera los `sim:*` pero vuelve al kernel 5.15.

Prerequisito para todos: **tener una SIM insertada** para poder observar el ATR.

## 2. Verificar la conectividad de datos móviles

Con la SIM detectada: `nmcli`/`mmcli` para el perfil de red, registrar en la red,
confirmar `wwan0` con IP. No tocar APN: el fallo actual es anterior al registro.

## 3. Estado integral del servidor Go (🟡)

Reconfirmar en el equipo:

```
systemctl status openstick-web.service --no-pager
journalctl -u openstick-web.service -n 100 --no-pager
```

y comprobar HTTP/HTTPS desde un móvil.

## 4. Hotspot

- Demostrar qué gestor levanta realmente el AP (`hostapd` o NetworkManager).
- Verificar cambio de SSID/contraseña y de MAC.
- Verificar el listado real de clientes (`iw station dump` + tabla ARP).

## 5. Portal de acceso

- Implementar y probar en el equipo la ruta `/login` + SQLite (sin contraseñas en claro).
- Corregir el refresco automático que sobrescribía campos en edición.

## 6. Sistema

- `dnsmasq.service` y `zramswap.service` en fallo (`systemd` en `degraded`).
  No bloquean el servicio Go, pero conviene dejarlos coherentes si se usa DNS
  local o portal.

## Criterio para cerrar cada punto

Un punto se marca ✅ solo con salida de comando ejecutada en el equipo con
fecha, no por existir el código.
