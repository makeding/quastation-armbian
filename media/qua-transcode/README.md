# Qua Station hardware transcoding

This directory contains the tested MPEG-2 -> H.264 path, its Panfrost
one-field NV12 deinterlacer, and the FFmpeg 4.4.5 NV12 patch. The pipeline is
an OpenMAX application linked to FFmpeg libraries; it is not an FFmpeg
hardware decoder or a standard FFmpeg deinterlace filter. `ffmpeg-omx` is the
separately built FFmpeg CLI with the Realtek NV12 `h264_omx` encoder patch.

The decoder and encoder share ION DMA-BUFs directly with the GPU. The shader
keeps one field and interpolates missing lines, producing 29.97 progressive
frames/s from 29.97 interlaced frames/s. It does not provide 59.94 fps or
motion-adaptive deinterlacing. `rpc-probe.c` bypasses the vendor RPC bootstrap
for this experimental video path; it does not implement the vendor RPC stack.

## Build and install on an arm64 Linux system

The build requires FFmpeg 4.4.5's official source archive (SHA256
`f9514e0d3515aee5a271283df71636e1d1ff7274b15853bcd84e144be416ab07`),
`gcc`, `make`, `patch`, xz, zlib development files, EGL/GLES development
headers, and libdrm headers.
Pass a new build output directory; the script extracts and retains the FFmpeg
source there, applies the NV12 patch, and builds the four runtime artifacts.

```sh
./media/qua-transcode/build.sh /path/to/ffmpeg-4.4.5.tar.xz /absolute/build-output
sudo ./media/qua-transcode/install.sh /absolute/build-output
```

The Realtek OpenMAX `.so` runtime and VE1/VE2 firmware must be supplied locally
in `media/vendor-openmax/lib` and `media/vendor-openmax/firmware`; run
`media/vendor-openmax/fetch-libraries.sh` to retrieve and verify the pinned
vendor files and restore the codec soname links. These vendor binaries are
intentionally excluded from this repository because their redistribution terms
were not included with the vendor bundle. `SHA256SUMS` records their expected
hashes. Installation places the runtime under `/opt/qua-video/openmax` and the
firmware at `/system/vendor/modules/ve1.bin` and `/system/vendor/modules/ve2.bin`,
the absolute paths opened by the Realtek decoder and encoder libraries.
The wrapper also needs the system `/usr/bin/ffmpeg` with the `h264_metadata`
bitstream filter. `/dev/vpu`, `/dev/ion` and the Panfrost render node must be
available.

The project source was rebuilt natively on Qua and installed on
`7.3.4-qua-proj1`. The rebuilt `ffmpeg-omx` reported NV12 support and encoded
30 frames using `h264_omx`; the rebuilt complete GPU pipeline produced the
ten-second Mirakurun test below with 300 H.264 packets and AAC.

## Test the known 1440x1080 NHK service

On the computer connected by **USB ADB**, from the workspace containing this
repository:

```sh
bash media/qua-transcode/test-local-usb.sh
```

The helper uses the existing `jp-noa` SSH connection and local ADB reverse to
transport HTTP over USB; it removes the tunnel on exit. The result is
`/root/mirakurun-test.ts` on Qua. It is specific to the recorded
`192.168.7.254:40772` service, local SSH key, and QuaStation ADB serial. Set
`QUA_DURATION=30` to run 30 seconds. The wrapper defaults to top-field-first,
SAR 4:3 and BT.709 for this specific 16:9 NHK stream; use `QUA_DEINTERLACE=bob-bff`
for a bottom-field-first source and do not reuse the hardcoded color/aspect
settings blindly for other channels.

On `7.3.4-qua-proj1`, the actual USB-forwarded 30-second Mirakurun test
produced 900 progressive H.264 frames and AAC, with a 1.067x processing-phase
measurement. The start phase includes input buffering, so this is not an
unrestricted throughput benchmark or an indefinite stability guarantee.
Direct Wi-Fi with the original WMM-disabled AP produced only 639 frames in a
30-second test and measured 0.674x; the bottleneck remains on that input path.
The original AP settings were restored after the temporary WMM test.
