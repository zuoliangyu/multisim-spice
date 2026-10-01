---
name: multisim-spice
description: 把自然语言电路描述变成经过验证、可在 Multisim 打开的 SPICE 网表。流程为「生成 SPICE 网表 → 用内置 ngspice 批处理自检 → 校验通过后导入 NI Multisim」。当用户要设计电路、画电路、做电路仿真、写 SPICE 网表、做 prelab 电路、用 Multisim 仿真时触发。Also triggers on: SPICE netlist generation, circuit design, Multisim simulation, ngspice check, electronics prelab.
---

# Multisim SPICE 电路助手

把一句话的电路描述,自动变成 **经过 ngspice 验证、可直接在 NI Multisim 打开** 的 SPICE 网表。
你(Claude)既是网表设计者,也是验证者——不要把没跑通的网表交给用户。

> 平台:Windows + NI Multisim(14.x 系列已验证)。ngspice 已绿色版自带。

## 资源位置

- **ngspice(自检引擎)** —— 本 skill 自带的绿色版 Windows 二进制,无需安装:
  - 相对路径(相对于本 SKILL.md 所在目录):`vendor\Spice64\bin\ngspice_con.exe`(纯命令行版,自检用这个)
  - 实际调用时,把 **本 SKILL.md 的所在目录** 拼到前面构成绝对路径。skill 若被搬家,按 SKILL.md 当前位置重新推算即可,后缀 `vendor\Spice64\` 不变。
- **辅助脚本**(`scripts\`,Windows PowerShell 5.1 即可运行):
  - `check.ps1 <网表> ["<命令>; <命令>"]` —— 跑 ngspice 批处理并扫报错,末行输出 `CHECK: PASS` / `CHECK: FAIL`(退出码 0 / 1)。第二个参数是可选的 ngspice 测量命令,脚本会在临时副本里注入 `.control` 块再跑,**交付网表本身不被改动**。
  - `find-multisim.ps1 [-Open <网表>]` —— 探测 `multisim.exe` 并打印路径;带 `-Open` 时顺便用它打开网表。
- **参考网表**(`references\`)—— 6 个已自检通过的常见电路(分压、RC 低通、RC 阶跃、整流、BJT 共射、运放反相),索引和每个电路的自检命令、实测结果见 `references\README.md`。
- **Multisim** —— 用户机本地安装的 NI Multisim(14.x 已验证):
  - **不要写死路径。** 用 `find-multisim.ps1` 探测,找不到再问用户。

> **调用方式**:Windows 上 Bash 工具跑的通常是 Git Bash,PowerShell 语法(`&`、`$var`)在里面不能用。统一这样调脚本,Bash / PowerShell 下都能用:
> ```
> powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\<脚本>.ps1" <参数>
> ```

## 工作流程

### 第 1 步 · 厘清需求

生成网表前,确认描述里缺失或模糊的关键参数:

- 电源电压、信号源幅度/频率
- 关键元件值或设计指标(截止频率、增益、静态电流、时间常数……)
- 需要哪种分析:静态工作点(.op)、直流扫描(.dc)、交流(.ac)、瞬态(.tran)

能合理假设的就假设并说明;无法合理假设的关键参数,先问用户,不要乱猜。

### 第 2 步 · 生成 SPICE 网表

按下方《SPICE 网表规范》生成,用 Write 工具存成 `<电路名>.cir`,放到用户当前工作目录(除非用户指定别处)。这一份是 **最终交付给 Multisim 的干净网表**,不要放 ngspice 专有语法(`.control` 块、XSPICE 的 `A` 器件等)。

**先看参考网表**:电路属于 `references\README.md` 里列出的类型(或包含其中的部件,如二极管 `.model`、BJT 偏置、运放子电路)时,先读对应的 `.cir`,沿用它的写法和模型参数,再按需求改值。

### 第 3 步 · 用 ngspice 自检(必做)

不要跳过。运行(把 `<SKILL_DIR>` 换成本 SKILL.md 所在目录的绝对路径):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\check.ps1" "<circuit.cir 的完整路径>" "<测量命令; 测量命令>"
```

- **.op 电路**:可以不给第二个参数,批处理模式会直接打印各节点电压。
- **.tran / .ac / .dc 电路**:批处理模式要求有 `.print` 才肯跑,所以 **把测量命令作为第二个参数传给脚本**,由它在临时副本里注入 `.control` 块。不要手工复制 `_check.cir`,两份文件改着改着容易不一致。不给命令时脚本也会跑一遍,但会提示指标没核对。

**测量命令优先用 `meas`,直接算出指标值**,比 `.print` 打几百行数据再人工找更快、更准。多条命令用 `;` 隔开,例如:

