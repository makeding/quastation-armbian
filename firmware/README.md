# Required device firmware

Install the contents below into `/lib/firmware/` on the root filesystem,
preserving the relative directory names.

| File | Device | Source |
|---|---|---|
| `rtlwifi/rtl8192eefw.bin` | Qua Station RTL8192EE PCIe Wi-Fi | Debian `firmware-realtek_20250410-2_all.deb`, retained builder package |
| `rtl_bt/rtl8761a_fw.bin` | Qua Station RTL8761ATV UART Bluetooth | Debian `firmware-realtek_20250410-2_all.deb` |
| `rtlwifi/rtl8812aefw.bin`, `rtlwifi/rtl8812aefw_wowlan.bin` | Second RTL8812AE radio, presently disabled in accepted DTS | Same Debian firmware-realtek package |
| `regulatory.db`, `regulatory.db.p7s` | Signed wireless regulatory database | Debian `wireless-regdb_2026.05.30-1~deb13u1_all.deb` |

The binary was restored to the live Debian root after removal of
`armbian-firmware-full`. The RTL8192EE driver successfully loaded it during
the USB candidate boot. Only required firmware is carried here.

These five files are the exact `CONFIG_EXTRA_FIRMWARE` build inputs in the
accepted full config. The second-radio binaries remain here to reproduce that
config; this does not enable that radio. The accepted kernel already embeds
these inputs, so removal of the rootfs firmware package alone does not prove
that the current kernel would lose Wi-Fi. The restored rootfs binary also
supports future kernels that load firmware from disk.

When building from this standalone project, override the old builder-specific
firmware directory with the absolute path of this `firmware/` directory:

```sh
scripts/config --file out/.config --set-str EXTRA_FIRMWARE_DIR /absolute/path/to/qua-kernel/firmware
```

Verify with `shasum -a 256 -c SHA256SUMS` from this directory.
The original package copyright/license metadata is retained verbatim as
`COPYRIGHT.firmware-realtek`; the `rtlwifi/*` stanza identifies the applicable
`binary-redist-Realtek-restrictive` license.
Regulatory database licensing is retained as `COPYRIGHT.wireless-regdb`.
