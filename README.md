# quastation-armbian

## 1. プロジェクト概要

KDDI Qua Station（Realtek RTD1295 / ARM64）向けの Linux 7.3.4 メインラインベースカーネル、デバイスツリー、アウトオブツリーモジュール、および Armbian（Debian 13 / Trixie）rootfs・USB ADB 導入ツールを提供するリポジトリです。

純正 Realtek ブートチェーンおよび個体固有の factory 環境を保持したまま、eMMC のルートパーティションに Armbian を導入・運用する構成をとります。汎用 Armbian イメージ、GRUB、`armbian-install` によるブート構成の置き換えは行いません。

主な構成要素:

- `kernel/`・`patches/`・`dts/rtd1295-quastation.dts`: Linux 7.3.4 向けパッチ群、Qua Station 固有ドライバー、ボード DTS
- `modules/`: Mali-T820 GPU 初期化、VE1 ハードウェア動画エンジン、ION メモリアロケーター
- `image/`: RAM メンテナンス initramfs（`QuaMaintenance` USB ADB）、個体別バンドル生成、USB 経由インストーラー、ブートスロットライター
- `media/qua-transcode/`: MPEG-2 → H.264 ハードウェアトランスコードパイプラインおよび FFmpeg 4.4.5 NV12 パッチ

## 2. 適応状況

RAM は `0x00000000..0x7fffffff` の 2 GiB を宣言します。低位 512 MiB
全体を除外せず、U-Boot が FDT に残す起動コード・音声ファームウェアの
予約、RPC/TEE、ACPU IDMEM (`0x10000000..0x10013fff`) とリセットコード
(`0x1fc00000..0x1fc00fff`) を保持します。GPU/VE/ION は既存の 128 MiB
CMA を使用し、旧 BSP の固定 ION ヒープを新たに割り当てません。
受け入れ確認は再起動後の RAM マップ、MemTotal、CMA、四 CPU、USB ADB、
および既存 GPU/VE デバイスで行います。

### v-7.3.4-7：既存環境の四 CPU 有効化

2 GiB の RAM 宣言と四 CPU を有効にした構成は実機で確認済みです。
Linux の MemTotal は約 1.86 GiB で、1.5 GiB の読み書きと ION DMA
割り当てを確認しています。128 MiB の CMA は維持します。

