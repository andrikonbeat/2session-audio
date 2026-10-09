# 2session-audio

¿Tenés **dos cuentas (o dos sesiones) en la misma computadora** y solo una
tiene sonido? Este programa hace que **las dos suenen al mismo tiempo**.

No necesitás permisos de administrador, no hay que editar archivos a mano, y
se puede deshacer con un comando.

## Instalación: un solo comando

Abrí una terminal y pegá esto (pegás con `Ctrl+Shift+V`). Hacelo en **cada
cuenta** que necesite sonido:

```sh
curl -fsSL https://raw.githubusercontent.com/andrikonbeat/2session-audio/main/install.sh | bash
```

Eso es todo. El comando **instala y configura** el audio de la cuenta en la que
lo corrés, y agrega una entrada en el menú de aplicaciones.

**Si tenés dos cuentas:** iniciá sesión en la otra y corré el mismo comando.
Es el único paso que falta para que las dos suenen juntas a la vez.

## ¿Qué hace exactamente?

1. Detecta tu tarjeta de sonido (no hay que elegir nada).
2. La comparte entre tus cuentas, para que puedan sonar al mismo tiempo.
3. Deja el volumen de la placa al máximo, para que se escuche fuerte aunque el
   control de volumen de cada sesión esté aparte.

Todo es reversible y **no toca tus archivos personales**: si ya tenías una
configuración de audio propia, se guarda como respaldo antes de tocar nada.

## Si algo no anda

| Qué ves | Qué hacer |
|---|---|
| Solo una cuenta tiene sonido | Corré el comando de instalación también en la otra cuenta. |
| Se escucha bajito aunque el volumen esté al 100% | Cerrá la sesión y volvé a entrar (o reiniciá). El arreglo se aplica solo al iniciar sesión. |
| Quiero ver qué detectó | `~/.local/share/dual-session-setup/setup.sh --check` |
| Se rompió algo | Desinstalá (abajo) y volvé a instalar. |

## Desinstalar

En **cada** cuenta donde lo instalaste:

```sh
curl -fsSL https://raw.githubusercontent.com/andrikonbeat/2session-audio/main/uninstall.sh | bash
```

Restaura tu configuración anterior (si la había) y borra lo que creó el
programa. Las modificaciones que hayas hecho a mano nunca se borran. Volver a
correrlo no hace nada malo.

## Requisitos

| Requisito | Nota |
|---|---|
| Linux con PipeWire + WirePlumber | Es la base sobre la que se comparte el audio. |
| systemd + logind | Para detectar y cambiar entre sesiones. |
| bash ≥ 4 | Es el shell por defecto en casi todas las distros modernas. |
| `curl` + `tar` | Solo para la instalación de una línea. |
| `python3` | Solo para el botón opcional "Switch session" del shell. |

No soportado: equipos con solo PulseAudio, sin systemd, o que no sean Linux.
Todo se detecta solo; si detecta la placa equivocada, se puede forzar en el
archivo de configuración (ver *Configuración*).

## Detalles técnicos

### Por qué esto existe

Una placa HDA on-board normalmente tiene un solo flujo de audio. La primera
sesión lo toma de forma exclusiva y la segunda termina con una salida muda
("Dummy Output", `EBUSY`).

Este programa:

1. Abre la placa a través de un **dmix de ALSA compartido** (`~/.asoundrc`),
   para que varias sesiones mezclen en el mismo PCM.
2. Fuerza a **WirePlumber** a usar ese camino compartido.
3. Agrega un **sink estático de PipeWire** para las sesiones que no enumeran la
   placa.
4. Fija el **mixer de hardware de la placa al máximo** en cada inicio de sesión,
   porque al desactivar ACP PipeWire deja de mapear el volumen al hardware.

### Cómo se comparten las claves entre cuentas

Ambas cuentas deben abrir el mismo dmix para mezclar en el mismo PCM. La clave
IPC se deriva de la ranura PCI de la placa con `cksum`, así que **cualquier
cuenta de la misma máquina calcula las dos mismas claves**
(`key1 = 10000000 + (cksum % 80000000)`, `key2 = key1 + 1`).
`ipc_key_add_uid false` y `ipc_perm 0666` hacen accesible el mixer de memoria
compartida a las dos cuentas. Alcanza con correr el setup una vez por cuenta;
los resultados son idénticos.

### Por qué se fija el mixer de hardware

Forzar la placa al dmix compartido requiere `api.alsa.use-acp = false` (si no,
ACP se queda con la placa). Pero ACP es también lo que mapea el volumen del
escritorio al mixer de **hardware** de la placa. Con ACP apagado, PipeWire solo
aplica volumen *por software* y deja los controles de hardware (p. ej.
`Master`) en el valor que ALSA restauró al arrancar.

Si ese valor quedó por debajo del máximo, la placa suena bajito sin importar
qué diga el control de volumen del escritorio — el control marca 100% mientras
el hardware está, por ejemplo, en −23 dB — y arreglarlo a mano no sobrevive al
reinicio, porque `alsa-restore` vuelve a aplicar el valor guardado.

