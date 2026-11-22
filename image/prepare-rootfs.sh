#!/bin/bash
# Assemble the public Qua userspace in an extracted official Armbian rootfs.
set -Eeuo pipefail
if [[ $# != 3 ]]; then
    echo "usage: $0 ROOTFS KERNEL_BUNDLE MEDIA_BUILD" >&2
    exit 2
fi
root=$(realpath "$1"); kernel=$(realpath "$2"); media=$(realpath "$3")
project=$(cd "$(dirname "$0")/.." && pwd)
[[ "$root" != / && -f "$root/etc/armbian-release" && -f "$root/var/lib/dpkg/status" ]]
for p in \
    "$project/media/vendor-openmax/lib/libOMX.realtek.video.dec.mpeg2.so" \
    "$project/media/vendor-openmax/lib/libOMX.realtek.video.enc.avc.so" \
    "$project/media/vendor-openmax/lib/libhwse.so" \
    "$project/media/vendor-openmax/firmware/ve1.bin" \
    "$project/media/vendor-openmax/firmware/ve2.bin"; do test -e "$p"; done
[[ ! -e "$root/root/.ssh/authorized_keys" && ! -e "$root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" ]] || {
    echo 'Refusing a rootfs containing device-specific credentials' >&2; exit 1;
}
release=$(cat "$kernel/kernelrelease")
[[ "$release" =~ ^7\.3\.4-qua-[a-zA-Z0-9._-]+$ ]]
for p in Image Image-legacy-uboot.gz board.dtb kernel-modules.tar.gz; do test -s "$kernel/$p"; done
for p in transcode-direct-gpubob gpu-bob.so rpc-probe.so ffmpeg-omx; do test -s "$media/$p"; done

if grep -q '^Package: linux-image-current-arm64$' "$root/var/lib/dpkg/status"; then
    python3 "$project/image/purge-uefi-package-state.py" "$root"
else
    for package in armbian-bsp-cli-uefi-arm64-current-grub linux-dtb-current-arm64 linux-image-current-arm64; do
        if grep -qx "Package: $package" "$root/var/lib/dpkg/status"; then
            echo "Inconsistent UEFI package state: $package" >&2; exit 1
        fi
    done
fi
# These paths belong to the verified UEFI-arm64 6.18.45 source image only.
for p in usr/lib/modules/6.18.45-current-arm64 usr/lib/linux-image-6.18.45-current-arm64; do
    [[ ! -e "$root/$p" ]] || rm -rf -- "$root/$p"
done
for p in Image config-6.18.45-current-arm64 initrd.img-6.18.45-current-arm64 \
         System.map-6.18.45-current-arm64 vmlinuz-6.18.45-current-arm64; do
    [[ ! -e "$root/boot/$p" && ! -L "$root/boot/$p" ]] || rm -- "$root/boot/$p"
done
install -m 644 "$kernel/Image" "$root/boot/Image"
install -m 644 "$kernel/Image-legacy-uboot.gz" "$root/boot/Image-legacy-uboot.gz"
install -m 644 "$kernel/board.dtb" "$root/boot/rtd1295-quastation.dtb"
tar -C "$root/lib/modules" -xzf "$kernel/kernel-modules.tar.gz"
install -d "$root/lib/firmware/rtlwifi"
for name in rtl8192eefw.bin rtl8812aefw.bin rtl8812aefw_wowlan.bin; do
    [[ ! -L "$root/lib/firmware/rtlwifi/$name" ]] || rm -- "$root/lib/firmware/rtlwifi/$name"
    install -m 644 "$project/firmware/rtlwifi/$name" "$root/lib/firmware/rtlwifi/$name"
done

install -d "$root/opt/qua-video/openmax/lib" "$root/system/vendor/modules" "$root/etc/modules-load.d" \
    "$root/etc/systemd/system/sshd-keygen.service.d" "$root/etc/ssh/sshd_config.d" "$root/etc/systemd/network" \
    "$root/etc/systemd/system/wpa_supplicant@wlan0.service.d"
install -D -m 644 "$project/image/qua-resolved.conf" "$root/etc/systemd/resolved.conf.d/qua.conf"
cp -a "$project/media/vendor-openmax/lib/." "$root/opt/qua-video/openmax/lib/"
install -m 644 "$project/media/vendor-openmax/firmware/ve1.bin" \
    "$project/media/vendor-openmax/firmware/ve2.bin" "$root/system/vendor/modules/"
install -m 755 "$media/transcode-direct-gpubob" "$media/gpu-bob.so" \
    "$media/rpc-probe.so" "$media/ffmpeg-omx" "$root/opt/qua-video/openmax/"
install -m 755 "$project/media/qua-transcode/transcode-mirakurun-gpu.sh" "$root/opt/qua-video/openmax/"
printf '%s\n' i2c-rtk qua-gpu qua-ion > "$root/etc/modules-load.d/quastation-ve.conf"
printf '%s\n' qua > "$root/etc/hostname"
printf '%s\n' 'LABEL=QUA_ROOT / btrfs subvol=@,compress=zstd:3,noatime,nodiscard 0 1' > "$root/etc/fstab"
install -d "$root/usr/lib/armbian"
if [[ ! -e "$root/usr/lib/armbian/armbian-release.upstream-uefi-arm64" ]]; then
    cp -p "$root/etc/armbian-release" "$root/usr/lib/armbian/armbian-release.upstream-uefi-arm64"
fi
sed -i -e 's/^BOARD=.*/BOARD=quastation/' -e 's/^BOARD_NAME=.*/BOARD_NAME="KDDI Qua Station"/' \
    -e 's/^BOARDFAMILY=.*/BOARDFAMILY=rtd1295/' -e 's/^BOOT_SOC=.*/BOOT_SOC=RTD1295/' \
    -e 's/^LINUXFAMILY=.*/LINUXFAMILY=quastation-mainline/' "$root/etc/armbian-release"
: > "$root/etc/machine-id"
for p in "$root"/etc/ssh/ssh_host_*; do [[ ! -e "$p" && ! -L "$p" ]] || rm -- "$p"; done
cat > "$root/etc/systemd/system/sshd-keygen.service.d/quastation.conf" <<'EOF'
[Unit]
ConditionFirstBoot=
EOF
cat > "$root/etc/ssh/sshd_config.d/10-quastation.conf" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
cat > "$root/etc/systemd/network/20-wlan0.network" <<'EOF'
[Match]
Name=wlan0
[Link]
ActivationPolicy=manual
RequiredForOnline=no
[Network]
DHCP=yes
EOF
cat > "$root/etc/systemd/system/wpa_supplicant@wlan0.service.d/quastation.conf" <<'EOF'
[Service]
ExecStartPre=/bin/sleep 30
ExecStartPre=/usr/sbin/ip link set dev wlan0 up
EOF
ln -sfn /usr/lib/systemd/system/wpa_supplicant@.service \
    "$root/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service"
# Debian's default adbd listens on TCP port 5555; HuaStation owns USB ADB.
p="$root/etc/systemd/system/multi-user.target.wants/adbd.service"
[[ ! -L "$p" ]] || rm -- "$p"
install -m 755 "$project/image/qua-usb-adbd.sh" "$root/usr/local/sbin/qua-usb-adbd"
# The board layout preserves an extended partition after the root filesystem.
p="$root/etc/systemd/system/basic.target.wants/armbian-resize-filesystem.service"
[[ ! -L "$p" ]] || rm -- "$p"
echo "PUBLIC_ROOTFS_ASSEMBLED kernel=$release"
