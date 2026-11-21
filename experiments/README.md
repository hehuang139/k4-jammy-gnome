# K4 V3.0 的 i2c2 时序对照（仅 TF）

在 V3.0（4 GB/16 GB）的首版实板中，`rk8xx-i2c`（`2-001b`）和两枚 `fan53555`（`2-0040/41`）响应超时，Panfrost 等待 `2-0041`，只有 `/dev/dri/card0`；`glxinfo` 是 llvmpipe。两份 K4 Android 设备树有同样的 i2c2 时序参数，故仅用覆盖层将频率设为 200 kHz、SCL 上升为 800 ns、下降为 40 ns；供电电压、GPIO 与 regulator 属性一律不变。相关现场讨论：[ophub #2248](https://github.com/ophub/amlogic-s9xxx-armbian/issues/2248)、[#2696](https://github.com/ophub/amlogic-s9xxx-armbian/issues/2696)、[#3722](https://github.com/ophub/amlogic-s9xxx-armbian/issues/3722)。

构建后可用 `build/docker-run.sh experiments/validate-i2c2-timing.sh work/board-boot/dtb/rockchip/rk3399-lzk4.dtb` 离线确认应用覆盖层只新增三项属性。实板 A/B 时使用额外的测试 TF 卡和相同的稳定系统，一个时间只启动一张 TF：把 `dtc -@ -I dts -O dtb` 编译的 `k4-i2c2-android-timing.dtbo` 放进该卡 `/boot/overlay-user/`，并在该卡 `/boot/armbianEnv.txt` 的 `user_overlays` 中加入 `k4-i2c2-android-timing`。失败时去掉该项恢复稳定 DTB。不要将该覆盖层装进稳定 eMMC。

对照记录启动日志中的 PMIC/调压器错误和 deferred supplier、`ls /dev/dri` 是否出现 `renderD128`、`glxinfo -B` 的 renderer / acceleration，以及网络、USB、HDMI 有无退化。覆盖层已离线通过合并检查，V3.0 尚未执行实板启动对照，不是 GPU 修复。