```
"meas ac f3db when vdb(out)=-3; meas ac gain_lo find vdb(out) at=10"
"meas tran t63 when v(out)=3.16 rise=1; meas tran vmax max v(out)"
"meas tran vmax max v(out) from=80m to=100m; meas tran vmin min v(out) from=80m to=100m; let ripple = vmax - vmin; print ripple"
```

注入的块是 `run` 加上这些命令,`run` 会依次执行网表里的分析。想同时看偏置点,就在测量命令之后再写 `op; print v(b) v(c) @q1[ic]`。`op` 会把当前结果切换成工作点,所以要放在 `meas ac/tran` 之后。

测量的坑(内置 ngspice 46 实测):

- **AC 测量别用 `v(out)`**:AC 里它取的是 **实部**,不是幅值。RC 低通用 `when v(out)=0.7071` 会算出 644 Hz(实际约 1 kHz)。幅度用 `vdb(out)`,或先 `let g=mag(v(out))`。`vp(out)` 的单位是弧度。
- **`.meas` 卡片行里写 `vdb()` / `vm()` 会失败**(`can't parse 'vd'`,AC 分析直接不跑)。测量一律通过脚本第二个参数走 `.control` 块。
- 确实要看整条曲线时才用 `print`(如 `print vdb(out)`),并控制点数,别把上千行塞进上下文。

**判读输出 —— 两层检查:**

1. **能不能跑** —— 看 `check.ps1` 末行。`CHECK: FAIL` 时,命中的报错行列在 `----- problems -----` 下面。
   - **不能只看退出码**:有悬空节点时 ngspice 会退回 transient op,**退出码仍是 0,节点电压看着也正常**,只有 `singular matrix` / `stepping failed` 警告会暴露问题。脚本会把这种情况判成 FAIL。
   - `singular matrix: check node X` 多半是 X 悬空 / 没有到地的直流通路。
   - `can't find model` / `could not find a valid modelname` 是缺 `.model` 或 `.subckt` 定义。
   - 没法跑 PowerShell 时,直接跑 `vendor\Spice64\bin\ngspice_con.exe -b <网表>`,自己扫这些词(不区分大小写):`error` · `singular matrix` · `can't find` · `can't parse` · `unknown` · `no convergence` · `timestep too small` · `aborted` · `stepping failed` · `nan` · `inf`。
2. **对不对** —— 把数值跟设计指标比对,而不只是"没报错"。例如要求截止频率 1kHz,就看 `f3db` 是不是在 1kHz 附近;要求某点 5V,就看是不是 5V。

有问题 → 改网表 → 重跑,直到既跑通又满足指标。然后把关键结果用人话讲给用户。

### 第 4 步 · 导入 Multisim

