# multisim-spice

> A Claude Code skill that turns natural-language circuit descriptions into ngspice-verified SPICE netlists, ready to import into NI Multisim.

**作者:** 左岚 · **元数据:** 见 [`project.yaml`](project.yaml)

**Flow:** you describe a circuit in plain language → Claude generates a SPICE netlist → the bundled ngspice runs a batch self-check → on pass, the netlist is opened in Multisim and you press F5 to simulate.

## Why

The usual "AI draws a circuit" workflow has a closed loop only with a human in it: the AI emits something, you simulate, you tell it what's wrong. This skill closes the loop with **ngspice as the source of truth** — Claude doesn't hand you a netlist it hasn't run itself.

## Features

- **No external AI API.** Claude itself (running the skill) generates the netlist — no Gemini / OpenAI / Anthropic-API key needed beyond Claude Code.
- **No Python.** Pure `SKILL.md` + a vendored Windows binary. Nothing to `pip install`.
- **Bundled ngspice 46 (Windows x64)** for offline self-checking. Zero install.
- **Self-verifying.** Claude scans ngspice output for errors and compares numeric results against your design spec, iterating until both pass.
- **Multisim path auto-detect.** Probes common install paths and the Windows registry; asks only on miss.

## Requirements

- **Windows** — the bundled ngspice is a Windows x64 binary; Multisim is Windows-targeted; the skill drives the OS via PowerShell.
- **NI Multisim 14.x** installed (other versions likely work — extend the candidates list in `SKILL.md`).
- **Claude Code** — this is a Claude Code skill, invoked via its Skill mechanism.

## Install

Clone or copy this folder into one of Claude Code's skill directories.

**Personal (available across all your projects):**
```powershell
git clone https://github.com/zuoliangyu/multisim-spice "$env:USERPROFILE\.claude\skills\multisim-spice"
```

**Project-scoped (available only inside one project):**
```powershell
git clone https://github.com/zuoliangyu/multisim-spice <project-root>\.claude\skills\multisim-spice
```

That's it — no `pip install`, no API keys, no PATH edits.

## Usage

In Claude Code, just describe what you want:

> "Design an RC low-pass filter with 1 kHz cutoff, 5 V supply, and open it in Multisim."

Claude auto-routes to this skill (description match), then:

1. Asks for any missing critical params.
2. Writes `<circuit_name>.cir` in your working directory.
3. Runs the bundled `ngspice -b` on it; if results don't meet the spec, fixes the netlist and re-runs.
4. Opens the verified `.cir` in Multisim. **You press F5** to run the simulation there.

You can also invoke explicitly: `/multisim-spice`.

## 实战截图

下面三张是用本 skill 设计一阶 RC 低通(`fc = 1 kHz`、`R = 1.59 kΩ`、`C = 100 nF`)的真实过程截图。

**1. 生成 / 编辑网表** — Claude 写出干净的 `.cir`,并另存一份 `_check.cir` 副本加上 ngspice 专用的 `.print` 行用于自检(干净版本里不留):

![编辑 .control 自检副本](01-edit.png)

**2. ngspice 自检 + 关键指标核对** — 批处理跑出 81 个频点,−3 dB 点正中 1 kHz,相位 −44.97°(理论 −45°),衰减斜率严格 −20 dB/decade:

![AC 扫描结果与 Multisim 路径探测](02-selfcheck.png)

**3. 最终交付 + 导入 Multisim** — 网表、参数表一并给出,自动启动 Multisim 并把 `.cir` 传给它(用户自己按 F5):

![交付清单与 Multisim 启动](03-deliver.png)

## How it works

| Step | What happens | Where |
|---|---|---|
| 1. Clarify | Resolve ambiguous specs (Vcc, frequencies, gain, …) | conversation |
| 2. Generate | Claude writes a clean SPICE netlist per standard conventions | `<circuit>.cir` |
| 3. Self-check | `ngspice_con.exe -b <circuit>.cir` — scan for errors + check numbers vs spec; iterate on miss | bundled ngspice |
| 4. Hand off | `Start-Process multisim.exe <circuit>.cir`; user presses F5 | NI Multisim |

Full workflow, SPICE conventions and troubleshooting live in [`SKILL.md`](SKILL.md).

## Customizing the Multisim search path

Open `SKILL.md`, jump to the **`## 定位 Multisim`** section, and add your install path to the `$candidates` array. The skill also probes the Windows registry under `HKLM:\SOFTWARE\WOW6432Node\National Instruments\Circuit Design Suite`, and falls back to asking the user.

## What if I don't want the bundled ngspice?

Delete `vendor/Spice64/` and edit `SKILL.md` to point at an external `ngspice.exe` — for example:

- `conda install -c conda-forge ngspice` (drops a Windows build into `<env>/Library/bin/`)
- Download a different version from [ngspice on SourceForge](https://sourceforge.net/projects/ngspice/files/ng-spice-rework/)

## Limitations

- **Windows-only.** Bundled binary + PowerShell driver + Multisim's primary platform.
- The deliverable `.cir` should stay standard SPICE — Multisim's importer dislikes ngspice-only constructs (e.g., `.control` blocks). The skill keeps these out of the final file.
- Multisim's netlist import auto-lays-out the schematic; expect to manually tidy non-trivial circuits.
- **No auto-F5.** The skill opens the circuit in Multisim but does NOT press F5 for you — intentional, to avoid timing/focus fragility.

## License

This skill's own code and documentation are released under the **MIT License** — see [`LICENSE`](LICENSE).

The bundled ngspice in `vendor/Spice64/` is **independent third-party software** under its own (BSD-style) license. See [`NOTICE`](NOTICE) and `vendor/Spice64/docs/COPYING`.

## Acknowledgments

- [ngspice](https://ngspice.sourceforge.io/) — the open-source SPICE engine that makes the self-check loop possible.
- NI Multisim — the target schematic / simulation environment.
