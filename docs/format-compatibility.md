# 格式兼容性与参考基准

本页定义 STLKIT **0.2.0** 的三角网格读取子集。依据规范组织支持范围，不表示完整格式认证、ISO 符合性认证或可制造性保证。解析器、CLI 和网页使用相同的默认严格读取路径；`parse_3mf(..., compatibility=true)` 仅供调用方显式选择旧包定位方式。

## 固定参考与资料许可

| 格式 | 本次固定参考 | 项目范围 | 原资料权利与使用方式 |
| --- | --- | --- | --- |
| STL | 3D Systems《StereoLithography Interface Specification》，1989 年；[美国国会图书馆的格式书目及布局说明](https://www.loc.gov/preservation/digital/formats/fdd/fdd000505.shtml) | ASCII / binary 三角形记录 | 原始规范版权属于原权利人；未取得可再分发许可，不随仓库附 PDF，也不将其标为 Apache-2.0 |
| OBJ | Wavefront Advanced Visualizer 3.0，Appendix B1 Object Files，[原文扫描副本](https://www.scratchapixel.com/lessons/3d-techiques-app-builders/obj-file-format/obj_spec.pdf) | ASCII polygonal geometry 子集 | Wavefront 原资料，仅作书目和链接引用；未确认再分发许可，不附原文件、不复制实现 |
| PLY | Greg Turk《The PLY Polygon File Format》，1.0，[原文](https://gamma-web.iacs.umd.edu/POWERPLANT/papers/ply.pdf) | ASCII / binary little-endian / binary big-endian 三角网格 | 原文含 Stanford 1994 版权、授权条件及免责声明；不是项目 Apache-2.0。仅链接参考，不随仓库重分发原文或软件 |
| 3MF | [3MF Core Specification v1.3.0](https://3mf.io/spec/core-v1-3-0/)，[官方版本对照](https://3mf.io/spec/) | Core geometry ingestion subset，加本页列明的 OPC 检查 | 3MF Consortium 规范仓库采用 [BSD-2-Clause](https://github.com/3MFConsortium/spec_core/blob/master/LICENSE)，Copyright (c) 2018, 3MF Consortium；仅引用链接与自行描述的实现范围 |

STL 不使用虚构的 STL v1/v2 版本号。3MF 官方表将 Core 1.3.0 对应 ISO/IEC 25422:2025，另列 Core 1.4.0 为后续修订。本次固定 **1.3.0 为参考**，不把实现一个读取子集写成“完整符合 ISO”或“完整兼容 Core 1.4.0”。Core 命名空间 URI 本身也不能证明实现了某一修订的全部行为。

资料参考与测试模型分开记账：自建模型 Apache-2.0；随附外部模型的 CC0-1.0 / BSD-2-Clause 作者、固定来源、哈希和改动见 [来源清单](../examples/external/manifest.json) 与 [完整第三方声明](../THIRD_PARTY_NOTICES.md)。没有把未知许可的网络文件加入样例。

## STL 三角形记录

`parse_stl_ascii`、`parse_stl_binary`、`parse_mesh` 与相应 STL 扫描入口使用统一输入契约。

- ASCII：`facet normal` → `outer loop` → 恰好三个 `vertex` → `endloop` → `endfacet`；支持空行、空格、Tab、CRLF。`solid` / `endsolid` 包装允许省略，这是项目的兼容行为，不宣称原始规范要求包装可省略，也不验证 solid 名称配对。
- binary：80 字节 header、little-endian uint32 面数、每面 50 字节。必须恰好为 `84 + 50×count`，面数大于零且可由当前实现索引。拒绝截断、任意额外尾字节及非有限顶点/法线。
- 每面末尾 2 字节 attribute 字段随记录消费，不解释 VisCAM / Magics 等私有颜色编码。输出不保留这些私有信息。
- 坏数字、未知非空 ASCII 记录、错误顺序、面中断/嵌套及不完整尾面失败。退化三角形可进入 Mesh，交给几何检查报告。
- 二进制 STL 才有真正的分块文件入口，扫描器必须调用 `finish()`；PLY、OBJ、3MF 不宣传为分块扫描。

证据：[STL 输入契约测试](../stl_input_wbtest.mbt)、[解析测试](../stl_wbtest.mbt)、[流式测试](../stream_wbtest.mbt)。

## OBJ 多边形几何子集

| 语句/引用 | 行为 |
| --- | --- |
| `v x y z` | 读取三个有限坐标；不能缺字段 |
| `v x y z w` | 仅接受 `w=1`；非单位 rational weight 明确拒绝，不静默忽略 |
| `vn i j k` | 恰好三个有限分量；不以解析成功证明其长度或方向正确 |
| `vt u [v [w]]` | 1–3 个有限坐标，建立纹理索引表；值不保存在最终 Mesh |
| `f v...` / `v/vt` / `v//vn` / `v/vt/vn` | 检查段数、非空必需段及对应表的实际索引范围；各表独立支持正/负索引，0 非法 |
| 多边形面 | 至少三个顶点；对支持的平面简单凸/凹多边形三角化；非平面、自交多边形失败 |
| `o/g/s/mtllib/usemtl` 等其他语句 | 跳过、不保存，也不验证其完整语义；不加载材质库或执行 `call/csh` |

引用按出现时的表解析，不支持向前引用。没有 `vt` 不能使用含纹理索引的面；负 `vt` 索引相对纹理表，不相对顶点表。截断、额外斜杠、空法线段、越界和非法数字明确失败。支持空格、Tab、CRLF 与以 `#` token 起始的行内注释；不支持反斜杠续行。顶点颜色扩展、自由曲线/曲面、NURBS、参数顶点及点线场景不属于已实现网格语义。

声明法线只在一个三角形的三个顶点法线完全相同时合并保存；其他情况置零。材质、UV、分组、平滑语义不做 round-trip 保真。此前跳过 `vt` 并接受未声明纹理索引的行为已收紧，不能继续把旧测试当作合法 OBJ 兼容证据。

证据：[新增格式边界测试](../format_profile_wbtest.mbt)、[OBJ 测试](../obj_wbtest.mbt)、[多边形测试](../polygon_wbtest.mbt)。

## PLY 1.0 三角网格子集

- 第一行 `ply`，第二行唯一且完整的 `format <encoding> 1.0`；encoding 只接受上述三种。header 接受 `element`、`property`、`comment`、`obj_info` 和空行，`end_header` 必须独占声明；未知、缺字段、额外字段的声明失败。
- `element` 数量为非负十进制整数字面量，最大 `2147483647`，不把浮点、指数或超范围计数转成 Int。仍受运行环境内存/数组容量限制，不承诺可处理上限规模。
- 每个 `vertex` 必须分别有且只有一个标量 `x/y/z`，允许重排；缺少、重复或 list 坐标失败。未知元素和属性按声明消费后丢弃，不等于未知 header 指令可以忽略。
- 支持 `char/uchar/short/ushort/int/uint/float/double` 及 `int8/uint8/int16/uint16/int32/uint32/float32/float64` 别名。ASCII 整数标量、列表长度和列表项均检查整数字面量及声明范围；例如 `uchar` 只能是 0..255，`uint` 标量可消费到 4294967295。
- 用作内部索引或列表长度时还须能用有符号 32 位 Int 表示，不能从 uint32 溢出成负数。list 长度类型及 face 顶点索引项类型必须为整数类型。
- 每个 face 顶点列表至少三个条目；即使其他面合法，也不静默丢弃 0/1/2 顶点的坏面。检查索引范围，平面简单多边形使用与 OBJ 相同的三角化路径。
- ASCII 默认按 header 顺序跨行消费；正文尾部 token 失败。二进制读完全部声明后必须到 EOF，截断或额外尾字节失败。`lenient_ascii=true` 仅兼容逐行记录中的额外值，不放宽 header、整数范围或坏面规则。
- 顶点必须有限；浮点属性不提供完整 IEEE 数值词法/属性语义认证。颜色、法线等额外属性不进入 Mesh。仅点云、无有效三角形的文件失败。

| 整数类型 | 下界 | 上界 |
| --- | --- | --- |
| int8 | -128 | 127 |
| uint8 | 0 | 255 |
| int16 | -32768 | 32767 |
| uint16 | 0 | 65535 |
| int32 | -2147483648 | 2147483647 |
| uint32 | 0 | 4294967295 |

证据：[类型/列表/坏面测试](../format_profile_wbtest.mbt)、[schema 测试](../ply_schema_wbtest.mbt)、[format/尾部测试](../ply_header_wbtest.mbt)、[读写测试](../ply_wbtest.mbt)。

## 3MF Core 1.3.0 核心几何读取子集

默认 `parse_3mf(data)`、自动 `parse_mesh(data)`、CLI 和网页都严格读取，不猜测唯一 `.model`。

1. ZIP 解包后检查重复部件名称及正斜杠路径。需要 `_rels/.rels` 和 `[Content_Types].xml`；关系及类型 XML 使用正确的 OPC 命名空间和完整结构。
2. 根关系须恰有一个完整 Type `http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel`；不能只匹配 `/3dmodel` 后缀。要求内部 Target，目标必须存在；拒绝外部 URI、点段、查询、fragment 和反斜杠目标。此有限路径规则不等同于完整 OPC URI/XSD 验证。
3. 验证关系 Id 唯一，内容类型 Default/Override 不重复；被选模型须声明 `application/vnd.ms-package.3dmanufacturing-3dmodel+xml`，根关系须声明 OPC relationships 类型。支持 Default 与 Override 定位；其他内容类型只解析声明，不验证每个缩略图/纹理等部件。
4. 模型根须为完整 Core URI `http://schemas.microsoft.com/3dmanufacturing/core/2015/02` 的 `model`；按 XML 局部命名空间作用域识别默认前缀和别名，不接受包含类似字符串的伪 URI。可选外部子树整体跳过，不能注入同名 Core 几何。
5. `resources` / `build` 唯一且顺序正确；对象 Id 为正的十进制整数且唯一。检查已处理几何标签的父子位置，一个对象不能重复 mesh、重复 components 或同时含二者；不把资源标签放到任意位置后仍提取。
6. 对象可含顶点/三角形网格或组件引用；build 仅展开被引用对象。验证顶点索引、缺失引用、有限坐标/变换及结果；递归深度超过 32 失败，包含循环引用也不会无限展开。
7. 只在 component 和 build item 上应用 12 数变换，并组合嵌套引用；不宣传不存在的“object transform 属性支持”。六种单位 micron/mm/cm/inch/foot/meter 转成毫米，未知单位或换算溢出失败。
8. 不支持的非空 `requiredextensions` 拒绝；可选扩展不保存。无三角形（如几何仅在 beam lattice）的 build 不返回伪造 Mesh。支撑对象的三角形可能被提取，但不评估支撑设计。

不包括完整 OPC/XSD、所有资源类型及顺序/属性约束、全套纹理/材料、Triangle Sets、Production、Slice、Beam Lattice、Secure Content、Toolpath、Volumetric 或私有切片工程配置的语义验证；不做颜色/材质/工程 round-trip。不能把“通过这组包结构检查”写成完整 3MF conformance。

### 显式旧包定位兼容

```moonbit nocheck
// 已知旧导出器没有规范关系/类型表时，由调用方显式选择。
let result = @stlkit.parse_3mf(data, compatibility=true)
```

此选项恢复旧关系表失败时寻找唯一 `.model`、旧 ZIP 名称归一化等定位行为，**不**放宽 Core 根、几何层级、Id、索引及 requiredextensions 检查。兼容读取成功不证明包符合规范。自动入口、CLI 和网页不启用此选项，也不因失败自行回退。

证据：[OPC/对象/命名空间测试](../format_profile_wbtest.mbt)、[单位/引用/变换及显式兼容测试](../three_mf_wbtest.mbt)、[有限数和扩展测试](../input_boundary_wbtest.mbt)、[13 个官方几何读取案例](../examples/conformance/README.md)。

## 验收与证据

```sh
moon check --target all --deny-warn
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon test --target native
node cmd/main/smoke.cjs
bash web/build.sh
node web/smoke.cjs
python scripts/prepare-scan.py
node scripts/corpus-cases.cjs --check
```

规范边界测试、自建解析值模型、官方/有许可外部模型和同几何跨格式对照分别提供证据。原始命令、结果、输入哈希、失败反馈统一在 [COMPARISON.md](../COMPARISON.md)。本轮正反例均自行构造；历史第三方模型及许可文件保持原样。
