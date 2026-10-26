#!/bin/sh
# Controller-driven Tailscale menu that runs inside Mustard Terminal.
# muxterm sends D-pad as arrow keys, Start as carriage return and B as DEL.

APP_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SVC="$APP_DIR/tailscale.sh"
TS="$APP_DIR/bin/tailscale"
LOGIN_SERVER_FILE="$APP_DIR/login_server"

JQ="/opt/muos/bin/jq"
[ -x "$JQ" ] || JQ="jq"

ESC=$(printf '\033')
CR=$(printf '\r')
DEL=$(printf '\177')
BS=$(printf '\010')

REV="${ESC}[7m"
DIM="${ESC}[2m"
RST="${ESC}[0m"

SELECTED=1

TTY_SAVED=$(stty -g)
RESTORE_TTY() {
	stty "$TTY_SAVED"
	printf '%s[?25h' "$ESC"
}
trap 'RESTORE_TTY' EXIT
trap 'exit 0' INT TERM HUP

# -icrnl keeps Start distinguishable from a read timeout, which also yields an empty string
stty -icanon -echo -icrnl min 1 time 0
printf '%s[?25l' "$ESC"

CLEAR() {
	printf '%s[H%s[2J' "$ESC" "$ESC"
}

# Sets KEY to up, down, enter, back, none (timeout) or other
READ_KEY() {
	C=$(dd bs=1 count=1 2>/dev/null)
	case "$C" in
		"") KEY=none ;;
		"$CR" | "$(printf '\n')") KEY=enter ;;
		"$DEL" | "$BS" | q | Q) KEY=back ;;
		"$ESC")
			SEQ=$(dd bs=1 count=2 2>/dev/null)
			case "$SEQ" in
				"[A" | "OA") KEY=up ;;
				"[B" | "OB") KEY=down ;;
				*) KEY=other ;;
			esac
			;;
		*) KEY=other ;;
	esac
}

PAUSE() {
	printf '\n%sPress Start or B to return%s' "$DIM" "$RST"
	while :; do
		READ_KEY
		case "$KEY" in enter | back) return ;; esac
	done
}

REFRESH_STATUS() {
	VERSION=$("$TS" version 2>/dev/null | head -n 1)
	STATE="Daemon"
	ADDR=""
	NAME=""

	pidof tailscaled >/dev/null 2>&1 || return

	JSON=$("$TS" status --json 2>/dev/null) || return
	STATE=$(printf '%s' "$JSON" | "$JQ" -r '.BackendState // "NoState"')
	ADDR=$(printf '%s' "$JSON" | "$JQ" -r '.Self.TailscaleIPs[0] // empty')
	NAME=$(printf '%s' "$JSON" | "$JQ" -r '.Self.DNSName // empty' | sed 's/\.$//')
}

STATE_LABEL() {
	case "$STATE" in
		Daemon) printf 'Not running' ;;
		Running) printf 'Connected' ;;
		Stopped) printf 'Disconnected' ;;
		Starting | NoState) printf 'Connecting...' ;;
		NeedsLogin) printf 'Needs login' ;;
		NeedsMachineAuth) printf 'Waiting for admin approval' ;;
		*) printf '%s' "$STATE" ;;
	esac
}

# Menu entries depend on state, so they are rebuilt as "id|label" lines every redraw
BUILD_ITEMS() {
	case "$STATE" in
		Daemon) printf 'start|Start Tailscale\n' ;;
		Running | Starting)
			printf 'peers|Show Devices\n'
			printf 'down|Disconnect\n'
			;;
		# NoState is a logged-in daemon still reaching the control server; `up` nudges it to retry now
		Stopped | NoState) printf 'up|Connect\n' ;;
		*) printf 'up|Log In\n' ;;
	esac

	if [ "$STATE" != "Daemon" ]; then
		case "$STATE" in
			Running | Starting | Stopped) printf 'logout|Log Out\n' ;;
		esac
		printf 'stop|Stop Tailscale\n'
	fi

	if "$SVC" autostart; then
		printf 'boot|Start on Boot: On\n'
	else
		printf 'boot|Start on Boot: Off\n'
	fi

	printf 'exit|Exit\n'
}

