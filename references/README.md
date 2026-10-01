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
| `07_multi_device.cir` | `.op` | 多种半导体模型(两种 NPN、PNP、两种二极管,D1/D3 共用模型),演示导入后写回模型 | 见下文《导入后写回模型》 | VC1 8.116 V,VC2 0.224 V,VC3 5.255 V |

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
| `07_multi_device.cir` | `op; print v(c1) v(c2) v(c3) v(d1) v(d2) v(d3)` |

## Multisim 14 导入实测

导入后用 Transfer → Export Netlist 导出,逐个引脚对比连接关系,再把导出的网表放进 ngspice 跑同样的测量:

| 文件 | 连线 | 器件模型 | 导出网表的 ngspice 结果 | 结论 |
|---|---|---|---|---|
| `01_divider.cir` | 全部正确 | 无半导体器件 | V(out) = 3.8367 V | 与原版一致 |
| `02_rc_lowpass.cir` | 全部正确(`AC 1` 激励保留) | 无半导体器件 | fc = 998.6 Hz | 与原版一致 |
| `03_rc_step.cir` | 全部正确(`PULSE` 参数保留) | 无半导体器件 | τ = 1.0002 ms | 与原版一致 |
| `04_halfwave_rectifier.cir` | 全部正确 | D1N4148 → 默认参数虚拟二极管 | 峰值 9.28 V,纹波 1.52 V | 与原版几乎一致 |
| `05_bjt_ce_amp.cir` | 全部正确 | Q2N2222 → 默认参数虚拟 NPN | VC 6.30 V,VE 1.23 V,增益 43.5 dB | 工作点偏移约 0.75 V,需用 `patch-ms14.ps1` 写回模型 |
| `06_opamp_inverting.cir` | 全部正确 | 无半导体器件,`E` 源正常导入 | 增益 −9.999 | 与原版一致 |

另做了一组对照(三极管偏置 + 二极管限流,真实参数下 VC = 8.12 V、默认参数下 9.76 V):`.model` 名写成元件库型号 `2N2222A` / `1N4148`、带完整参数;同样的型号名但不写 `.model`;以及现在的 `Q2N2222` / `D1N4148` 写法。三种写法导入后导出的网表完全相同,都是 `NPN__TRANSISTORS_VIRTUAL__1` / `DIODE__DIODES_VIRTUAL__1` 默认模型。结论:导入器不按型号查元件库,半导体器件的参数只能导入后再写回(见下文《导入后写回模型》)。

又按写法做了排查:全部参数改用科学计数法、只留关键参数并分别用后缀 / 科学计数法写,以及把 Multisim 自己导出的带参数网表原样导回去。4 种情况导入后都是默认参数的虚拟器件。说明导入器(网表 → 原理图)和导出器是两套逻辑,导入时根本不读 `.model`,与写法无关。往返导入还会把元件名叠一层类型前缀(`D1` → `DD1`)、把直流源改成幅度为 0 的正弦源,所以 Multisim 导出的网表也不适合作为交付格式。

导入后手动处理(同一个对照电路实测):Q1 用 Edit model 改 IS、BF、VAF、IKF、ISE、NE 六个参数后,导出网表的 VC = 8.1162 V(原网表 8.1163 V);D1 用 Replace 换成 Master Database 的 1N4148 后,V(d) = 0.641 V(原网表 0.653 V,NI 自带模型参数不同)。

6 个电路的连线都已用导出网表逐个引脚核对。原理图上交叉的线不一定代表连错(04、05 的图看着乱,实际连线全对),判断以导出的网表为准。

## 导入后写回模型

Multisim 工程文件 `.ms14` 是分块压缩的 XML(PKWARE DCL 压缩,每块最多 900000 字节),每个器件的模型以 SPICE `.MODEL` 文本嵌在 `<CiModel>` 里,原理图符号的图形也逐个实例嵌在文件中。`scripts/patch-ms14.ps1` 解压后按引脚所接的网络把网表器件对应到 Multisim 元件,改写模型文本、把 PNP 的符号改回 PNP、写入分析设置,再以纯 XML 写出(Multisim 14 能直接打开不压缩的 `.ms14`)。

用 `07_multi_device.cir` 实测(导入 → 另存 → 写回 → 打开 → 导出网表 → ngspice):

| 器件 | 模型 | 原网表 | 写回后导出 | 未写回(默认参数) |
|---|---|---|---|---|
| Q1 VC | Q2N2222 | 8.116298 V | 8.116298 V | 9.755 V |
| Q2 VC | QHIBETA(BF=500) | 0.2238 V | 0.2238 V | 6.725 V |
| Q3 VC | Q2N3906(PNP) | 5.255039 V | 5.255039 V | 2.245 V |
| D1 / D2 / D3 | D1N4148 / D1N4007 / D1N4148 | 0.6532 / 0.6241 / 0.5478 V | 一致 | 0.693 / 0.693 / 0.634 V |

