#!/bin/sh
# Builds dist/Tailscale.muxapp with the official static arm64 Tailscale binaries.
set -eu

TS_VERSION="${TS_VERSION:-1.104.4}"
TS_SHA256="${TS_SHA256:-a1c249ce6bdebef62e1ae3b997595555bce2ae4709bf95a718e9ca7a129dad7e}"
TS_TARBALL="tailscale_${TS_VERSION}_arm64.tgz"
TS_URL="https://pkgs.tailscale.com/stable/$TS_TARBALL"

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
STAGE="$BUILD/stage"
DIST="$ROOT/dist"

mkdir -p "$BUILD" "$DIST"

if [ ! -f "$BUILD/$TS_TARBALL" ]; then
	curl -fL --retry 3 -o "$BUILD/$TS_TARBALL.part" "$TS_URL"
	mv "$BUILD/$TS_TARBALL.part" "$BUILD/$TS_TARBALL"
fi

if command -v sha256sum >/dev/null 2>&1; then
	ACTUAL=$(sha256sum "$BUILD/$TS_TARBALL" | cut -d' ' -f1)
else
	ACTUAL=$(shasum -a 256 "$BUILD/$TS_TARBALL" | cut -d' ' -f1)
fi

if [ "$ACTUAL" != "$TS_SHA256" ]; then
	printf 'Checksum mismatch for %s\n  expected %s\n  got      %s\n' "$TS_TARBALL" "$TS_SHA256" "$ACTUAL" >&2
	exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$ROOT/Tailscale" "$STAGE/Tailscale"
mkdir -p "$STAGE/Tailscale/bin"
tar -xzf "$BUILD/$TS_TARBALL" -C "$STAGE/Tailscale/bin" --strip-components=1 \
	"tailscale_${TS_VERSION}_arm64/tailscale" "tailscale_${TS_VERSION}_arm64/tailscaled"
chmod 755 "$STAGE/Tailscale/bin/"* "$STAGE/Tailscale/"*.sh
# BSD-3 requires the licence to travel with redistributed binaries
curl -fsSL --retry 3 -o "$STAGE/Tailscale/bin/LICENSE.tailscale" \
	"https://raw.githubusercontent.com/tailscale/tailscale/v${TS_VERSION}/LICENSE"

# Archive Manager extracts .muxapp archives straight into MUOS/application
rm -f "$DIST/Tailscale.muxapp"
(cd "$STAGE" && zip -qr -X "$DIST/Tailscale.muxapp" Tailscale)

printf 'Built %s (Tailscale %s)\n' "$DIST/Tailscale.muxapp" "$TS_VERSION"
