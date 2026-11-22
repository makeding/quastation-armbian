#!/bin/sh
set -eu

tree=$(CDPATH= cd -- "$1" && pwd)
out=$(CDPATH= cd -- "$2" && pwd)
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pkg_dir=$(dirname "$out")
rm -f "$pkg_dir"/linux-image-*_arm64.deb \
	"$pkg_dir"/linux-headers-*_arm64.deb \
	"$pkg_dir"/linux-libc-dev_*_arm64.deb \
	"$pkg_dir"/linux-upstream_*
make -C "$tree" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}" O="$out" -j"$(nproc)" bindeb-pkg

release=$(cat "$out/include/config/kernel.release")
image_root="$out/debian/linux-image-$release"
modules=$(find "$out/qua-modules" -type f -name '*.ko' -print)
[ -d "$image_root/lib/modules/$release" ]
[ -n "$modules" ]
printf '%s\n' "$modules" | while IFS= read -r module; do
	relative=${module#"$out/qua-modules/"}
	install -D -m 0644 "$module" "$image_root/lib/modules/$release/extra/qua/$relative"
done
depmod -b "$image_root" "$release"

boot_tools="$image_root/usr/lib/qua-kernel"
install -d "$image_root/boot" "$boot_tools"
install -m 0644 "$out/Image-legacy-uboot.gz" "$image_root/boot/Image-legacy-uboot.gz"
install -m 0644 "$out/rtd1295-quastation.dtb" "$image_root/boot/rtd1295-quastation.dtb"
maintenance_uimage="$(dirname "$out")/QuaStation-maintenance-initramfs.uImage"
if [ -s "$maintenance_uimage" ]; then
	initrd_capacity=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["slots"]["initrd"]["sectors"] * d["sector_bytes"])' "$root/image/boot-slot-layout.json")
	initrd_size=$(wc -c < "$maintenance_uimage")
	[ "$initrd_size" -le "$initrd_capacity" ]
	install -m 0644 "$maintenance_uimage" "$image_root/boot/QuaStation-maintenance-initramfs.uImage"
fi
install -m 0644 "$out/rescue-profile.json" "$boot_tools/rescue-profile.json"
install -m 0644 "$out/kernel-slot.bin" "$boot_tools/kernel-slot.bin"
install -m 0644 "$out/dtb-slot.bin" "$boot_tools/dtb-slot.bin"
install -m 0644 "$root/image/boot-slot-layout.json" "$boot_tools/boot-slot-layout.json"
install -m 0644 "$root/image/quastation-layout.mbr" "$boot_tools/quastation-layout.mbr"
install -m 0644 "$root/image/write-boot-slots.py" "$boot_tools/write-boot-slots.py"
install -m 0755 "$root/image/install-package-kernel-slots.py" \
	"$boot_tools/install-package-kernel-slots.py"
install -D -m 0755 "$root/image/qua-usb-adbd.sh" \
	"$image_root/usr/local/sbin/qua-usb-adbd"

control="$image_root/DEBIAN/control"
if grep -q '^Depends:' "$control"; then
	sed -i '/^Depends:/s/$/, python3, util-linux, systemd, bluez, firmware-realtek/' "$control"
else
	printf '%s\n' 'Depends: python3, util-linux, systemd, bluez, firmware-realtek' >> "$control"
fi
size_kib=$(du -sk "$image_root" | cut -f1)
sed -i "s/^Installed-Size:.*/Installed-Size: $size_kib/" "$control"

postinst="$image_root/DEBIAN/postinst"
[ -f "$postinst" ]
tail -n 1 "$postinst" | grep -qx 'exit 0'
sed -i '$d' "$postinst"
cat >> "$postinst" <<'POSTINST'
if [ "$1" = configure ]; then
	/usr/bin/python3 /usr/lib/qua-kernel/install-package-kernel-slots.py
	/bin/systemctl daemon-reload
fi
exit 0
POSTINST
chmod 0755 "$postinst"

version=$(sed -n 's/^Version: //p' "$image_root/DEBIAN/control")
[ -n "$version" ]
image_deb="$(dirname "$out")/linux-image-${release}_${version}_arm64.deb"
[ -f "$image_deb" ]
rebuilt_deb="${image_deb%.deb}.rebuilt.deb"
trap 'rm -f "$rebuilt_deb"' EXIT HUP INT TERM
dpkg-deb --build --root-owner-group "$image_root" "$rebuilt_deb"
mv -f "$rebuilt_deb" "$image_deb"
trap - EXIT HUP INT TERM