自检通过后,一条命令完成探测和打开:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\find-multisim.ps1" -Open "<circuit.cir 的完整路径>"
```

退出码 1 并报 `multisim.exe not found` → 见《定位 Multisim》。

然后告诉用户:Multisim 会打开并把网表导入成原理图(可能弹出网表导入对话框,按提示确认即可);**导入完成后由用户自己运行仿真**。不要尝试自动按 F5。

Multisim 导入时会 **忽略网表里的分析命令**(日志显示 `Ignored: .op` 等),所以要告诉用户具体怎么设:在 Simulate → Analyses and simulation 里选对应分析(DC Operating Point / AC Sweep / Transient),填上和网表一致的参数,输出选关键节点,再运行。同时给出 ngspice 的关键数值,让用户对照。

电路里有 `D` / `Q` / `M` / `J` 器件时,还要告诉用户:导入后它们是参数为默认值的虚拟器件,Multisim 的结果会和 ngspice 有偏差。要和 ngspice 对上,在 Multisim 里右键该器件 → Replace Components,换成元件库里的同型号器件(如 1N4148、2N2222A)。不含半导体器件的电路(R/C/L/源/受控源)导入后数值应与 ngspice 一致,对不上多半是连线问题。

## SPICE 网表规范

- **首行是标题行**:SPICE 把网表第一行当标题/注释,不解析。永远写一行标题占位。
- **末行是 `.end`**。
- **节点 0 是地**。每个节点都要有到地的直流通路,否则会 `singular matrix`。
- **元件首字母决定类型**:
  `R` 电阻 · `C` 电容 · `L` 电感 · `V` 电压源 · `I` 电流源 ·
  `D` 二极管 · `Q` BJT · `M` MOSFET · `J` JFET · `X` 子电路调用 ·
  `E/G/F/H` 受控源 · `K` 互感。
- **交付给 Multisim 的网表不要用 `.subckt` / `X` 子电路**:Multisim 14 导入时会把子电路实例整个丢掉,不报错(实测)。运放等用 `E` 受控源加电阻直接展开,写法见 `references_opamp_inverting.cir`。
- **半导体器件必须配 `.model`**(二极管、三极管、MOS 等),否则 `unknown model`。
  注意:Multisim 14 导入时会把这些器件换成 **虚拟器件,`.model` 参数全部丢失、改用 SPICE 默认值**(实测,导出网表里只剩 `.model ... NPN`)。连线不受影响,但数值会偏:二极管整流基本不变,BJT 放大器的静态工作点会明显偏移(参考 05:VC 从 5.55 V 变成 6.30 V)。交付含半导体器件的电路时,要提醒用户这一点,见第 4 步。
- **数值后缀(SPICE 大小写不敏感,这是头号大坑)**:
  `T`=1e12 · `G`=1e9 · `meg`=1e6 · `k`=1e3 · `m`=1e-3 · `u`=1e-6 · `n`=1e-9 · `p`=1e-12 · `f`=1e-15。
  **`M` 不是兆!`M`=`m`=1e-3。1 兆欧要写 `1meg`,写 `1M` 是 1 毫欧。**
- **分析命令**(按需选):
  - `.op` —— 静态工作点
  - `.dc <源> <起> <止> <步>` —— 直流扫描
  - `.ac dec <每十倍频点数> <fstart> <fstop>` —— 交流;做 AC 时电压源要带 `AC 1`
  - `.tran <步长> <终止时间>` —— 瞬态
- 输出纯网表文本,**不要 markdown 代码围栏,不要解释性散文混在 .cir 里**(注释用 `*` 开头的行)。
- 网表内容建议只用 ASCII(注释写英文),文件名和路径也尽量不带中文。Multisim 14 导入器对非 ASCII 字符的处理未经验证,这样最稳。

## 定位 Multisim

`scripts\find-multisim.ps1` 按以下顺序探测,**不默认任何路径**:

1. 注册表 `HKLM:\SOFTWARE\[WOW6432Node\]National Instruments\Circuit Design Suite\<版本>\MSI Parts\Core` 下的 `Path` 值,版本从高到低。
   版本键本身不存安装路径,路径在 `MSI Parts\Core` 子键里(14.0 实测)。
2. 所有本地盘 `Program Files (x86)` / `Program Files` 下的 `National Instruments\Circuit Design Suite *\multisim.exe`。

都找不到 → 问用户 `multisim.exe` 的完整路径,然后直接用它打开:

```
powershell -NoProfile -Command "Start-Process -FilePath '<multisim.exe 路径>' -ArgumentList '\"<circuit.cir 的完整路径>\"'"
```

## 排错速查

| 现象 | 处理 |
|---|---|
| ngspice `singular matrix` | 找悬空节点 / 给某节点补到地的直流通路(如大电阻) |
| ngspice `can't find model` / `unknown model` | 补 `.model` 定义 |
| `CHECK: FAIL` 但节点电压看着正常 | 有 `singular matrix` 警告:悬空节点被 ngspice 兜底了,照样要修 |
| AC 测出的截止频率明显偏低 | 用了 `v(out)`(实部),改成 `vdb(out)` |
| 交付网表单独跑报 `no ".plot", ".print"` | 正常:.tran/.ac/.dc 要把测量命令作为 `check.ps1` 的第二个参数 |
| ngspice `no convergence` / `Timestep too small` | 检查初值、加 `.options` 或调整步长;非线性电路给 `.ic` |
| 数值能跑出来但不达标 | 调元件值,重新自检,别直接交付 |
| Multisim 打不开 .cir | 确认路径无误、Multisim 没有残留启动对话框挡住主窗口 |
| Multisim 路径不存在 | 见《定位 Multisim》 |
| Multisim 启动弹 "Master Database cannot be accessed",导入日志里所有元件都 `Failed to create` | 与网表无关:NI Authentication Service(`niauth`)被禁用。管理员 PowerShell 执行 `Set-Service niauth -StartupType Automatic; Start-Service niauth` |
| 导入后少了元件(如运放不见了) | 网表里用了 `.subckt` / `X`,改成基本元件展开 |
| 导入后有图但不确定连线对不对 | 交叉的线看不出是否相连。让用户在 Multisim 里 Transfer → Export Netlist 导出网表,逐个引脚和原网表对比;导出的网表也能直接用 `check.ps1` 跑(分析命令通过第二个参数给,如 `"tran 50u 100m; meas ..."`) |
| Multisim 结果和 ngspice 有偏差,但连线没错 | 半导体器件被换成了默认参数的虚拟器件,在 Multisim 里换成元件库的同型号器件 |
