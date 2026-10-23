# stlkit

MoonBit 三维网格检查与修复库。读取 STL、OBJ、3MF、PLY 的支持子集，提供拓扑检查、射线厚度采样、几何统计、简单修复和 SVG 预览。CLI 和浏览器复用同一份 MoonBit 核心代码。

[在线演示](https://mik1e80.github.io/stlkit/) · [库接口](README.mbt.md) · [范围与复现案例](docs/review-cases.md) · [项目对比](COMPARISON.md) · [变更记录](CHANGELOG.md)

本次修订版本 **0.1.4**。使用 [Mooncakes 0.1.4](https://mooncakes.io/docs/mik1e80/stlkit@0.1.4/) 或固定的 [v0.1.4 标签](https://github.com/mik1e80/stlkit/tree/v0.1.4) 复核本轮格式输入修复；0.1.3 及以前不包含这些新边界。[发布说明](docs/releases/0.1.4.md) 分开列明文档、代码和申报材料的调整。

在已有 MoonBit 项目中安装指定版本：

```sh
moon add mik1e80/stlkit@0.1.4
```

## 快速运行

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，获取源码后执行：

```sh
git clone --branch v0.1.4 --depth 1 https://github.com/mik1e80/stlkit
cd stlkit
moon update
moon run cmd/main examples/cube.obj --strict
moon run cmd/main examples/broken.stl --fix fixed.stl --strict
moon run cmd/main examples/broken.stl --fix fixed.stl --svg fixed.svg --strict
moon run cmd/main examples/torus.obj --svg torus.svg
```

网页支持本地打开 `web/index.html`，或访问在线演示。文件在浏览器本地处理，不上传；网页使用仓库内的编译产物，修改代码后需重建。

`--fix` 与 `--svg` 可同时使用：先写出最终网格，再由修复后的网格生成 SVG；无需自动修复时也按指定路径导出网格和预览。`--strict` 根据最终网格的复核结果退出，仍有薄壁等问题时两个输出仍会生成，并以 1 退出。输出路径按宿主平台规则转换为规范化绝对路径后比较（包括 .、..、分隔符和 Windows 大小写）；相同则在写入前拒绝。此词法比较不识别符号链接或硬链接别名。写入网格失败时不继续生成 SVG；SVG 写入失败时以 1 退出，已经写出的网格保留。

## 格式参考与支持范围

STL 参考 3D Systems 1989 年格式布局；OBJ 参考 Wavefront Advanced Visualizer 3.0 Appendix B1 的多边形几何；PLY 固定 1.0；3MF 以 Core 1.3.0 为参考，仅实现核心几何读取子集。每种格式的必需行为、拒绝条件、兼容选项、未实现语义、资料版权和可复现测试集中在 [格式兼容性说明](docs/format-compatibility.md)，不宣称完整标准/ISO 符合性或完整 Core 1.4.0 兼容。

OBJ 读取并验证 `vt` 及面引用，UV 不进入 Mesh；没有 `vt` 的 `v/vt` 引用失败。PLY 检查 ASCII 整数声明范围、list 类型和长度、非法 header，以及不足三个顶点的 face。3MF 默认要求正确的根关系和内容类型表、唯一对象 Id、精确 Core 命名空间及受支持几何层级；自动入口不会猜测唯一 `.model`。旧包定位只能由库调用方显式传 `parse_3mf(data, compatibility=true)`，不会放宽模型 XML/几何检查。

## 已实现范围

| 能力 | 内容与限制 |
| --- | --- |
| 读取 | ASCII / 二进制 STL；OBJ 顶点、法线、纹理坐标声明及引用检查、负索引、多边形面；3MF 核心三角网格、组件引用、变换和单位；ASCII / 大小端二进制 PLY |
| 多边形 | OBJ / PLY 平面简单凸、凹多边形三角化；自相交或非平面多边形报错 |
| 网格检查 | 边界边、非流形边、退化面、已保留声明面法线方向是否与三角形绕向相反；按共享边连通分量报告绕向、有符号体积和朝向状态 |
| 厚度采样 | 从确定性表面样本沿内法线取射线命中距离，报告样本最小值、命中数和参考阈值提醒 |
| 几何统计 | 面积、体积、AABB、PCA 定向包围盒、共享边连通部分、欧拉数、重心与转动惯量 |
| 简单修复 | 删除退化 / 重复面、简单边界环补洞、统一绕向和重算法线；修复后重新检查 |
| 输出 | ASCII / 二进制 STL、OBJ、ASCII / 二进制 PLY、SVG 和检查报告 |
| 流式统计 | 二进制 STL 分块处理，不构造完整 Mesh；仍保存顶点去重表与三角形边记录 |

不支持完整 3MF 扩展语义；非空 `requiredextensions` 明确拒绝，可选扩展可忽略。STL / OBJ 的非有限坐标及被读取法线、3MF 非有限变换与变换后的坐标溢出会报错。二进制流式统计校验声明法线是否有限，但不执行声明面法线反向检查。

### 声明面法线检查范围

当前仅检查**已保留的声明面法线方向是否与三角形绕向相反**：用声明向量与顶点绕序计算的单位几何法线做点积，结果小于 0 时计入 `wrong_normal_count`。声明向量长度不超过 `1e-9` 时跳过；零值计数不表示所有法线均已验证。

不检查声明法线是否单位化、是否垂直于三角形，或是否与几何法线精确一致。例如，与几何法线正交的声明向量点积为 0，不计为反向；长度为 2 的同向向量也不会因此报错。退化面由单独的退化检查报告，不靠这项证明法线有效。

OBJ 的 `vn` 是逐顶点数据。本库只在一个三角形的三个顶点法线逐分量完全相同时保留为单个声明面法线；缺失或三个向量不同时置零，之后跳过声明面法线反向检查。它不会验证或保留完整的平滑顶点法线场，也不会将不相同的 `vn` 自动判为错误。相邻三角形绕向由另一项检查处理。

因此，报告中的兼容字段“错误法线”只表示已保留声明面法线的反向计数；不是完整法线正确性检查。`normal_scope_wbtest.mbt` 给出正交、非单位及不同 OBJ 顶点法线的可执行边界案例。

### 格式探测与解析

`detect_format(data)` 返回 `Ascii`（ASCII STL）、`Binary`（二进制 STL）、`Obj`、`ThreeMF`、`Ply` 或 `Unknown`。它依据内容提供解析路由提示，不使用文件后缀，也不证明文件有效或完整符合规范。

探测先检查 ZIP/3MF 候选与 PLY 文件头，再检查二进制 STL 的计数和精确文件长度。其余文本逐行查找行首几何记录：STL 的 `facet/vertex/endfacet` 或 OBJ 的 `v/vn/f`；仅有 `solid/endsolid` 时作为 ASCII STL 候选。注释和对象名称中嵌入这些单词不会被当成几何记录。文本扫描直到找到提示或到达末尾，最坏为 O(n)，不以 512 字节作为识别上限。

`parse_mesh()` 将已识别格式送到对应解析器；`Unknown` 文本依次尝试 ASCII STL 和 OBJ，均失败时返回“无法识别网格格式”并附两者原因。已识别格式的解析错误直接保留，不因文件损坏而换一种格式蒙混通过。`Unknown` 不再是 OBJ 的别名；`parse_stl()` 明确拒绝 OBJ、PLY 和 3MF。

可复现：`examples/long-header.stl` 的 solid 名称长 2048 个字符，首个 facet 位于 512 字节之后；`examples/obj-stl-keywords.obj` 的注释和对象名称包含 STL 关键字。两者均应按实际内容显示正确格式、读取 12 个三角形；库、CLI、网页都有回归检查。

### ASCII PLY 的读取规则

默认 `parse_ply(data)` 按 header 声明的元素、记录数量、属性及列表长度顺序连续读取正文 token；支持多条记录同一行、记录跨行，以及空格、制表符、CR / LF 等 ASCII 空白。未知元素和属性按声明消费后丢弃，不跳过未声明的行尾内容；正文不足或消费完声明后仍有非空白数据会报错。面先于顶点声明时，等顶点表读完再验证索引和三角化。

异常文件若每条记录独占一行、行尾多出未声明值，可显式调用 `parse_ply(data, lenient_ascii=true)`。该兼容模式会丢弃每条记录的行尾余项，不能用于同一行多条记录或跨行记录，行内属性不足会报错。默认解析、`parse_mesh()`、CLI 和网页均不自动回退；此开关不改变二进制 PLY 的读取。

这里的“严格”指正文按声明消费，不代表完整 PLY 规范验证或所有属性语义支持。本库仍以三角网格为目标，不保留颜色、材质等附加属性，也不接收只有点云而没有面的模型。元素 / 属性顺序依据 [Greg Turk 的 PLY 格式说明](https://gamma-web.iacs.umd.edu/POWERPLANT/papers/ply.pdf)。

自建案例：[同一行的顶点与面](examples/ascii-packed.ply) 读取为 2 个三角形、面积 1 mm²；它是开放方片，几何复核仍会提示边界边。[未声明尾随值](examples/ascii-extra-values.ply) 默认报错，仅显式兼容模式可读取。回归见 [PLY 测试](ply_wbtest.mbt)。

## STL 与 PLY 输入契约

PLY 第一行必须为 `ply`，第二行必须为唯一、完整的 `format <编码> 1.0` 声明；编码仅支持 `ascii`、`binary_little_endian`、`binary_big_endian`。缺失、重复、字段不全 / 多余、版本不为 `1.0`，或把声明放在注释 / element 后都会报错。合法注释应放在 format 之后。二进制正文必须精确消费所有已声明元素与属性，拒绝任意多余尾部字节（包括零填充、空格和换行）。`lenient_ascii=true` 不放宽 header 或二进制尾部规则。格式依据见 [Greg Turk 的原始 PLY 说明](https://gamma-web.iacs.umd.edu/POWERPLANT/papers/ply.pdf)，这些边界检查不表示完整规范认证。

PLY 在读取正文前检查每个 `vertex` 元素：必须各声明一个标量 `x`、`y`、`z`，缺失、list 型坐标和重复坐标属性都会报错，不将缺失值补零。规则同样适用于 ASCII、大小端二进制及 `lenient_ascii=true`；坐标顺序可变，未知属性仍按声明消费。自建反例 [missing-z.ply](examples/missing-z.ply) 应明确报“vertex 缺少 z”，真实零坐标仍合法。

自建反例 [missing-format.ply](examples/missing-format.ply) 虽有合法 ASCII 三角形正文，仍须明确拒绝，不能猜测为 ASCII。回归见 [PLY header 与尾部测试](ply_header_wbtest.mbt)。

STL 输入边界：二进制文件必须恰好为 `84 + 50 × 头部三角形数` 字节，数量须大于 0，法线与顶点都须为有限数；截断和任意尾部多余字节均拒绝。`parse_stl_binary()`、`stream_stl_binary()` 与 `StlScanner` 使用同一规则，分块调用必须调用 `finish()` 才能确认输入完整。

ASCII 全量与整块流式入口共用逐面状态机：`facet normal` → `outer loop` → 恰好三个 `vertex` → `endloop` → `endfacet`；支持空行、空格、制表符和 CRLF，`solid` / `endsolid` 包装可省略。未知非空行、坏数字、面中断 / 嵌套及不完整尾面均报错，不忽略坏面。退化三角形仍可解析，由几何检查判断。自动格式识别只是路由提示，不证明 STL 有效；结构长度不符的二进制输入可能被标为未知，但仍会解析失败。回归见 [统一输入契约测试](stl_input_wbtest.mbt)。

## 如何解释报告

报告表示**已覆盖网格项的复核结果，不构成可打印结论**。本库不验证网格自相交、全部非流形顶点、支撑需求、喷嘴适配、摆放方向、材料或切片工艺。

- `--strict` 在发现需复核问题时退出 1；普通模式可输出带问题的报告并退出 0。参数或读取失败也退出 1，脚本须结合输出解释原因。
- STL / OBJ / PLY 按毫米解释，使用者需确认比例；3MF 按声明单位换算为毫米。
- 拓扑按默认 `1e-6` mm 坐标格子重建，不保留原始共享顶点身份。格子边界两侧的近点可能不合并；库的 `validate(mesh, tolerance)` 可调整容差。
- 边计数闭合不证明无自交或无非流形顶点；体积、质量属性和欧拉数需结合闭合、绕向及曲面前提解释。

- 简单补洞不解决设计薄壁、复杂洞或自交；修复后仍需复核。

CLI 和网页仅在 `PrintabilityReport::mass_properties_available()` 为真时输出重心和主惯量：网格非空、边计数闭合、无退化面、绕向一致、无需局部翻面，且全部分量为正体积、无潜在嵌套 / 重叠标记；否则明确显示“未评估”。薄壁提醒或参考阈值不单独阻止质量属性输出。此条件不证明无自相交或无非流形顶点，也不保证任意尺度下的数值精度。

[闭合但含退化面的反例](examples/degenerate-closed.obj) 具有一致绕向和正体积，仍应暂停质量属性：运行 `moon run cmd/main examples/degenerate-closed.obj --strict`，报告应显示“重心 未评估”“主惯量 未评估”，并以 1 退出。

## 按连通分量检查绕向

`check_winding_default(mesh).components` 为每个共享边连通分量返回原始面索引、局部绕向一致性、边闭合状态、有符号体积及 `PositiveVolume` / `NegativeVolume` / `Indeterminate` 状态。总体 `signed_volume` 仅作汇总，不能证明每个零件朝向正确。

例如，体积 8 的大立方体朝外、体积 1 的小立方体朝里时，总和仍是 +7，但报告分别列出 +8、−1，并触发复核、暂停统一入口的厚度评估。CLI 和网页均显示分量明细；回归见 [分量绕向测试](winding_component_wbtest.mbt)。

统一检查入口返回的 `PrintabilityReport` 可直接查询 `inward_component_count()`，并通过 `winding.components` 查看对应分量；兼容方法 `inward()` 等价于计数大于 0。计数从分量明细计算，不使用全局体积。`needs_review()` 独立检查分量朝向：任一负体积、朝向未定或可能嵌套 / 重叠的分量都会触发复核，即使报告中已有厚度命中结果。零个负体积分量也不保证无需复核。入口回归见 [复核判断测试](printability_wbtest.mbt)。

`unify_winding()` 先统一各分量相邻面的绕向；对闭合、可定向且包围盒与其他分量不重叠的负体积分量，按“独立实心零件”假设整体翻转。`RepairResult.reoriented_components` 单独记录整体翻转数，`flipped_faces` 仍记录局部绕向调整，`changed()` 会识别两者。

负体积也可能表示合法内腔。包围盒重叠或接触时只标记“可能嵌套或重叠”，保留壳层整体符号并人工复核；这不是精确的壳层包含或相交判定。开放、零体积、非流形或绕向冲突的分量不据此判断朝内外，也不承诺被自动修好。

## 厚度采样与场景设置

```sh
moon run cmd/main examples/cube.obj --min-thickness 0.8 --samples 1000 --strict
moon run cmd/main examples/cube.obj --nozzle 0.4 --supports off --min-thickness 0.8 --strict
```

`--min-thickness` 是使用者给定的非负有限参考阈值，单位毫米，默认 0.8；0 关闭薄壁阈值提醒。`--samples` 是 1..100000 的射线预算，默认 1000。

喷嘴和支撑参数**只记录上下文**，不参与工艺判定，也不自动推导壁厚阈值。单独开启支撑不会使网格检查转为通过。

采样按面编号选取，结果受面顺序、样本预算、朝向和射线起点偏移影响，不按面积均匀取样。它可能漏掉局部薄处，不能称为全局最薄处；无命中表示未评估。统一复核入口在空、开放、退化、任一分量朝向非正或未定、可能嵌套 / 重叠时暂停厚度评估。每条射线遍历所有面，时间约 O(samples×faces)。

仓库提供明确安排面顺序的反例：同一个含 0.05 mm 薄板的模型，1000 次采样报告约 1 mm，3084 次约 0.05 mm。该反例及同模型不同场景的原始报告见 [复现案例](docs/review-cases.md)。

## 射线命中距离

`Mesh::ray_cast(origin, dir)` 在内部归一化有限的非零方向，返回最近命中的 `RayHit`。`distance` 是起点到命中点的欧氏距离，单位与网格坐标相同；`point` 是命中坐标。将方向乘以正数不会改变射线及其距离，负倍数则改变射线朝向。例如，从单位立方体下方 (0.25, 0.5, -1) 沿 (0, 0, 2) 发射，最近命中 z=0，距离为 1，而不是参数值 0.5。

零方向、非有限起点或方向返回 `None`；无命中时同样返回 `None`，该返回类型不区分这些原因。归一化先按方向的最大绝对分量缩放，避免直接平方极大 / 极小方向造成溢出或下溢。求交仍使用 Double 和原有平行 / 自交阈值，不是任意几何尺度下的精确计算保证。

底层 `ray_triangle(origin, dir, a, b, c)` 保持返回射线参数 `t`：命中点为 `origin + dir*t`。它不归一化方向；只有单位方向下参数才等于欧氏距离。不要把这个底层返回值与 `RayHit.distance` 混淆。

此次修复不改变函数签名。依赖旧版非单位方向下参数值的 `ray_cast()` 调用方应改用正确的几何距离；需要命中点时直接读取 `hit.point`，不要将距离再次乘以原始非单位方向。轴向、斜向、极大 / 极小正比例方向及无效输入回归见 `ray_direction_wbtest.mbt`。

## PCA 定向包围盒

`Mesh::oriented_bounding_box()` 对去重顶点的协方差矩阵执行 **Jacobi 对称特征分解**，一次取得完整正交轴组，再投影顶点求盒子中心和尺寸。两重或三重特征值也使用完整基，不再分别叉乘求轴。

PCA 给出近似包围盒，**不保证最小体积**。重复或很接近的特征值可能使主轴方向不唯一或随数值扰动变化；旋转后的方柱、立方体不保证恢复原始边方向。平面、直线或单点输入可有零尺寸，不能把它们解释成实体体积。计算仍受浮点精度和输入数值尺度限制。

公开的 `symmetric_eigendecomposition()` 返回按特征值降序配对的 `values` 与正交 `vectors`。需要完整基时应调用该接口；旧 `symmetric_eigenvector()` 仅作单向量查询，同一重根重复查询不产生不同向量。方柱、圆柱、矩阵重建与特征方程测试见 [PCA 回归](pca_regression_wbtest.mbt)。

## 大文件与内存

```sh
moon run cmd/main examples/review/cubes-64.stl --stream-only
moon run cmd/main examples/cube.stl --bench
```

`--stream-only` 只做二进制 STL 分块统计，不构造完整网格，也不执行绕向、厚度、修复或工艺判定。它输出逻辑存储计数；`--bench` 会同时运行全量解析，不是纯流式的低内存入口。

分块文件读取缓冲为 256 KiB，但顶点表 V 和边记录 R 仍随输入增长。非退化三角形 R=3F，排序前包含重复边。空间为 O(V+R+chunk)，排序还可能使用临时存储，**总内存不固定**。

`StlScanner::storage()` 的计数及缓冲峰值不是 RSS，不包含容器容量、哈希桶、对象头、分配器或运行时。1、16、64 个分离立方体的实际计数见复现案例；不提供未经实测的固定内存节省比例。

## 验证与开发

```sh
moon check --target all --deny-warn
moon build
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon test --target native
node cmd/main/smoke.cjs
bash web/build.sh
node web/smoke.cjs
node scripts/review-cases.cjs
```

测试包含解析、拓扑、修复、采样、输入边界和 PCA 的解析对照。网页回归执行实际 MoonBit 编译产物与最小 DOM，验证报告逻辑，不代替布局检查。案例脚本重建输入、调用实际 CLI 并核对原始报告；CI 检查已保存案例是否过期。

## 依赖与许可

核心几何使用 MoonBit core；3MF 依赖 `hustcer/fzip`、`Milky2018/xml`，CLI 另用 `moonbitlang/x` 与 `moonbitlang/async`。库支持 wasm、wasm-gc、JS、native；CLI 文件读取支持 wasm、native。

项目采用 [Apache-2.0](LICENSE)。原有 17 个外部 3MF 样例来自 3MF Consortium；新增外部 CAD、扫描及 Cura 样例分别采用 BSD-2-Clause 或 CC0-1.0，作者、固定来源、改动和完整条款见 [第三方声明](THIRD_PARTY_NOTICES.md) 与 [逐文件清单](examples/external/manifest.json)。自建案例采用 Apache-2.0；网页分发许可存于 `web/licenses/`。API 与模块组织参考 trimesh，不宣称厚度能力独有。


模型实测、失败反馈、外部来源与许可证、薄壁采样和 100k/500k/1m 大文件结果统一见 [COMPARISON.md](COMPARISON.md)。完整原始输出和命令可逐项复核；解析成功不等于网格或工艺通过。
