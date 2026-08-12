# Changelog

## 0.1.0

- Initial release.
- Add configurable `led_fix` switch.
- Apply verified Debian LED values `0x2f71` / `0x6007` on RTL8211F-VD.
- Save native values before first modification and restore them when the fix is disabled.
- Recheck every 60 seconds and reapply after PHY reinitialization.
- Refuse writes on unexpected PHY IDs.
