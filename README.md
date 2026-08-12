# ROCK 4 SE Ethernet LED Fix for Home Assistant OS

Home Assistant app for the Radxa ROCK 4 SE that applies the Ethernet PHY LED behaviour observed under Radxa Debian to Home Assistant OS.

## Confirmed hardware

- Radxa ROCK 4 SE
- Realtek RTL8211F-VD PHY
- PHY ID `0x001cc878`
- Host interface `end0`

The app refuses register writes unless the detected PHY ID is exactly `0x001cc878`.

## Confirmed register values

| Environment | LEDCR (page d04, reg 10) | EEELCR (page d04, reg 11) | Observed behaviour |
|---|---:|---:|---|
| HAOS native | `0x6251` | `0x600f` | HAOS LED mapping |
| Radxa Debian / fix | `0x2f71` | `0x6007` | Yellow steady link, green traffic activity |

These values were measured directly on the same ROCK 4 SE hardware and verified by temporarily applying the Debian values under HAOS.

## Configuration

`led_fix` is available in the Home Assistant app configuration UI.

- `true`: apply `LEDCR=0x2f71` and `EEELCR=0x6007`, and check every 60 seconds in case a PHY reset restores other values.
- `false`: restore the native values saved before the fix was first applied, if a saved native state is available; otherwise do not write any registers.

Default: `true`.

## Security / permissions

The app uses `host_network: true` so it can see `end0`, and requests only the `NET_ADMIN` capability required for the MII/MDIO write ioctls. It does not request `full_access`, `SYS_ADMIN`, or `SYS_RAWIO`.

## Install

Add this repository to the Home Assistant app store, then install **ROCK 4 SE Ethernet LED Fix**.

Repository URL:

`https://github.com/josefseger/rock4se-haos-ethernet-led-fix`

## Version history

See `rock4se_ethernet_led_fix/CHANGELOG.md`.
