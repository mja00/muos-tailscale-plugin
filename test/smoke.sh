#!/bin/sh
# Installs dist/Tailscale.muxapp into a temp dir and drives the daemon and menu the way the device does.
# Needs root, arm64 Linux, network access, jq, unzip and util-linux `script`.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TS_VERSION=$(sed -n 's/^TS_VERSION=.*:-\([^}]*\)}.*/\1/p' "$ROOT/build.sh")
WORK=$(mktemp -d)
APP="$WORK/Tailscale"
MENU_LOG="$WORK/menu.log"

FAIL() {
	printf 'FAIL: %s\n' "$1" >&2
	[ -f /tmp/tailscaled.log ] && sed 's/^/  tailscaled: /' /tmp/tailscaled.log >&2
	exit 1
}

CLEANUP() {
	"$APP/tailscale.sh" stop >/dev/null 2>&1 || true
	rm -rf "$WORK"
}
trap CLEANUP EXIT

unzip -q "$ROOT/dist/Tailscale.muxapp" -d "$WORK"

for f in tailscale.sh menu.sh mux_launch.sh bin/tailscale bin/tailscaled; do
	[ -x "$APP/$f" ] || FAIL "$f missing or not executable in the archive"
done

ACTUAL_VERSION=$("$APP/bin/tailscale" version | head -n 1)
[ "$ACTUAL_VERSION" = "$TS_VERSION" ] || FAIL "tailscale version is $ACTUAL_VERSION, expected $TS_VERSION"
printf 'ok: bundled tailscale %s\n' "$ACTUAL_VERSION"

"$APP/tailscale.sh" start || FAIL "tailscale.sh start did not create the socket"
pidof tailscaled >/dev/null || FAIL "tailscaled is not running"
[ "$(readlink /usr/bin/tailscale)" = "$APP/bin/tailscale" ] || FAIL "/usr/bin/tailscale is not linked to the bundled CLI"
printf 'ok: daemon started\n'

# The menu reads these fields, so a renamed one would silently show the wrong status
STATE=$(tailscale status --json | jq -r '.BackendState')
[ "$STATE" = "NeedsLogin" ] || FAIL "fresh daemon BackendState is $STATE, expected NeedsLogin"
tailscale status --json | jq -e 'has("Self")' >/dev/null || FAIL "status --json has no Self"
printf 'ok: status --json reports NeedsLogin\n'

# Start opens Log In, B cancels it, B leaves the pause screen, B exits the menu
{
	sleep 3
	printf '\r'
	sleep 15
	printf '\177'
	sleep 3
	printf '\177'
	sleep 2
	printf '\177'
	sleep 2
} | timeout 60 script -qfec "sh '$APP/menu.sh'" "$MENU_LOG" >/dev/null || FAIL "menu did not exit cleanly"

# Strip ANSI sequences so the checks match the visible text
TEXT=$(sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$MENU_LOG")
for want in "Tailscale $TS_VERSION" "Status:  Needs login" "Log In" "Login cancelled"; do
	printf '%s' "$TEXT" | grep -qF "$want" || FAIL "menu output is missing \"$want\""
done
printf '%s' "$TEXT" | grep -qE 'https://login\.tailscale\.com/a/[0-9A-Za-z]+' || FAIL "Log In did not print a login URL"
printf 'ok: menu shows status, login URL and cancels\n'

"$APP/tailscale.sh" stop
pidof tailscaled >/dev/null && FAIL "tailscaled still running after stop"
printf 'ok: daemon stopped\n'
