# ROCK 4 SE Ethernet LED Fix

This app changes only two RTL8211F-VD PHY LED registers on a verified Radxa ROCK 4 SE Ethernet PHY.

## Option: `led_fix`

When enabled, the app applies:

- RTL8211F page `0xd04`, register `0x10` (LEDCR): `0x2f71`
- RTL8211F page `0xd04`, register `0x11` (EEELCR): `0x6007`

This produces the tested Debian-style LED behaviour: yellow steady link indication and green network activity indication.

When disabled, the app attempts to restore the native values it saved before first applying the fix. If no native state is available, it leaves the PHY registers unchanged.

After changing the option, restart the app so the new setting takes effect.

## Safety checks

The app will refuse writes unless:

- interface `end0` exists;
- MII access succeeds; and
- PHY ID is exactly `0x001cc878` (RTL8211F-VD as measured on the tested ROCK 4 SE).

The PHY page-select register is restored after every operation.
