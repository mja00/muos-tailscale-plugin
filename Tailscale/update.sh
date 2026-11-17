#!/bin/sh
# Checks GitHub for a newer release of this app and installs it in place.
# check: exit 0 and record the tag if newer, 1 if up to date, 2 on error. install: update if newer.

APP_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO="mja00/muos-tailscale-plugin"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
DOWNLOAD_URL="https://github.com/$REPO/releases/download"
LATEST_FILE="/tmp/tailscale-app-latest"

JQ="/opt/muos/bin/jq"
[ -x "$JQ" ] || JQ="jq"

CURRENT=$(cat "$APP_DIR/VERSION" 2>/dev/null)

FETCH() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 2 --connect-timeout 10 -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -T 10 -O "$2" "$1"
	else
		printf 'Neither curl nor wget is available\n' >&2
		return 1
	fi
}

# BusyBox sort may be built without -V
NEWER() {
	printf '%s %s\n' "${1#v}" "${2#v}" | awk '{
		n = split($1, a, "."); m = split($2, b, ".")
		for (i = 1; i <= (n > m ? n : m); i++) {
			if (a[i] + 0 > b[i] + 0) exit 0
			if (a[i] + 0 < b[i] + 0) exit 1
		}
		exit 1
	}'
}

CHECK() {
	rm -f "$LATEST_FILE"

	# Test builds from PRs are not releases, and "updating" them could install an older version
	case "$CURRENT" in
		v[0-9]*) ;;
		*)
			printf 'This is a test build (%s), so it does not update itself\n' "${CURRENT:-unknown}" >&2
			return 1
			;;
	esac

	JSON=$(mktemp) || return 2
	if ! FETCH "$API_URL" "$JSON"; then
		rm -f "$JSON"
		printf 'Could not reach GitHub. Check the Wi-Fi connection.\n' >&2
		return 2
	fi
	LATEST=$("$JQ" -r '.tag_name // empty' "$JSON" 2>/dev/null)
	rm -f "$JSON"

	case "$LATEST" in
		v[0-9]*) ;;
		*)
			printf 'Unexpected release tag "%s"\n' "$LATEST" >&2
			return 2
			;;
	esac
	case "$LATEST" in *[!v0-9.]*)
		printf 'Unexpected release tag "%s"\n' "$LATEST" >&2
		return 2
		;;
	esac

	NEWER "$LATEST" "$CURRENT" || return 1
	printf '%s\n' "$LATEST" >"$LATEST_FILE"
	printf '%s\n' "$LATEST"
}

INSTALL() {
	CHECK >/dev/null
	case $? in
		1)
			printf 'Already up to date (%s)\n' "${CURRENT:-unknown}"
			return 0
			;;
		2) return 1 ;;
	esac
	LATEST=$(cat "$LATEST_FILE")

	# Staging next to the app keeps the final swap a rename on the same filesystem
	PARENT=$(dirname "$APP_DIR")
	NEW="$PARENT/.Tailscale.new"
	OLD="$PARENT/.Tailscale.old"
	WORK=$(mktemp -d) || return 1
	rm -rf "$NEW" "$OLD"

	printf 'Downloading %s...\n' "$LATEST"
	if ! FETCH "$DOWNLOAD_URL/$LATEST/Tailscale.muxapp" "$WORK/app.zip" ||
		! FETCH "$DOWNLOAD_URL/$LATEST/Tailscale.muxapp.sha256" "$WORK/app.sha256"; then
		rm -rf "$WORK"
		printf 'Download failed\n'
		return 1
	fi

	EXPECTED=$(cut -d' ' -f1 <"$WORK/app.sha256")
	ACTUAL=$(sha256sum "$WORK/app.zip" | cut -d' ' -f1)
	if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
		rm -rf "$WORK"
		printf 'Checksum mismatch, update cancelled\n'
		return 1
	fi

	mkdir -p "$NEW"
	if ! unzip -q "$WORK/app.zip" -d "$NEW" || [ ! -x "$NEW/Tailscale/tailscale.sh" ] || [ ! -x "$NEW/Tailscale/bin/tailscaled" ]; then
		rm -rf "$WORK" "$NEW"
		printf 'Could not unpack the update\n'
		return 1
	fi
	rm -rf "$WORK"

	printf 'Installing...\n'
	WAS_RUNNING=""
	if pidof tailscaled >/dev/null 2>&1; then
		WAS_RUNNING=1
		"$APP_DIR/tailscale.sh" stop
	fi

	# Login state and the custom control server survive the update
	for KEEP in state login_server; do
		[ -e "$APP_DIR/$KEEP" ] && mv "$APP_DIR/$KEEP" "$NEW/Tailscale/$KEEP"
	done

	if mv "$APP_DIR" "$OLD" && mv "$NEW/Tailscale" "$APP_DIR"; then
		rm -rf "$OLD" "$NEW"
	else
		[ -d "$OLD" ] && [ ! -e "$APP_DIR" ] && mv "$OLD" "$APP_DIR"
		for KEEP in state login_server; do
			[ -e "$NEW/Tailscale/$KEEP" ] && mv "$NEW/Tailscale/$KEEP" "$APP_DIR/$KEEP"
		done
		rm -rf "$NEW"
		printf 'Could not replace the app, kept %s\n' "$CURRENT"
		[ -n "$WAS_RUNNING" ] && "$APP_DIR/tailscale.sh" start
		return 1
	fi

	rm -f "$LATEST_FILE"
	[ -n "$WAS_RUNNING" ] && "$APP_DIR/tailscale.sh" start
	printf 'Updated to %s\n' "$LATEST"
}

case "$1" in
	check) CHECK ;;
	install) INSTALL ;;
	*)
		printf 'Usage: %s {check|install}\n' "$0" >&2
		exit 1
		;;
esac
