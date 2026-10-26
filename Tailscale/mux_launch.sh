#!/bin/sh
# HELP: Tailscale
# ICON: tailscale
# GRID: Tailscale

# shellcheck source=/dev/null
. /opt/muos/script/var/retro.sh

SETUP_APP "muxterm" ""

# -----------------------------------------------------------------------------

APP_DIR="$1"
[ -n "$APP_DIR" ] || APP_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

/opt/muos/frontend/muxterm -- sh "$APP_DIR/menu.sh"
