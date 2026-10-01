# 参考网表

常见 prelab 电路的标准写法。每个 `.cir` 都是 **可直接交付给 Multisim 的干净网表**(纯 ASCII、无 ngspice 专有语法),并已用内置 ngspice 46 通过 `scripts/check.ps1` 自检。

写新电路时,类型相近就先读对应文件,沿用其写法和 `.model` / `.subckt`,再按需求改值。

| 文件 | 分析 | 演示的写法 | 理论值 | ngspice 实测 |
|---|---|---|---|---|
| `01_divider.cir` | `.op` | 最简网表、直流源 | V(out) = 3.837 V | 3.8367 V |
| `02_rc_lowpass.cir` | `.ac` | `AC 1` 激励、测 −3 dB 点 | fc = 1.00 kHz | 998.6 Hz;10 kHz 处 −20.0 dB |
| `03_rc_step.cir` | `.tran` | `PULSE` 源、测时间常数 | τ = 1 ms | 1.0002 ms;5τ 时 4.966 V |
| `04_halfwave_rectifier.cir` | `.tran` | `SIN` 源、二极管 `.model` | 峰值 ≈ 9.3 V,纹波 < 1.9 V | 峰值 9.27 V,纹波 1.51 V |
| `05_bjt_ce_amp.cir` | `.ac` | BJT `.model`、分压偏置、耦合/旁路电容 | IC ≈ 1.4 mA,VC ≈ 5.5 V,增益 40~45 dB | IC 1.37 mA,VC 5.55 V,44.0 dB,相位 −175° |
| `06_opamp_inverting.cir` | `.tran` | 理想运放用 `E` 受控源 + 电阻展开(不用 `.subckt`) | 增益 −10 | −9.999 |

## 自检命令

在仓库根目录下运行(`<F>` 换成文件名):

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check.ps1 references\<F> "<测量命令>"
```

| 文件 | 测量命令 |
|---|---|
| `01_divider.cir` | (不需要,`.op` 直接打印节点电压) |
| `02_rc_lowpass.cir` | `meas ac gain_10hz find vdb(out) at=10; meas ac f3db when vdb(out)=-3; meas ac gain_10khz find vdb(out) at=10k` |
| `03_rc_step.cir` | `meas tran tau when v(out)=3.16 rise=1; meas tran v_5tau find v(out) at=5m` |
| `04_halfwave_rectifier.cir` | `meas tran vmax max v(out) from=80m to=100m; meas tran vmin min v(out) from=80m to=100m; let ripple = vmax - vmin; print ripple` |
| `05_bjt_ce_amp.cir` | `meas ac gain_1k find vdb(out) at=1k; meas ac phase_1k find vp(out) at=1k; op; print v(b) v(e) v(c) @q1[ic]` |
| `06_opamp_inverting.cir` | `meas tran vin_pk find v(in) at=2.25m; meas tran vout_pk find v(out) at=2.25m; let gain = vout_pk / vin_pk; print gain` |

## Multisim 14 导入实测

导入后用 Transfer → Export Netlist 导出,逐个引脚对比连接关系,再把导出的网表放进 ngspice 跑同样的测量:

| 文件 | 连线 | 器件模型 | 导出网表的 ngspice 结果 | 结论 |
|---|---|---|---|---|
| `04_halfwave_rectifier.cir` | 全部正确 | D1N4148 → 默认参数虚拟二极管 | 峰值 9.28 V,纹波 1.52 V | 与原版几乎一致 |
| `05_bjt_ce_amp.cir` | 全部正确 | Q2N2222 → 默认参数虚拟 NPN | VC 6.30 V,VE 1.23 V,增益 43.5 dB | 工作点偏移约 0.75 V,需在 Multisim 里换成 2N2222A |
| `06_opamp_inverting.cir` | 全部正确 | 无半导体器件,`E` 源正常导入 | 增益 −9.999 | 与原版一致 |

01–03 只做了看图检查(元件少、没有交叉线),没有导出网表核对。原理图上交叉的线不一定代表连错,判断以导出的网表为准。

## 模型来源

- `D1N4148`、`Q2N2222`:常见的厂商 SPICE 模型参数,足够做教学级仿真;要和实测严格对比时换成器件手册给的模型。
- 06 的理想运放:输入电阻 1 MΩ(`RIN`)、开环增益 1e5(`EOP`)、输出电阻 75 Ω(`ROUT`),不含带宽和摆率限制。没有用 `.subckt`,因为 Multisim 14 导入网表时会丢掉子电路实例。需要带宽等效应时,导入后在 Multisim 里换成元件库里的运放。
