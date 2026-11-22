#!/bin/bash
# Run as root on the Linux release builder, using the official Armbian cache.
set -Eeuo pipefail
archive=$(realpath "${1:?usage: build-armbian-rootfs.sh ARMBIAN.tar.zst KERNEL.deb OUTPUT MEDIA_BUILD}")
deb=$(realpath "${2:?}")
out=$(realpath -m "${3:?}")
media=$(realpath "${4:?}")
project=$(cd "$(dirname "$0")/.." && pwd)
root="$out/rootfs"
test ! -e "$root"
for p in \
  "$project/media/vendor-openmax/lib/libOMX.realtek.video.dec.mpeg2.so" \
  "$project/media/vendor-openmax/lib/libOMX.realtek.video.enc.avc.so" \
  "$project/media/vendor-openmax/lib/libhwse.so" \
  "$project/media/vendor-openmax/firmware/ve1.bin" \
  "$project/media/vendor-openmax/firmware/ve2.bin"; do test -e "$p"; done
mkdir -p "$root"
cleanup() { rm -rf -- "$root"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tar --xattrs --acls --numeric-owner -xpf "$archive" -C "$root"
grep -qx 'VERSION_ID="13"' "$root/etc/os-release"
# Install distribution-owned runtime dependencies inside the native arm64 root.
rm -f "$root/etc/resolv.conf"
install -m 644 /etc/resolv.conf "$root/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 755 "$root/usr/sbin/policy-rc.d"
chroot "$root" apt-get update
chroot "$root" apt-get install -y --no-install-recommends \
    adbd ca-certificates curl ffmpeg libegl1 libgles2 libgl1-mesa-dri libdrm2 \
    libatomic1 zlib1g python3 btrfs-progs openssh-server wpasupplicant systemd-resolved systemd-timesyncd \
    bluez firmware-realtek
# Resolve the actual package dependency expression, including alternatives and versions.
depends=$(dpkg-deb -f "$deb" Depends)
chroot "$root" apt-get satisfy -y --no-install-recommends "$depends"
install -m 755 "$project/image/install-huastation.sh" "$root/usr/local/sbin/install-huastation"
mv "$root/usr/bin/systemctl" "$root/usr/bin/systemctl.real"
cat > "$root/usr/bin/systemctl" <<'EOF'
#!/bin/sh
n=$#
for a in "$@"; do
  [ "$a" = "--now" ] && continue
  set -- "$@" "$a"
done
shift "$n"
exec /usr/bin/systemctl.real "$@"
EOF
chmod 755 "$root/usr/bin/systemctl"
chroot "$root" /usr/local/sbin/install-huastation
mv "$root/usr/bin/systemctl.real" "$root/usr/bin/systemctl"
rm -f "$root/usr/sbin/policy-rc.d"
# Register and unpack the kernel; configure its hardware-facing postinst on Qua.
install -d "$root/var/cache/apt/archives"
install -m 644 "$deb" "$root/var/cache/apt/archives/$(basename "$deb")"
chroot "$root" dpkg --unpack "/var/cache/apt/archives/$(basename "$deb")"
release=$(dpkg-deb -f "$deb" Package)
release=${release#linux-image-}
depmod -b "$root" "$release"
install -d "$root/opt/qua-video/openmax/lib" "$root/system/vendor/modules" "$root/etc/modules-load.d"
cp -a "$project/media/vendor-openmax/lib/." "$root/opt/qua-video/openmax/lib/"
install -m 644 "$project/media/vendor-openmax/firmware/ve1.bin" \
  "$project/media/vendor-openmax/firmware/ve2.bin" "$root/system/vendor/modules/"
for name in transcode-direct-gpubob gpu-bob.so rpc-probe.so ffmpeg-omx; do
    install -m 755 "$media/$name" "$root/opt/qua-video/openmax/"
done
install -m 755 "$project/media/qua-transcode/transcode-mirakurun-gpu.sh" "$root/opt/qua-video/openmax/"
printf 'i2c-rtk\nqua-gpu\nqua-ion\n' > "$root/etc/modules-load.d/quastation-ve.conf"
printf 'qua-rtk-hsotg\n' > "$root/etc/modules-load.d/quastation-usb.conf"
install -d "$root/lib/firmware/rtlwifi" "$root/etc/systemd/network" \
  "$root/etc/ssh/sshd_config.d" "$root/etc/wpa_supplicant" \
  "$root/etc/systemd/system/multi-user.target.wants"
install -D -m 644 "$project/image/qua-resolved.conf" "$root/etc/systemd/resolved.conf.d/qua.conf"
install -m 644 "$project"/firmware/rtlwifi/*.bin "$root/lib/firmware/rtlwifi/"
printf '%s\n' \
  'LABEL=QUA_ROOT / btrfs subvol=@,compress=zstd:3,noatime,nodiscard 0 1' \
  'tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,mode=0755,size=64M 0 0' \
  'tmpfs /tmp tmpfs defaults,nosuid,nodev,size=256M 0 0' \
  > "$root/etc/fstab"
printf 'qua\n' > "$root/etc/hostname"
printf '%s\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' \
  'PermitRootLogin prohibit-password' > "$root/etc/ssh/sshd_config.d/10-quastation.conf"
printf '[Match]\nName=wlan0\n[Link]\nActivationPolicy=up\nRequiredForOnline=no\n[Network]\nDHCP=yes\n' > "$root/etc/systemd/network/20-wlan0.network"
rm -f "$root/etc/systemd/system/multi-user.target.wants/adbd.service"
for service in systemd-networkd ssh wpa_supplicant@wlan0 huastation; do
  unit=${service/@wlan0/@}
  ln -sfn "/usr/lib/systemd/system/$unit.service" "$root/etc/systemd/system/multi-user.target.wants/$service.service"
done
install -d "$root/usr/lib/armbian" "$root/etc/systemd/system/sshd-keygen.service.d"
# The official board-independent rootfs cache has no board BSP identity.
printf '%s\n' 'BOARD=quastation' 'BOARD_NAME="KDDI Qua Station"' \
  'BOARDFAMILY=rtd1295' 'LINUXFAMILY=quastation-mainline' \
  'ARCH=arm64' 'DISTRIBUTION_CODENAME=trixie' > "$root/etc/armbian-release"
printf '[Unit]\nConditionFirstBoot=\n' > "$root/etc/systemd/system/sshd-keygen.service.d/quastation.conf"
rm -f "$root"/etc/ssh/ssh_host_* "$root/root/.ssh/authorized_keys"
: > "$root/etc/machine-id"
rm -f "$root/etc/systemd/system/basic.target.wants/armbian-resize-filesystem.service"
rm -f "$root/etc/resolv.conf"
ln -s /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
tar --xattrs --acls --numeric-owner -C "$root" -cpf - . \
  | zstd -T0 -o "$out/QuaStation-Armbian-trixie-arm64-rootfs.tar.zst"
