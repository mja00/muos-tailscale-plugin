#!/bin/sh
# Controls the bundled Tailscale daemon, mirroring the service script MustardOS shipped before 2606.0.

APP_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

TS_DAEMON="$APP_DIR/bin/tailscaled"
TS_CLI="$APP_DIR/bin/tailscale"
TS_STATEDIR="$APP_DIR/state"
TS_LEGACY_STATEDIR="/opt/muos/config/tailscale"
# The CLI defaults to this socket, so a plain `tailscale` over SSH reaches the daemon without flags
TS_RUNDIR="/var/run/tailscale"
TS_SOCKET="$TS_RUNDIR/tailscaled.sock"
TS_LOG="/tmp/tailscaled.log"
TS_CLI_LINK="/usr/bin/tailscale"

INIT_SCRIPT="/run/muos/storage/init/tailscale.sh"

TS_PIDS() {
	pidof tailscaled 2>/dev/null
}

TS_RUNNING() {
	[ -n "$(TS_PIDS)" ]
}

# Users upgrading in place from 2601 keep their old node identity instead of re-authenticating
MIGRATE_LEGACY_STATE() {
	if [ ! -f "$TS_STATEDIR/tailscaled.state" ] && [ -f "$TS_LEGACY_STATEDIR/tailscaled.state" ]; then
		cp -a "$TS_LEGACY_STATEDIR/." "$TS_STATEDIR/"
	fi
}

TUN_MODE() {
	if [ ! -c /dev/net/tun ]; then
		modprobe tun >/dev/null 2>&1
	fi

	if [ -c /dev/net/tun ]; then
		printf 'tailscale0'
	else
		printf 'userspace-networking'
	fi
}

START() {
	TS_RUNNING && return 0

	mkdir -p "$TS_STATEDIR" "$TS_RUNDIR"
	MIGRATE_LEGACY_STATE
	rm -f "$TS_SOCKET"

	# setsid keeps the daemon alive when the terminal that launched it closes its session
	setsid "$TS_DAEMON" \
		--statedir="$TS_STATEDIR" \
		--socket="$TS_SOCKET" \
		--tun="$(TUN_MODE)" \
		>"$TS_LOG" 2>&1 </dev/null &

	i=0
	while [ ! -S "$TS_SOCKET" ] && [ "$i" -lt 20 ]; do
		sleep 0.5
		i=$((i + 1))
	done

	ln -sf "$TS_CLI" "$TS_CLI_LINK" 2>/dev/null

	[ -S "$TS_SOCKET" ]
}

STOP() {
	PIDS=$(TS_PIDS)
	[ -n "$PIDS" ] || return 0

	# shellcheck disable=SC2086
	kill $PIDS 2>/dev/null

	i=0
	while TS_RUNNING && [ "$i" -lt 20 ]; do
		sleep 0.25
		i=$((i + 1))
	done

	if TS_RUNNING; then
		# shellcheck disable=SC2046
		kill -9 $(TS_PIDS) 2>/dev/null
	fi

	rm -f "$TS_SOCKET"
}

AUTOSTART_ENABLED() {
	[ -f "$INIT_SCRIPT" ]
}

# Starting before Wi-Fi has IPv4 leaves tailscaled stuck in backoff after failed logins, so boot waits up to 2 minutes
BOOT() {
	i=0
	while ! ip -4 route show default | grep -q . && [ "$i" -lt 120 ]; do
		sleep 1
		i=$((i + 1))
	done

	START
}

AUTOSTART_ON() {
	mkdir -p "$(dirname "$INIT_SCRIPT")" || return 1
	printf '#!/bin/sh\n# Installed by the Tailscale application\n"%s/tailscale.sh" boot\n' "$APP_DIR" >"$INIT_SCRIPT" || return 1

	# Init scripts only run when this advanced setting is on
	# shellcheck source=/dev/null
	. /opt/muos/script/var/config.sh
	if [ "$(GET_VAR "config" "settings/advanced/user_init")" != "1" ]; then
		SET_VAR "config" "settings/advanced/user_init" "1"
		printf 'Enabled Advanced > User Init Scripts\n'
	fi
}

AUTOSTART_OFF() {
	rm -f "$INIT_SCRIPT"
}

case "$1" in
	start) START ;;
	stop) STOP ;;
	boot) BOOT ;;
	restart)
		STOP
		START
		;;
	autostart)
		case "$2" in
			on) AUTOSTART_ON ;;
			off) AUTOSTART_OFF ;;
			*) AUTOSTART_ENABLED ;;
		esac
		;;
	*)
		printf 'Usage: %s {start|stop|boot|restart|autostart [on|off]}\n' "$0" >&2
		exit 1
		;;
esac