旧環境で `/proc/cmdline` に `maxcpus=1` が残る場合は、カーネルの更新
だけでは解除されません。[Release](https://github.com/makeding/quastation-armbian/releases/tag/v-7.3.4-7)
添付の `qua-enable-smp.tar.gz` を対象の Qua に転送し、次を実行します。

```sh
tar -xzf qua-enable-smp.tar.gz
sudo python3 enable-smp.py /var/lib/qua-kernel/smp-environment-before-v7
sudo reboot
cat /sys/devices/system/cpu/online
```

`0-3` なら四 CPU です。このツールは両 factory 環境とレスキューの
インポート用環境から `maxcpus=1` だけを削除し、元の環境を指定先に
保存します。バックアップには個体別データがあるため公開しないでください。
ソースは [qua-rescue-uboot/scripts](https://github.com/makeding/qua-rescue-uboot/tree/qua-rescue/scripts) で管理します。

| 領域 | 状態 | 概要・対象コンポーネント |
| --- | --- | --- |
| CPU / クロック / 割り込み / サーマル | 対応済み | Cortex-A53 四 CPU（`online=0-3`）、`clk-quastation*`、`irq-quastation`、`rtd129x-quastation-thermal` |
| メモリ | 対応済み | 物理 2 GiB、Linux の MemTotal 約 1.86 GiB、GPU/VE 用 128 MiB CMA |
| GPIO / LED | 対応済み | `qua-iso-gpio`、`gpio-leds` |
| eMMC / SD / SATA | 対応済み | `rtkemmc-quastation`、`rtk-sdmmc`、`ahci-quastation` |
| USB ホスト / USB ADB ガジェット | 対応済み | DWC3、`kddi,quastation-ehci`、DWC2 ペリフェラル + `qua-usb-adbd` |
| PCIe / Wi-Fi | 対応済み | `pcie-rtd129x-slot1` / `slot2`、Realtek 無線ファームウェア（`firmware/rtlwifi/`） |
| Bluetooth | 対応済み | RTL8761ATV、UART2 / H5。ファームウェア読み込み、`hci0` 初期化、BlueZ のコントローラー起動を実機で確認 |
| LTE モデム | 対応済み | WWHC060、USB AT / CDC Ethernet、PPP。SMS / VoLTE は別パッケージの HuaStation とモデム側修正を利用 |
| GPU / 動画エンジン / トランスコード | 対応済み（制約あり） | `qua-gpu`（Mali-T820 / Panfrost）、`video/ve1`、`video/ion`、`media/qua-transcode/` |
| RAM メンテナンス / USB 復旧 | 対応済み | レスキュー U-Boot の USB コンソール、`QuaMaintenance` の RAM 起動と USB ADB 接続を実機で確認 |
| 未導入機への一括インストール | 検証中 | `install-over-usb.sh` を使う工場出荷状態からの全工程（詳細は [image/README.md](image/README.md)） |

- `media/vendor-openmax/lib/` の Realtek OpenMAX ランタイムは再配布条件が不明なためリポジトリには同梱せず、ビルド時に外部取得またはローカル配置します。
- 動画パイプラインおよび `ffmpeg-omx` の既知制約（1 フィールド補間による 29.97fps 出力等）は [media/qua-transcode/README.md](media/qua-transcode/README.md) を参照してください。

## 3. 推奨インストール方法とパーティション構成

### eMMC パーティション・ブートスロット構成

対象 eMMC（15,269,888 セクター、512 バイト/セクター）は `image/quastation-layout.mbr` に従い構成されます。先頭の純正ブートコードと factory 環境は保持し、ディスク全体の `dd` イメージ書き換えは行いません。

| 領域 | 開始 LBA | セクター数 | 用途 |
| --- | ---: | ---: | --- |
| ファームウェア領域 | 0 | 196608 | 純正ブートコードと factory データを保持 |
| `p1` | 196608 | 32768 | ファイルシステムを作らない起動用 raw 領域 |
| `p2` | 229376 | 13443072 | Btrfs `QUA_ROOT`（ルートサブボリューム `@`、`compress=zstd:3`） |
| `p3` | — | — | エントリーを削除し、旧領域を `p2` に統合 |
| `p4` | 13672448 | 1269760 | 既存の拡張パーティションと論理領域を保持 |

raw 起動スロットには本リポジトリのスロットライター（`image/write-boot-slots.py`）で `Image-legacy-uboot.gz`（`text_offset=0x20000000` 調整済み）を書き込みます。

| スロット | 開始 LBA | セクター数 |
| --- | ---: | ---: |
| カーネル | 196608 | 12288 |
| レスキュー引き継ぎ | 210944 | 512 |
| DTB | 212736 | 31 |
| メンテナンス initrd | 212992 | 15534 |

### 推奨導入手順（ベストプラクティス）

1. **Qua rescue U-Boot（v6 以降）を導入する**

   [qua-rescue-uboot](https://github.com/makeding/qua-rescue-uboot/releases) の [setup.md](https://github.com/makeding/qua-rescue-uboot/blob/qua-rescue/setup.md) に従いステージングと有効化を行います（`usbrecv` による高速転送と `.uImage` initrd 自動引き継ぎに対応しています）。

   ```sh
   sudo python3 install-usb-chain.py . stage
   sudo python3 install-usb-chain.py . arm
   ```

2. **RAM メンテナンス環境（`QuaMaintenance`）を起動する**

   再起動時に USB 2.0 ポートへ接続した状態で CDC ACM コンソール（例: macOS `/dev/cu.usbmodemQuaRescue1`）を開き、`usbrecv` で `QuaStation-maintenance-initramfs.uImage`（約 5 秒で転送完了）を `0x30000000` へロードして起動します。

   ```text
   usbrecv 0x30000000 <hex_size>
   boot
   ```

   起動後は `adb devices -l` に `QuaMaintenance` が表示されます。

3. **eMMC バックアップと Armbian rootfs インストール**

   ```sh
   adb -s QuaMaintenance shell 'cat /sys/class/block/mmcblk0/device/cid' > cid.txt
   set -o pipefail
   adb -s QuaMaintenance exec-out 'dd if=/dev/mmcblk0 bs=1048576 2>/dev/null' | gzip -1 > factory-emmc.img.gz
   python3 RELEASE_DIR/prepare-target-bundle.py factory-emmc.img.gz "$(cat cid.txt)" RELEASE_DIR TARGET_BUNDLE
   bash image/install-over-usb.sh RELEASE_DIR TARGET_BUNDLE \
     QuaStation-Armbian-trixie-arm64-rootfs.tar.zst authorized_keys wpa.conf \
     QuaStation-maintenance-stage2.tar.gz
   ```

   再起動後は USB ADB（`QuaStation`）、Wi-Fi（`wlan0`）、SSH、および `huastation` が自動で立ち上がります。
   - **SSH 認証**: `root` アカウントには初期パスワードが設定されておらず、パスワードログインは無効（`PasswordAuthentication no`）です。導入時に必ず `authorized_keys` を配置してください（未配置の場合は起動後に USB ADB `adb -s QuaStation shell` から設定できます）。
   - **Wi-Fi**: `wpa.conf` を渡さない場合、`huastation` が本体底面ラベルの初期 SSID / パスワードで AP モードを起動します。

4. **導入後のカーネル更新・HuaStation 更新**

   `huastation` は Armbian rootfs に同梱済みです。再導入や更新を行う場合は `/usr/local/sbin/install-huastation`（または `sudo bash image/install-huastation.sh`）を実行してください。

   カーネル更新時は USB ADB 経由で `.deb` を送り、`sudo apt install ./linux-image-*_arm64.deb` を実行します（`adb push` + `apt install` が最速で、`postinst` が自動でスロットを書き換えます）。macOS で `adb devices` が `offline` になった場合は `adb -s QuaStation reconnect offline` を実行してください。

## 4. トラブルシューティング

- **U-Boot 起動失敗時、DC 電源を抜き差ししても再起動しない場合**:
  USB-A オス-オスケーブルを接続している場合、USB ケーブルも同時に抜いてから電源を入れ直してください。本機は USB 電源ラインに逆流防止ダイオードがないため、USB 接続中は 5V 給電が回り込み、DC 電源の抜き差しだけでは完全に電源が落ちません。

## 5. 関連リソース

- [qua-rescue-uboot](https://github.com/makeding/qua-rescue-uboot/)（[setup.md](https://github.com/makeding/qua-rescue-uboot/blob/qua-rescue/setup.md)）: RAM レスキュー U-Boot と USB ブートチェーン
- [huastation](https://git.huggy.moe/qua/huastation): Qua Station 管理パッケージ
- [image/README.md](image/README.md): RAM メンテナンスシステムおよび USB インストーラーの詳細仕様
- [media/qua-transcode/README.md](media/qua-transcode/README.md): ハードウェアトランスコードと FFmpeg パッチのビルド・検証手順
- [firmware/README.md](firmware/README.md) / [modules/README.md](modules/README.md): ファームウェアおよびカーネル外モジュール情報

## 6. ライセンス

本プロジェクトは複数のライセンスを持つコンポーネント（Linux カーネル・GPL-2.0 系ドライバー、LGPL-2.1+ メディアツール、Khronos MIT ヘッダー、Realtek ファームウェア・vendor バイナリ、Armbian / Debian パッケージ等）を組み合わせた混合ライセンス構成です。

詳細は [LICENSE](LICENSE) および各ファイル内の SPDX 識別子・著作権表示を参照してください。