DRAW() {
	CLEAR
	printf ' Tailscale %s\n\n' "${VERSION:-}"
	printf ' Status:  %s\n' "$(STATE_LABEL)"
	[ -n "$ADDR" ] && printf ' Address: %s\n' "$ADDR"
	[ -n "$NAME" ] && printf ' Name:    %s\n' "$NAME"
	printf '\n'

	i=1
	printf '%s\n' "$ITEMS" | while IFS='|' read -r _ LABEL; do
		if [ "$i" -eq "$SELECTED" ]; then
			printf ' %s> %s %s\n' "$REV" "$LABEL" "$RST"
		else
			printf '   %s\n' "$LABEL"
		fi
		i=$((i + 1))
	done

	printf '\n%sD-Pad: Move   Start: Select   B: Exit%s\n' "$DIM" "$RST"
}

ACTION_LOGIN() {
	CLEAR
	# One line only, since the QR code needs nearly every row on a 480p screen
	printf 'Requesting login...'

	set -- up --qr --qr-format=small
	if [ -s "$LOGIN_SERVER_FILE" ]; then
		set -- "$@" --login-server="$(head -n 1 "$LOGIN_SERVER_FILE" | tr -d ' \r\n')"
	fi

	"$TS" "$@" &
	UP_PID=$!

	# Poll once a second so B can cancel while `tailscale up` waits for the browser login
	stty min 0 time 10
	while kill -0 "$UP_PID" 2>/dev/null; do
		READ_KEY
		if [ "$KEY" = back ]; then
			kill "$UP_PID" 2>/dev/null
			printf '\nLogin cancelled\n'
			break
		fi
	done
	wait "$UP_PID" 2>/dev/null
	stty min 1 time 0

	PAUSE
}

ACTION_PEERS() {
	CLEAR
	"$TS" status 2>&1
	PAUSE
}

RUN_STEP() {
	CLEAR
	printf '%s\n' "$1"
	shift
	if ! OUTPUT=$("$@" 2>&1); then
		printf '\n%s\n' "$OUTPUT"
		PAUSE
	elif [ -n "$OUTPUT" ]; then
		printf '\n%s\n' "$OUTPUT"
		sleep 2
	fi
}

ACTION() {
	case "$1" in
		start) RUN_STEP "Starting Tailscale..." "$SVC" start ;;
		stop) RUN_STEP "Stopping Tailscale..." "$SVC" stop ;;
		up) ACTION_LOGIN ;;
		down) RUN_STEP "Disconnecting..." "$TS" down ;;
		logout) RUN_STEP "Logging out..." "$TS" logout ;;
		peers) ACTION_PEERS ;;
		boot)
			if "$SVC" autostart; then
				RUN_STEP "Disabling start on boot..." "$SVC" autostart off
			else
				RUN_STEP "Enabling start on boot..." "$SVC" autostart on
			fi
			;;
		exit) exit 0 ;;
	esac
}

while :; do
	REFRESH_STATUS
	ITEMS=$(BUILD_ITEMS)
	COUNT=$(printf '%s\n' "$ITEMS" | wc -l)
	[ "$SELECTED" -gt "$COUNT" ] && SELECTED=$COUNT

	DRAW
	READ_KEY

	case "$KEY" in
		up)
			SELECTED=$((SELECTED - 1))
			[ "$SELECTED" -lt 1 ] && SELECTED=$COUNT
			;;
		down)
			SELECTED=$((SELECTED + 1))
			[ "$SELECTED" -gt "$COUNT" ] && SELECTED=1
			;;
		enter) ACTION "$(printf '%s\n' "$ITEMS" | sed -n "${SELECTED}p" | cut -d'|' -f1)" ;;
		back) exit 0 ;;
	esac
done