Para mantener fuerte el setup compartido, la instalación escribe un pequeño
script y una unidad `systemd --user` (oneshot) que fijan el mixer de hardware
de la placa detectada al máximo en cada inicio de sesión:

```
~/.local/share/dual-session-setup/pin-mixer.sh
~/.config/systemd/user/dual-session-audio-mixer.service
```

La unidad se habilita al instalar y se elimina al desinstalar. Los controles
que se fijan se pueden cambiar con `MIXER_CONTROLS` (ver *Configuración*).

### Comandos

| Comando | Qué hace |
|---|---|
| `install.sh` | Instala **y configura** (lo que usa el usuario normal). |
| `install.sh --check` | Muestra el entorno detectado. No cambia nada. |
| `install.sh --dry-run` | Simula la instalación. No cambia nada. |
| `install.sh --no-setup` | Solo copia el programa, no configura. |
| `install.sh --uninstall` | Desinstala y restaura. |
| `setup.sh` | Reconfigura el audio del usuario actual (crea la config en la primera corrida). |
| `setup.sh --check` | Igual que `install.sh --check`. |
| `setup.sh --dry-run` | Igual que `install.sh --dry-run`. |
| `setup.sh --ui-only` | Solo la integración del shell (requiere `shell.json`). |
| `uninstall.sh` | Restaura respaldos y borra todo lo que creó el programa. |

### Garantías de seguridad

- **`--check` y `--dry-run` nunca escriben ni cambian nada.**
- **Los archivos de configuración nunca se pisan**: se respaldan primero.
- **Tus archivos modificados nunca se borran**: al desinstalar se conserva
  cualquier archivo cuyo contenido ya no coincida con la firma registrada,
  junto con su respaldo.
- **Idempotente**: volver a correr cualquier comando es seguro.

### Configuración

En la primera corrida real se crea `~/.config/dual-session-setup.conf` con los
valores detectados (modo `600`). Nunca se pisa; editá el archivo para forzar un
valor y volvé a correr `setup.sh`.

| Clave | Por defecto | Significado |
|---|---|---|
| `CARD_SLOT` | detectado | Ranura PCI de la placa, p. ej. `pci-0000_00_1f.3`. |
| `CARD_ALSA_NAME` | detectado | Nombre corto ALSA de `/proc/asound/cards`, p. ej. `PCH`. |
| `ALSA_DEVICE` | `0` | Número de dispositivo ALSA. |
| `RATE` | `48000` | Frecuencia de muestreo de los PCM compartidos. |
| `FORMAT` | `S16_LE` | Formato de muestra de los PCM compartidos. |
| `CHANNELS` | `2` | Cantidad de canales de los PCM compartidos. |
| `PERIOD_SIZE` | `1024` | Tamaño de período del dmix. |
| `BUFFER_SIZE` | `8192` | Tamaño de buffer del dmix. |
| `ENABLE_UI` | `1` si existe `shell.json` | Activa la integración del shell (`0`/`1`). |
| `IPC_KEY_BASE` | derivado | Primera clave dmix compartida; la de dsnoop es `IPC_KEY_BASE + 1`. |
| `MIXER_CONTROLS` | `Master PCM Front` | Controles de hardware que se fijan al 100% en cada login. Poné los que exponga tu placa. |

### Orden de detección

1. Escanea `/proc/asound/card*/codec#0` buscando firmas de códecs on-board
   (Realtek `ALC*`, `VT*`, `CX*`, `STAC*`, Sigmatel, Analog Devices).
2. Alternativa: la primera placa cuya clase de dispositivo en sysfs sea `0403`
   (Audio) y cuyo nombre corto no sea HDMI / Display Audio.
3. Último recurso: `card0`.

Forzá cualquier valor con el archivo de configuración si detecta la placa
equivocada.

### Qué se instala

```
~/.local/share/dual-session-setup/
├── setup.sh        # configura el audio (re-ejecutable)
├── uninstall.sh
└── lib/
    ├── common.sh   # detección, config, respaldo/restauración
    ├── audio.sh    # asoundrc + confs de WirePlumber/PipeWire
    ├── mixer.sh    # fija el mixer de hardware al máximo en cada login
    └── ui.sh       # integración opcional del shell (shell.json)
```

Además, en la primera corrida: `~/.config/dual-session-setup.conf` y
`~/.config/dual-session-setup.manifest` (la lista de firmas que usa el
desinstalador), la unidad `systemd --user`
`~/.config/systemd/user/dual-session-audio-mixer.service` con su script
`~/.local/share/dual-session-setup/pin-mixer.sh`, y una entrada de menú en
`~/.local/share/applications/dual-session-setup.desktop`.

## Soporte

¿Encontraste un problema o querés una función nueva? Abrí un issue en
https://github.com/andrikonbeat/2session-audio/issues
