# Kernel, Go y servicios

## Kernel 6.12 instalado ✅

Origen: release `13.1-14` del repo `KyonLi/ufi003-debian`
(kernel `6.12.49-msm8916-g93a71ee9468d`, bootloader `lk1st-msm8916-21.0`).

Piezas usadas:

| Fichero | Tamaño |
|---|---|
| `linux-image-6.12.49-msm8916-g93a71ee9468d_..._arm64.deb` | 17.1 MB |
| `boot.img` (kernel + DTB + ramdisk) | 20,3 MB |

Procedimiento respetando las restricciones del proyecto:

1. **Backup previo** de la partición `boot` (64 MB, en el equipo y en el PC).
2. Instalación del `.deb` con `dpkg -i` **sin purgar** el kernel anterior
   (queda `5.15.0-handsomekernel+` para recuperación).
3. `update-initramfs` automático; el firmware del módem **no** va en la initramfs,
   así que no requiere reconstrucción.
4. Escritura del `boot.img` con el método oficial del repo:
   ```
   dd if=/root/boot.img of=/dev/disk/by-partlabel/boot bs=1M
   ```
   (partición identificada por `partlabel`, no por número supuesto.)
5. Verificación por MD5 exacto antes de reiniciar.
6. Reinicio → `uname -r` confirma `6.12.49-msm8916-g93a71ee9468d`.

### DTB y placa

El `boot.img` del repo UFI003 incorpora el DTB `thwc,ufi003`
(modelo `UFI003 4G Modem Stick`). Arranca correctamente en este equipo, pero —
como se documenta en `02-modem-y-sim.md` — **carece de los nodos GPIO de SIM**
que necesita el slot de esta placa.

## Go instalado ✅

| Elemento | Valor |
|---|---|
| Versión | `go1.27.2 linux/arm64` |
| Origen | mirror Aliyun (`mirrors.aliyun.com/golang/`) |
| Ubicación | `/usr/local/go` |
| Espacio | **277 MB** (1,6 GB libres tras instalar) |
| PATH | persistente en `/etc/profile` y `/root/.bashrc` |

Nota: los servidores oficiales (`go.dev`, `dl.google.com`) devolvían 404 desde
esta red; el mirror de Aliyun sirvió el tarball correcto.

### Compilación cruzada

```powershell
cd D:\Proyectos\OpenStickWeb
$env:GOOS = "linux"
$env:GOARCH = "arm64"
$env:CGO_ENABLED = "0"
go build -trimpath -ldflags "-s -w" -o bin\server-linux-arm64 .
```

`CGO_ENABLED=0` evita necesitar toolchain C dentro del stick (muy limitado: 380 MB de RAM).

## systemd

Estado operativo, pero **`degraded`**:

```
$ systemctl is-system-running
degraded
```

Servicios problemáticos detectados:

| Servicio | Estado |
|---|---|
| `dnsmasq.service` | falla al arrancar (intento de bind en configuración heredada) |
| `zramswap.service` | falla al arrancar |

Importante: esto **no** impide ejecutar el servidor Go propio con `Restart=always`.
El `degraded` es del sistema previo, no del servicio web.

### Unidad propuesta (🟡 diseñada, no reconfirmada)

```ini
[Unit]
Description=OpenStick Go Web Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/openstick-web
ExecStart=/opt/openstick-web/server
Restart=always
RestartSec=3
KillSignal=SIGTERM
TimeoutStopSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Administración:

```
systemctl status openstick-web.service --no-pager
journalctl -u openstick-web.service -n 100 --no-pager
systemctl restart openstick-web.service
```

## Despliegue por ADB (🟡 reportado)

Problemas resueltos en sesiones previas:

| Problema | Solución |
|---|---|
| `CRLF` en scripts Linux | generar `.sh` con finales LF, UTF-8 sin BOM |
| `fi` / errores de shell | ejecutar vía `sh /data/local/tmp/script.sh` |
| `su -c` con rutas mal citadas | comillas simples envolviendo la ruta completa |
| `Text file busy` al reemplazar binario | subir como `server.new` y luego `mv` |

Patrón:
```
adb shell "su -c 'sh /data/local/tmp/openstick-web-root-command.sh'"
```

Conservar siempre en el despliegue: `/opt/openstick-web/data/` y `/opt/openstick-web/certs/`.
