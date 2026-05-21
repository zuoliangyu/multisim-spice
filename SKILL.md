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
- **Multisim** —— 用户机本地安装的 NI Multisim(14.x 已验证):
  - **不要写死路径。** 每次第 4 步调用前用《定位 Multisim》块探测 `multisim.exe`,找不到再问用户。

## 工作流程

### 第 1 步 · 厘清需求

生成网表前,确认描述里缺失或模糊的关键参数:

- 电源电压、信号源幅度/频率
- 关键元件值或设计指标(截止频率、增益、静态电流、时间常数……)
- 需要哪种分析:静态工作点(.op)、直流扫描(.dc)、交流(.ac)、瞬态(.tran)

能合理假设的就假设并说明;无法合理假设的关键参数,先问用户,不要乱猜。

### 第 2 步 · 生成 SPICE 网表

按下方《SPICE 网表规范》生成,用 Write 工具存成 `<电路名>.cir`,放到用户当前工作目录(除非用户指定别处)。这一份是 **最终交付给 Multisim 的干净网表**,不要放 ngspice 专有语法。

### 第 3 步 · 用 ngspice 自检(必做)

不要跳过。运行(PowerShell;把 `<SKILL_DIR>` 换成本 SKILL.md 所在目录的绝对路径):

```powershell
& "<SKILL_DIR>\vendor\Spice64\bin\ngspice_con.exe" -b "<circuit.cir 的完整路径>"
```

**.op 电路** 直接跑上面的命令即可,批处理模式会打印各节点电压。

**.tran / .ac / .dc 电路** 批处理模式默认不打印波形数据。复制一份 `<电路名>_check.cir`,在副本里加输出指令再跑,**最终交付的 .cir 保持干净**。两种加法二选一:

- 加 `.print` 行,例如 `.print tran v(out) i(v1)` / `.print ac vdb(out) vp(out)`
- 或加 ngspice 专有的控制块:
  ```
  .control
  run
  print v(out)
  .endc
  ```

**判读输出 —— 两层检查:**

1. **能不能跑** —— 扫描这些报错关键词,出现就说明网表有问题:
   `Error` · `parse error` · `singular matrix` · `unknown` · `no convergence` ·
   `Timestep too small` · `aborted` · `NaN` · `inf`
   - `singular matrix` 多半是有悬空节点 / 某节点没有到地的直流通路。
   - `unknown model/subckt` 是缺 `.model` 或 `.subckt` 定义。
2. **对不对** —— 把数值跟设计指标比对,而不只是"没报错"。例如要求截止频率 1kHz,就看 AC 结果里 −3dB 点是不是在 1kHz 附近;要求某点 5V,就看是不是 5V。

有问题 → 改网表 → 重跑,直到既跑通又满足指标。然后把关键结果用人话讲给用户。

### 第 4 步 · 导入 Multisim

自检通过后,先用《定位 Multisim》块拿到 `$exe`,再启动 Multisim 把网表传给它:

```powershell
# $exe 来自《定位 Multisim》探测结果
$cir = "<circuit.cir 的完整路径>"
Start-Process -FilePath $exe -ArgumentList "`"$cir`""
```

然后告诉用户:Multisim 会打开并把网表导入成原理图(可能弹出网表导入对话框,按提示确认即可);**导入完成后由用户自己按 F5 运行仿真**。不要尝试自动按 F5。

## SPICE 网表规范

- **首行是标题行**:SPICE 把网表第一行当标题/注释,不解析。永远写一行标题占位。
- **末行是 `.end`**。
- **节点 0 是地**。每个节点都要有到地的直流通路,否则会 `singular matrix`。
- **元件首字母决定类型**:
  `R` 电阻 · `C` 电容 · `L` 电感 · `V` 电压源 · `I` 电流源 ·
  `D` 二极管 · `Q` BJT · `M` MOSFET · `J` JFET · `X` 子电路调用 ·
  `E/G/F/H` 受控源 · `K` 互感。
- **半导体器件必须配 `.model`**(二极管、三极管、MOS 等),否则 `unknown model`。
- **数值后缀(SPICE 大小写不敏感,这是头号大坑)**:
  `T`=1e12 · `G`=1e9 · `meg`=1e6 · `k`=1e3 · `m`=1e-3 · `u`=1e-6 · `n`=1e-9 · `p`=1e-12 · `f`=1e-15。
  **`M` 不是兆!`M`=`m`=1e-3。1 兆欧要写 `1meg`,写 `1M` 是 1 毫欧。**
- **分析命令**(按需选):
  - `.op` —— 静态工作点
  - `.dc <源> <起> <止> <步>` —— 直流扫描
  - `.ac dec <每十倍频点数> <fstart> <fstop>` —— 交流;做 AC 时电压源要带 `AC 1`
  - `.tran <步长> <终止时间>` —— 瞬态
- 输出纯网表文本,**不要 markdown 代码围栏,不要解释性散文混在 .cir 里**(注释用 `*` 开头的行)。

## 定位 Multisim

第 4 步调用前,按下面的顺序找 `multisim.exe`,**找不到再问用户**,不要默认任何路径:

```powershell
# 1) 常见安装位置候选(覆盖 14.0~14.3,C: 和 D: 盘)
$candidates = @(
  "C:\Program Files (x86)\National Instruments\Circuit Design Suite 14.3\multisim.exe",
  "C:\Program Files (x86)\National Instruments\Circuit Design Suite 14.2\multisim.exe",
  "C:\Program Files (x86)\National Instruments\Circuit Design Suite 14.1\multisim.exe",
  "C:\Program Files (x86)\National Instruments\Circuit Design Suite 14.0\multisim.exe",
  "D:\Program Files (x86)\National Instruments\Circuit Design Suite 14.3\multisim.exe",
  "D:\Program Files (x86)\National Instruments\Circuit Design Suite 14.0\multisim.exe"
)
$exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

# 2) 都没命中时,扫一下注册表里所有装过的 CDS 版本
if (-not $exe) {
  $rk = "HKLM:\SOFTWARE\WOW6432Node\National Instruments\Circuit Design Suite"
  if (Test-Path $rk) {
    foreach ($v in Get-ChildItem $rk -ErrorAction SilentlyContinue) {
      $p = Get-ItemProperty $v.PSPath -ErrorAction SilentlyContinue
      foreach ($cand in @($p.'(default)', $p.InstallPath, $p.Path)) {
        if ($cand -and (Test-Path (Join-Path $cand "multisim.exe"))) {
          $exe = Join-Path $cand "multisim.exe"
          break
        }
      }
      if ($exe) { break }
    }
  }
}

# 3) 还是找不到 → 问用户 multisim.exe 的完整路径
```

用户给了新路径后,可以建议他把这个路径补进上面的 `$candidates` 列表,下次就免问。

## 排错速查

| 现象 | 处理 |
|---|---|
| ngspice `singular matrix` | 找悬空节点 / 给某节点补到地的直流通路(如大电阻) |
| ngspice `unknown model` | 补 `.model` 定义 |
| ngspice `no convergence` / `Timestep too small` | 检查初值、加 `.options` 或调整步长;非线性电路给 `.ic` |
| 数值能跑出来但不达标 | 调元件值,重新自检,别直接交付 |
| Multisim 打不开 .cir | 确认路径无误、Multisim 没有残留启动对话框挡住主窗口 |
| Multisim 路径不存在 | 见《定位 Multisim》 |
