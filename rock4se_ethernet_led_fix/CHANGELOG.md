# Changelog

## 0.1.1

- Fix disabling the app when the first app start happened after manual PHY testing had already applied the Debian LED values.
- If no saved native state exists, disabling now restores the experimentally verified HAOS defaults `0x6251` / `0x600f`.
- Verify the native register values after restore.
- Never overwrite an already captured native state.
- Add clearer log messages for already-active and restored configurations.

## 0.1.0

- Initial release.
- Add configurable `led_fix` switch.
- Apply verified Debian LED values `0x2f71` / `0x6007` on RTL8211F-VD.
- Save native values before first modification and restore them when the fix is disabled.
- Recheck every 60 seconds and reapply after PHY reinitialization.
- Refuse writes on unexpected PHY IDs.
