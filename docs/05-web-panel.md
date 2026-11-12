# Servidor Go, panel y API de administración

Alcance mantenido: **`info.html`, sus recursos exclusivos y la API que usa**.
No se toca `index.html` ni la lógica de `/pedido/`.

## Estructura del proyecto

```
D:\Proyectos\OpenStickWeb          /opt/openstick-web
├── main.go
├── go.mod
├── index.html          (fuera de alcance)
├── info.html           (panel administrativo)
├── assets/{css,js,images}
├── data/               (persistente en despliegues)
├── certs/              (persistente en despliegues)
└── bin/
    server-linux-arm64
```

Puertos: `80` (HTTP) y `443` (HTTPS).

## Rutas

| Ruta | Propósito |
|---|---|
| `/` | Página principal (fuera de alcance) |
| `/info`, `/info/` | Panel administrativo |
| `/assets/*` | Estáticos (css/js/images) |
| `/pedido/` | Funcionalidad de pedidos (fuera de alcance) |
| `/api/hotspot/*` | Administración del hotspot |

## Panel administrativo

Contenido del panel: estado del hotspot, SSID, MAC, interfaz Wi-Fi, clientes
conectados, acciones de activar/desactivar, cambio de SSID y contraseña,
actualización automática cada 10 s.

Token administrativo: valor fijo solicitado

```
291203Er*
```

escrito en `data/hotspot.token`; el servidor acepta
`Authorization: Bearer 291203Er*`. El token se reescribe en cada arranque.

Defecto conocido pendiente: el refresco automático podía sobrescribir los campos
SSID/interfaz mientras el administrador escribía. Corrección pendiente.

## API del hotspot

| Méto | Endpoint | Función |
|---|---|---|
| GET | `/api/hotspot/status` | Estado |
| POST | `/api/hotspot/enable` | Activar |
| POST | `/api/hotspot/disable` | Desactivar |
| GET | `/api/hotspot/config` | Consultar |
| POST | `/api/hotspot/config` | Modificar |
| POST | `/api/hotspot/mac` | Cambiar MAC |
| GET | `/api/hotspot/clients` | Listar clientes |

Configuración de hostapd buscada en `/etc/hostapd/hostapd.conf`,
`/etc/hostapd.conf` o la ruta de `OPENSTICK_HOSTAPD_CONFIG`.

## Nota sobre el portal cautivo

La idea evolucionó hacia un **portal de acceso simple** para un equipo de
laboratorio. El diseño acordado fue:

| Ruta | Contenido |
|---|---|
| `/` | Portal (página principal accesible) |
| `/login` | Proceso de acceso |
| `/info` | Panel de administración (única ruta administrativa) |

Decisiones de diseño acordadas:

- **SQLite** para registrar intentos: usuario introducido, IP, fecha/hora,
  resultado del intento.
- **No almacenar contraseñas en texto plano ni mostrar credenciales capturadas.**
- Sin Docker, PostgreSQL, Redis ni microservicios.
- Pensado para un puñado de clientes, no para cargas de producción.

Estado: arquitectura definida; **implementación y pruebas en el equipo: no
demostradas**.
