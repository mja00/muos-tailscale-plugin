# Tailscale for MustardOS

MustardOS 2606.0 (Andromeda) removed the bundled Tailscale Web Service (`MustardOS/internal` commit `40996994`, 20 Oct 2026). This application brings it back as a standalone app with its own copy of the official static `tailscale`/`tailscaled` arm64 binaries, so later OS updates do not break it.

Tested on the Anbernic RG34XXSP running MustardOS 2606.0. It should work on any H700/A133 arm64 device running MustardOS.

## Install

1. Download `Tailscale.muxapp` from the [latest release](https://github.com/mja00/muos-tailscale-plugin/releases/latest).
2. Copy it to the `ARCHIVE` folder on SD1.
3. Open **Applications > Archive Manager** and install it.
4. Open **Applications > Tailscale**.

## Build

```sh
./build.sh
```

Downloads the pinned Tailscale release from `pkgs.tailscale.com`, checks its SHA-256, and writes `dist/Tailscale.muxapp`. To change the version, override both `TS_VERSION` and `TS_SHA256`.

## Use

The app opens a menu in Mustard Terminal:

| Button | Action |
|--------|--------|
| D-pad  | Move   |
| Start  | Select |
| B      | Back / exit |

- **Start Tailscale** starts the daemon.
- **Log In** shows a QR code and login URL. Scan it with your phone and approve the device; press B to cancel.
- **Start on Boot** installs `MUOS/init/tailscale.sh`, which waits up to 2 minutes for Wi-Fi before starting the daemon. This also turns on **Advanced > User Init Scripts**, because init scripts only run when it is on.
- **Disconnect**, **Log Out** and **Stop Tailscale** do what they say.

Once the daemon has started, `tailscale` is linked into `/usr/bin`, so the normal CLI works over SSH:

```sh
tailscale status
tailscale ip -4
```

## Details

- Node state lives in `MUOS/application/Tailscale/state`. If you upgraded in place from 2601 and `/opt/muos/config/tailscale` still exists, it is copied over on first start so the device keeps its identity.
- The daemon uses the kernel TUN device when available and falls back to userspace networking otherwise. In userspace mode other tailnet devices can still reach this device (SSH, SFTP, Syncthing), but outbound traffic from the device does not route through the tailnet.
- To use Headscale or another control server, put its URL on the first line of `MUOS/application/Tailscale/login_server`.
- Daemon log: `/tmp/tailscaled.log`.

## License

MIT for this project. The bundled Tailscale binaries are BSD-3-Clause; their licence ships in the app as `bin/LICENSE.tailscale`. Tailscale is a trademark of Tailscale Inc.; this project is not affiliated with Tailscale or MustardOS.
