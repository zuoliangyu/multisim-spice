# Multisim 示例工程

用 skill 完整流程生成的 Multisim 14 工程，**打开后不用做任何设置，直接按 F5** 就出结果。可以用来：

- 看 skill 最终交付的样子（原理图、模型、分析设置都和网表一致）；
- 确认本机 Multisim 环境正常：打开后弹出 "Master Database cannot be accessed"，或者结果和下表对不上，先按 `SKILL.md` 的排错表处理。

每个工程的生成方式都一样：`references/` 里的网表导入 Multisim 后另存，得到 `references/fixtures/` 里的原始工程，再用 `scripts/patch-ms14.ps1` 写回模型、P 型符号、实例参数和分析设置。最后用 Multisim 自己的压缩格式压缩，Multisim 能直接打开，不压缩的版本也一样能打开。

| 文件 | 电路 | 当前分析 | 按 F5 后看到的 | ngspice 参考值 |
|---|---|---|---|---|
| `02_rc_lowpass.ms14` | RC 低通 | AC 扫描 10 Hz–100 kHz | V(out) 幅频 / 相频曲线 | −3 dB 点 998.6 Hz |
| `03_rc_step.ms14` | RC 阶跃 | 瞬态 0–6 ms | V(in) 方波，V(out) 指数上升 | τ = 1.000 ms |
| `05_bjt_ce_amp.ms14` | BJT 共射放大（2N2222） | AC 扫描 10 Hz–10 MHz | 中频增益约 158，相位约 −180° | 1 kHz 处 44.0 dB、−175° |
| `07_multi_device.ms14` | 两种 NPN、一个 PNP、两种二极管 | DC 工作点 | 11 个节点电压表 | VC1 8.116 V、VC2 0.224 V、VC3 5.255 V |
| `08_mos_jfet.ms14` | NMOS / PMOS（W/L = 20µ/2µ）、N / P 沟道 JFET | DC 工作点 | 9 个节点电压表 | d1 3.960 V、d2 0.522 V、d3 3.454 V、d4 2.013 V |
| `09_dc_sweep.ms14` | 分压 | 直流扫描 V1 0–12 V | V(out) 随 V1 线性变化 | 12 V 时 3.837 V |

03、05、07、08、09 的同款工程（未压缩版）都在 Multisim 14.0 里实测过：打开后直接 F5，结果与 ngspice 一致，07、08 的 DC 工作点一致到 5 位有效数字。本目录里的压缩版也直接打开验证过：`02`（单块压缩）出波特图，−3 dB 点在 1 kHz 附近；`07`（大于 900000 字节，分两块压缩）的工作点表与未压缩版完全相同。

`01_divider`、`04_halfwave_rectifier`、`06_opamp_inverting` 暂时没有示例工程，因为还没有它们导入后另存的原始工程。要补的话，在 Multisim 里导入对应的 `.cir`、另存，再按 `SKILL.md` 第 5 步运行脚本即可。

打开前，如果 Multisim 里已经开着同名标签页，先关掉，选不保存。否则 Multisim 只会切到旧标签页，不会重新读文件。
