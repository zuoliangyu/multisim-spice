# .ms14 格式参考样本

`scripts/patch-ms14.ps1` 里写死的字段名、字符串和箭头坐标，都是从这几个 Multisim 14.0 自己保存的工程里对比出来的。以后要支持新的器件类型，或者核对某个改动是否合理，就照这个办法：在 Multisim 里做一个只差一处的样本，解压后和已有样本对比。

| 文件 | 内容 | 用来确定 |
|---|---|---|
| `bjt_npn_and_pnp.ms14` | 新建设计，手动放置的虚拟 BJT_NPN 和 BJT_PNP 各一个 | PNP 与 NPN 的差别：族名 / 类型 / 描述字符串，以及发射极箭头（NPN (60,71)(61,75)(57,76)，PNP (58,77)(57,73)(61,72)）；其余线段、引脚完全相同 |
| `mos_n_type_imported.ms14` | 网表导入后另存：三个 PMOS 被导成虚拟 `MOS_N_4T`；模型名 `MP` 的那个被换成数据库三极管 MPS2222，没有连线 | N 型 MOS 的字符串与箭头 (58,61)(55,63)(58,65)；MOS 第 4 脚名为 `SUB`；"模型名与数据库模型同名会被替换" 这一现象 |
| `mos_jfet_p_type_replaced.ms14` | 同类导入工程中，一个 MOS 用 Replace 换成 `MOS_P_4T`、一个 JFET 换成 `JFET_P`，另一个 JFET 保持 `JFET_N` | P 型 MOS 箭头 (56,61)(59,63)(56,65)；JFET N (48,70)(51,72)(48,74) / P (50,70)(47,72)(50,74)；P 型的 `@` → `B` 字段、MOS 的 `CiaDOUBLE` 366 → 368 |
| `mos_wl_instance_params.ms14` | 在 Value 页把一个 MOS 的 W / L 改成 2e-5 / 2e-6 | 实例参数存在元件 `CiaParamList` 的第一个字符串里（`" L=2e-006  W=2e-005"`），由 SPICE 模板的 `%S0` 接到器件行末尾 |
| `ac_sweep_output_selected.ms14` | 导入 `02_rc_lowpass.cir` 后，在 Analyses 里设好 AC 扫描（10 Hz–100 kHz、每十倍频 100 点）并只选 V(out) | `SimState` 里 AC 参数的写法（纯数值 `double`）；选中输出 = `Nodes` 列表中 `NAME:string{$out}` 且 `GROUP:long{768}`；`ActiveAnalysis="ac"`、`SimStateDataInOldVersion="0"` |

解压方式见 `scripts/patch-ms14.ps1` 里的 `ReadDesign`：文件头 36 字节标识加上 `uint32` 总长和一个 0，然后是若干块，每块依次是解压后大小、压缩后大小和 PKWARE DCL implode 数据，每块最多 900000 字节。
