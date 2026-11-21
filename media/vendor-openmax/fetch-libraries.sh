#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
mkdir -p lib firmware
base=https://raw.githubusercontent.com/tsukumijima/QuaStation-Kernel/041115133e6babea21a0e75519648afeb023b7ac/prebuilt/openmax/usr/lib
firmware_base=https://raw.githubusercontent.com/tsukumijima/QuaStation-Kernel/041115133e6babea21a0e75519648afeb023b7ac/prebuilt/openmax/system/vendor/modules
while read -r hash path; do
    case "$path" in
        lib/*) curl -fL "$base/${path#lib/}" -o "$path" ;;
        firmware/*) curl -fL "$firmware_base/${path#firmware/}" -o "$path" ;;
    esac
done < SHA256SUMS
sha256sum -c SHA256SUMS

for codec in aac ac3 adpcm amrnb amrwb eac3 flac g711alaw g711mulaw mp3 pcm raw vorbis wmapro; do
    ln -sfn libOMX.realtek.audio.dec.so "lib/libOMX.realtek.audio.dec.$codec.so"
done
for codec in 3gpp avc avs divx3 flv h263 hevc mjpg mp43 mpeg2 mpeg4 raw rv rv30 rv40 vc1 vp8 wmv wmv3 wvc1; do
    ln -sfn libOMX.realtek.video.dec.so "lib/libOMX.realtek.video.dec.$codec.so"
done
for codec in avc mpeg4; do
    ln -sfn libOMX.realtek.video.enc.so "lib/libOMX.realtek.video.enc.$codec.so"
done
ln -sfn libhwse_kylin.so lib/libhwse.so
