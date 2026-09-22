#!/usr/bin/env bash
#
# dual-session-ui-setup.sh
# =========================
# Restores caelestia's shell.json with the session-switch integration:
#   * launcher action "Switch session" (type ">" in the launcher)
#   * session popup button (4th slot, former Hibernate) -> switch to KDE
# Only meaningful for the CAELESTIA user; other users (e.g. andrik) skip it.
#
# How to use afterwards:
#   * Switch session button:  CTRL+ALT+Delete -> 4th button (switch_account)
#   * Launcher alternative:   SUPER+SUPER_L (double-tap Super) -> type ">" + "switch"
#   * Return to Hyprland:     Ctrl+Alt+F3
# shell.json hot-reloads (QFileSystemWatcher); no shell restart needed.
#
set -euo pipefail

if [ "$USER" != "caelestia" ]; then
  echo "UI setup is caelestia-only; skipping for user '$USER'."
  exit 0
fi

mkdir -p "$HOME/.config/caelestia"

cat > "$HOME/.config/caelestia/shell.json" <<'EOF'
{
    "appearance": {
        "transparency": {
            "enabled": true
        }
    },
    "border": {
        "rounding": 10
    },
    "session": {
        "icons": {
            "hibernate": "switch_account"
        },
        "commands": {
            "hibernate": [
                "bash",
                "-c",
                "loginctl activate $(loginctl list-sessions --no-legend | awk '$3 == \"andrik\" && $6 == \"user\" {print $1; exit}')"
            ]
        }
    },
    "launcher": {
        "actions": [
            {
                "name": "Calculator",
                "icon": "calculate",
                "description": "Do simple maths equations (powered by Qalc)",
                "command": [
                    "autocomplete",
                    "calc"
                ]
            },
            {
                "name": "Scheme",
                "icon": "palette",
                "description": "Change the current colour scheme",
                "command": [
                    "autocomplete",
                    "scheme"
                ]
            },
            {
                "name": "Wallpaper",
                "icon": "image",
                "description": "Change the current wallpaper",
                "command": [
                    "autocomplete",
                    "wallpaper"
                ]
            },
            {
                "name": "Variant",
                "icon": "colors",
                "description": "Change the current scheme variant",
                "command": [
                    "autocomplete",
                    "variant"
                ]
            },
            {
                "name": "Random",
                "icon": "casino",
                "description": "Switch to a random wallpaper",
                "command": [
                    "caelestia",
                    "wallpaper",
                    "-r"
                ]
            },
            {
                "name": "Light",
                "icon": "light_mode",
                "description": "Change the scheme to light mode",
                "command": [
                    "setMode",
                    "light"
                ]
            },
            {
                "name": "Dark",
                "icon": "dark_mode",
                "description": "Change the scheme to dark mode",
                "command": [
                    "setMode",
                    "dark"
                ]
            },
            {
                "name": "Shutdown",
                "icon": "power_settings_new",
                "description": "Shutdown the system",
                "command": [
                    "poweroff"
                ],
                "dangerous": true
            },
            {
                "name": "Reboot",
                "icon": "cached",
                "description": "Reboot the system",
                "command": [
                    "reboot"
                ],
                "dangerous": true
            },
            {
                "name": "Logout",
                "icon": "exit_to_app",
                "description": "Log out of the current session",
                "command": [
                    "logout"
                ],
                "dangerous": true
            },
            {
                "name": "Lock",
                "icon": "lock",
                "description": "Lock the current session",
                "command": [
                    "loginctl",
                    "lock-session"
                ]
            },
            {
                "name": "Sleep",
                "icon": "bedtime",
                "description": "Suspend then hibernate",
                "command": [
                    "suspendThenHibernate"
                ]
            },
            {
                "name": "Settings",
                "icon": "settings",
                "description": "Configure the shell",
                "command": [
                    "caelestia",
                    "shell",
                    "nexus",
                    "open"
                ]
            },
            {
                "name": "Switch session",
                "icon": "switch_account",
                "description": "Switch to the KDE session (andrik) leaving this session active",
                "command": [
                    "bash",
                    "-c",
                    "loginctl activate $(loginctl list-sessions --no-legend | awk '$3 == \"andrik\" && $6 == \"user\" {print $1; exit}')"
                ]
            }
        ]
    },
    "utilities": {
        "quickToggles": [
            {
                "enabled": true,
                "id": "wifi"
            },
            {
                "enabled": true,
                "id": "bluetooth"
            },
            {
                "enabled": true,
                "id": "mic"
            },
            {
                "enabled": true,
                "id": "settings"
            },
            {
                "enabled": true,
                "id": "gameMode"
            },
            {
                "enabled": true,
                "id": "dnd"
            },
            {
                "enabled": true,
                "id": "vpn"
            }
        ]
    }
}
EOF

chmod 644 "$HOME/.config/caelestia/shell.json"

if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$HOME/.config/caelestia/shell.json" >/dev/null && echo "shell.json OK ($(python3 -c "import json;d=json.load(open('$HOME/.config/caelestia/shell.json'));print(len(d['launcher']['actions']),'acciones; session:',bool(d.get('session')))"))"
fi

echo "UI setup done for caelestia (shell.json with Switch session)."