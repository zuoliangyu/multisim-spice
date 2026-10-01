# Multisim 示例工程

用 skill 完整流程生成的 Multisim 14 工程，**打开后不用做任何设置，直接按 F5** 就出结果。可以用来：

- 看 skill 最终交付的样子（原理图、模型、分析设置都和网表一致）；
- 确认本机 Multisim 环境正常：打开后弹出 "Master Database cannot be accessed"，或者结果和下表对不上，先按 `SKILL.md` 的排错表处理。

每个工程的生成方式都一样：`references/` 里的网表导入 Multisim 后另存，得到 `references/fixtures/` 里的原始工程，再用 `scripts/patch-ms14.ps1` 写回模型、P 型符号、实例参数和分析设置。最后用 Multisim 自己的压缩格式压缩，Multisim 能直接打开，不压缩的版本也一样能打开。

| 文件 | 电路 | 当前分析 | 按 F5 后看到的 | ngspice 参考值 |
|---|---|---|---|---|
| `01_divider.ms14` | 分压 | DC 工作点 | V(in)、V(out) 电压表 | V(out) 3.837 V |
| `02_rc_lowpass.ms14` | RC 低通 | AC 扫描 10 Hz–100 kHz | V(out) 幅频 / 相频曲线 | −3 dB 点 998.6 Hz |
| `03_rc_step.ms14` | RC 阶跃 | 瞬态 0–6 ms | V(in) 方波，V(out) 指数上升 | τ = 1.000 ms |
| `04_halfwave_rectifier.ms14` | 二极管半波整流 + 滤波电容（1N4148） | 瞬态 0–100 ms | V(in) 正弦，V(out) 带纹波的直流 | 80–100 ms 内峰值 9.27 V、谷值 7.77 V |
| `05_bjt_ce_amp.ms14` | BJT 共射放大（2N2222） | AC 扫描 10 Hz–10 MHz | 中频增益约 158，相位约 −180° | 1 kHz 处 44.0 dB、−175° |
| `06_opamp_inverting.ms14` | 运放反相放大（E 源展开的理想运放） | 瞬态 0–3 ms | V(out) 与 V(in) 反相，幅度 10 倍 | 0.1 V 峰值输入 → −1.0 V |
| `07_multi_device.ms14` | 两种 NPN、一个 PNP、两种二极管 | DC 工作点 | 11 个节点电压表 | VC1 8.116 V、VC2 0.224 V、VC3 5.255 V |
| `08_mos_jfet.ms14` | NMOS / PMOS（W/L = 20µ/2µ）、N / P 沟道 JFET | DC 工作点 | 9 个节点电压表 | d1 3.960 V、d2 0.522 V、d3 3.454 V、d4 2.013 V |
| `09_dc_sweep.ms14` | 分压 | 直流扫描 V1 0–12 V | V(out) 随 V1 线性变化 | 12 V 时 3.837 V |

9 个都在 Multisim 14.0 里打开后直接 F5 验证过，结果与 ngspice 一致；07、08 的 DC 工作点一致到 5 位有效数字。其中 01、02、04、06、07 验证的就是本目录里的压缩文件，07 大于 900000 字节，是分两块压缩的；03、05、08、09 验证的是同一流程生成的未压缩版。

打开前，如果 Multisim 里已经开着同名标签页，先关掉，选不保存。否则 Multisim 只会切到旧标签页，不会重新读文件。