导入时发现、脚本已处理的几点:

- 同类虚拟器件共用一个模型(三个三极管都指向 `NPN__TRANSISTORS_VIRTUAL__1`),需要不同参数时脚本会复制拆开;
- 工程内部的元件编号会被打乱(网表 Q3 在内部是 Q1),所以按引脚网络而不是按名字对应;界面上显示的位号仍与网表一致;
- PNP 被导入成 NPN 符号(族名 `BJT_NPN`、发射极箭头朝外),脚本改族名 / 类型字符串,并把箭头的三个顶点换成 Multisim 自己的 PNP 符号坐标,打开后箭头朝里;
- 带单位后缀的数值(`14.34f`、`80m`、`100u`)Multisim 正常识别。

**分析设置**也存在 `.ms14` 里:`CIITDiagram` 的 `SimState` 属性是一段 `名字:类型{值}` 嵌套文本,`ANALYSES` 下 `OP` / `AC` / `TRAN` 各有参数(`AC` 的 `FSTART` / `FSTOP` 是纯数值,`TRAN` 的 `TSTOP` / `TMAX` 等)和输出列表(`Nodes` 里 `NAME:string{$out}` 且 `GROUP:long{768}` 表示选中);当前分析由 `ActiveAnalysis` 属性决定(`interactive` / `dcOpPoint` / `ac` / `transient`)。脚本按网表的 `.op` / `.ac` / `.tran` 改写这些字段。

在 Multisim 里打开脚本生成的工程、不做任何设置直接 F5 的实测:

| 电路 | Multisim 结果 | ngspice |
|---|---|---|
| `07_multi_device`(DC 工作点) | VC1 8.11629 V、VC2 223.79 mV、VC3 5.25505 V,V(d1/d2/d3) 653.21 / 624.05 / 547.74 mV | 8.116298 V、223.80 mV、5.255039 V,653.23 / 624.07 / 547.76 mV |
| `05_bjt_ce_amp`(AC 扫描) | 波特图:中频增益约 158,相位约 −180° | 44.0 dB(≈158),−175°(1 kHz) |
| `03_rc_step`(瞬态) | V(out) 按 τ = 1 ms 指数上升到 5 V | τ = 1.0002 ms |

**回归测试**(改脚本后在仓库根目录跑,不需要打开 Multisim):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\patch-ms14.ps1" "references\07_multi_device.cir" "references\fixtures\07_multi_device_import.ms14" "<临时目录>\07_out.ms14"
```

应输出 6 行 `MAPPED`(网表 Q1/Q2/Q3/D1/D2/D3 → 内部 Q4/Q2/Q1/D4/D2/D1)、3 行 `CLONED`、1 行 `SYMBOL Q1: virtual NPN turned into virtual PNP`、1 行 `ANALYSIS DC operating point; outputs V(a), ...`、`ACTIVE   dcOpPoint`,末行 `PATCH: OK`。`fixtures/07_multi_device_import.ms14` 是 `07_multi_device.cir` 在 Multisim 14.0 里导入后直接另存、未做任何修改的工程。

### 完整交付示例(含半导体器件)

以 `07_multi_device.cir` 为例,Claude 依次执行:

1. 自检:`check.ps1 07_multi_device.cir "op; print v(c1) v(c2) v(c3)"`,末行 `CHECK: PASS`,数值和设计目标对上。
2. 打开:`find-multisim.ps1 -Open <路径>\07_multi_device.cir`(Multisim 设为以管理员运行时会弹 UAC)。
3. 请用户 File → Save As 存成 `07_multi_device_import.ms14`,等用户确认。
4. 写回:`patch-ms14.ps1 07_multi_device.cir 07_multi_device_import.ms14 07_multi_device.ms14`,确认末行 `PATCH: OK`,有 `NOTE` / `WARNING` 时如实告诉用户。
5. 请用户关掉 `07_multi_device_import` 标签页(不保存),打开 `07_multi_device.ms14`,直接按 F5:DC 工作点表应与 ngspice 一致(实测 VC1 8.11629 V、VC2 223.79 mV、VC3 5.25505 V),把 ngspice 的数值一起告诉用户供对照。

## 模型来源

- `D1N4148`、`Q2N2222`、`Q2N3906`、`D1N4007`:常见的厂商 SPICE 模型参数(`QHIBETA` 是 07 里为区分模型虚构的高 β NPN),足够做教学级仿真;要和实测严格对比时换成器件手册给的模型。
- 06 的理想运放:输入电阻 1 MΩ(`RIN`)、开环增益 1e5(`EOP`)、输出电阻 75 Ω(`ROUT`),不含带宽和摆率限制。没有用 `.subckt`,因为 Multisim 14 导入网表时会丢掉子电路实例。需要带宽等效应时,导入后在 Multisim 里换成元件库里的运放。
