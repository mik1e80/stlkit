# stlkit：接口与实现

MoonBit 的 STL / OBJ / 3MF / PLY 网格工具链。本次修订版本为 **0.1.1**；安装、命令行和网页版入口见 [README.md](README.md)。Mooncakes 使用 `moon add mik1e80/stlkit@0.1.1`，源码固定到 [v0.1.1](https://github.com/mik1e80/stlkit/tree/v0.1.1)。0.1.0 不包含本轮修复，复核范围及迁移说明见 [0.1.1 发布说明](docs/releases/0.1.1.md)。

## 数据与单位

`Vec3` 使用 Double；`Triangle` 保存三个点及声明法线；`Mesh` 保存三角形数组。解析阶段展开 OBJ / PLY / 3MF 的索引和对象引用，不保留原文件的独立顶点身份。

拓扑分析按容差重建顶点关系。全量校验、流式扫描、PLY 导出和定向包围盒共用完整的三分量坐标键，不截断坐标位数，也不转换为 32 位整数。哈希冲突通过完整相等判定区分。

默认焊接容差为 1e-6 毫米，公开的 `validate(mesh, tolerance)` 可调整容差。量化不是距离搜索：格子边界两侧即使很近也可能分开。STL / OBJ / PLY 按毫米解释；3MF 的声明单位换算到毫米。

## 读取与导出

| 接口 | 用途 |
| --- | --- |
| `parse_mesh(data)` | 按内容检测 STL / OBJ / 3MF / PLY，返回 `Result[Mesh, String]` |
| `parse_stl_ascii(text)` / `parse_stl_binary(data)` | STL 读取 |
| `parse_obj(text)` | OBJ 顶点、法线、负索引和多边形面；支持空格、制表符、CRLF、行内注释 |
| `parse_3mf(data)` | ZIP / XML、对象引用、组件变换与单位 |
| `parse_ply(data, lenient_ascii=false)` | ASCII / 小端 / 大端 PLY；默认连续按声明消费正文，不丢弃行尾 token |
| `write_stl_ascii(mesh)` / `write_stl_binary(mesh)` | STL 导出 |
| `write_obj(mesh)` | OBJ 导出 |
| `write_ply_ascii(mesh)` / `write_ply_binary(mesh)` | PLY 导出，统一容差去重 |
| `write_mesh(mesh, filename)` | 按输出后缀选择格式 |

OBJ / PLY 的三角形原样保留，由校验层检查退化性。平面简单凸多边形保留扇形切分；凹多边形用耳切，并保持绕向。自相交和非平面多边形明确报错，不猜测几何。未实现 OBJ 材质渲染以及完整 3MF 颜色、材料与扩展语义。

ASCII PLY 默认严格按声明消费正文：记录可跨行或共用一行，未知元素、标量与变长列表照声明读取后丢弃，拒绝缺失值和声明外的尾随 token。面先声明也可读取，索引验证延后到顶点表完整之后。header 仍按行读取；“严格”描述正文布局规则，不表示完整 PLY 规范验证。仅有点云的文件仍报错。

`parse_ply(data, lenient_ascii=true)` 显式启用异常 ASCII 文件的逐行兼容：一行一条记录，丢弃该行未声明的余项，行内缺少声明值时报错，不跨行补齐。这会有意丢弃数据，调用方应先确认布局；不能用于多条记录共用一行。该选项对二进制输入无影响。`parse_mesh()`、CLI、网页保持默认模式，不做失败后自动回退。普通 `parse_ply(data)` 调用方式保留；依赖旧版隐式忽略行尾数据的调用方需修正文件声明或显式启用兼容模式。

### 格式探测与解析

`detect_format(data)` 返回 `Ascii`（ASCII STL）、`Binary`（二进制 STL）、`Obj`、`ThreeMF`、`Ply` 或 `Unknown`。它依据内容提供解析路由提示，不使用文件后缀，也不证明文件有效或完整符合规范。

探测先检查 ZIP/3MF 候选与 PLY 文件头，再检查二进制 STL 的计数和精确文件长度。其余文本逐行查找行首几何记录：STL 的 `facet/vertex/endfacet` 或 OBJ 的 `v/vn/f`；仅有 `solid/endsolid` 时作为 ASCII STL 候选。注释和对象名称中嵌入这些单词不会被当成几何记录。文本扫描直到找到提示或到达末尾，最坏为 O(n)，不以 512 字节作为识别上限。

`parse_mesh()` 将已识别格式送到对应解析器；`Unknown` 文本依次尝试 ASCII STL 和 OBJ，均失败时返回“无法识别网格格式”并附两者原因。已识别格式的解析错误直接保留，不因文件损坏而换一种格式蒙混通过。`Unknown` 不再是 OBJ 的别名；`parse_stl()` 明确拒绝 OBJ、PLY 和 3MF。

可复现：`examples/long-header.stl` 的 solid 名称长 2048 个字符，首个 facet 位于 512 字节之后；`examples/obj-stl-keywords.obj` 的注释和对象名称包含 STL 关键字。两者均应按实际内容显示正确格式、读取 12 个三角形；库、CLI、网页都有回归检查。

### 声明面法线检查范围

当前仅检查**已保留的声明面法线方向是否与三角形绕向相反**：用声明向量与顶点绕序计算的单位几何法线做点积，结果小于 0 时计入 `wrong_normal_count`。声明向量长度不超过 `1e-9` 时跳过；零值计数不表示所有法线均已验证。

不检查声明法线是否单位化、是否垂直于三角形，或是否与几何法线精确一致。例如，与几何法线正交的声明向量点积为 0，不计为反向；长度为 2 的同向向量也不会因此报错。退化面由单独的退化检查报告，不靠这项证明法线有效。

OBJ 的 `vn` 是逐顶点数据。本库只在一个三角形的三个顶点法线逐分量完全相同时保留为单个声明面法线；缺失或三个向量不同时置零，之后跳过声明面法线反向检查。它不会验证或保留完整的平滑顶点法线场，也不会将不相同的 `vn` 自动判为错误。相邻三角形绕向由另一项检查处理。

因此，报告中的兼容字段“错误法线”只表示已保留声明面法线的反向计数；不是完整法线正确性检查。`normal_scope_wbtest.mbt` 给出正交、非单位及不同 OBJ 顶点法线的可执行边界案例。

## 校验与打印前复核

`validate_default(mesh)` 返回三角形数、去重顶点数、边界边、非流形边、退化面、已保留声明面法线反向计数（兼容字段 wrong_normal_count）与边计数。退化检查包含顶点合并和三点共线两种情况。

`check_winding_default(mesh)` 按共享边连通分量检查绕向。`WindingReport.components` 的每项包含本次报告的分量编号 `index`、原始面索引 `faces`、`closed`、`consistent`、`flipped_faces`、`signed_volume`、`orientation` 和包围盒。重排输入面可能改变分量编号；总体 `signed_volume` 仅作兼容汇总，不能让正体积大零件掩盖负体积小零件。

`orientation` 为 `PositiveVolume`、`NegativeVolume` 或 `Indeterminate`；开放、零体积或存在绕向冲突时不判断朝内外。`negative_components()` 返回确定的负体积闭合分量数；`orientation_reliable()` 要求非空、所有分量为正且没有可能嵌套 / 重叠标记。`potentially_nested` 基于包围盒重叠 / 接触的保守筛选，不是精确壳层分类。各分量使用局部原点与补偿求和，降低平移造成的体积相消。

`unify_winding()` 统一可定向分量的相邻绕向，按独立实心零件假设翻转包围盒互不重叠的闭合负体积分量；潜在嵌套壳层保持整体符号。`RepairResult.reoriented_components` 计整体翻转分量数，原 `flipped_faces` 的局部调整语义保留，`changed()` 包含两者。

本次源码新增的统一入口：

```moonbit nocheck
// mesh 是已解析的网格。0.5 是调用方选择的参考壁厚，单位毫米。
let review = @stlkit.check_printability(mesh, 0.5)
println(review.verdict())
println(review.inward_component_count()) // 确定的负体积闭合分量数
if review.needs_review() {
  println("请按报告检查模型和加工条件")
}
```

`PrintabilityReport` 包含 `validation`、`winding`、可选的 `thickness` 和 `min_thickness`。`inward_component_count()` 从 `winding.components` 返回确定的负体积闭合分量数，不保存重复计数；兼容方法 `inward()` 等价于该计数大于 0。两者不依赖总体积；负号不直接等于设计错误，内腔仍须人工解释。

`thin_wall()`、`thickness_unavailable()` 表示具体问题；`needs_review()` 和 `verdict()` 被 CLI 与网页共用。`needs_review()` 独立检查分量朝向，任一负体积、朝向未定或可能嵌套 / 重叠均须复核，不依赖厚度是否可用来间接拦截。即使调用方替换了公开报告的 `thickness` 字段，分量问题仍触发复核。负体积分量数为 0 不等于无需复核。

参考阈值为非负有限数，0 不设薄壁阈值。CLI 默认 0.8mm，网页版可调整；它是参考值，不是通用工艺标准。结果为“本次网格检查未发现已覆盖的问题”或“本次检查发现需要复核的问题”，不承诺打印成功。

检查范围不包括网格自相交、所有非流形顶点、支撑规划、喷嘴 / 树脂 / 材料适配、切片设置等。

## 壁厚

`check_printability(mesh, threshold, samples=1000)` 可指定采样预算，原两参数调用保持兼容。`review_scope()` 返回 CLI / 网页共同的工艺边界说明；接口名字不代表可打印认证。按面编号采样不保证面积均匀，采样预算和面顺序会影响结果。`docs/review-cases.md` 给出默认预算漏掉 0.05 mm 薄板的反例。

`check_thickness(mesh, samples)` / `check_thickness_default(mesh)` 从确定性表面采样点沿内法线打射线，记录命中数、采样最小厚度、命中样本平均值和最小样本位置。默认 1000 次采样，每条射线遍历三角形，时间复杂度约为 O(samples × faces)。

报告是局部采样估计，可能漏掉未采样的薄处；射线起点的微小偏移也影响数值。命中数为 0 表示无法评估，不能解读为实际壁厚 0。统一复核入口在网格开放、退化、任一分量朝向非正或未定、可能嵌套 / 重叠时不作可靠壁厚估计。

trimesh 的 `trimesh.proximity.thickness()` 同样提供厚度查询。本项目实现的是 MoonBit 的确定性采样与射线报告，不宣称该能力独有。

## 分析

- `Mesh::volume()`：有符号四面体贡献求和后取绝对值；开放或绕向异常时不能作为可信实体体积。
- `Mesh::surface_area()`、`bounding_box()`：现有三角形的面积与轴对齐包围盒。
- `oriented_bounding_box()`：PCA 方向的包围盒，不保证最小体积。协方差矩阵由 Jacobi 一次分解为完整正交基，两重或三重特征值均不再分别求向量；重复特征值下方向不唯一，不能保证恢复模型原始边方向。
- `symmetric_eigendecomposition(m)`：输入至少九项、按行排列的有限实对称 3×3 矩阵，使用上三角；返回 `SymmetricEigen`，`values` 为降序特征值，`vectors` 为对应正交轴。内部先缩放，最多 64 次最大非对角元 Jacobi 旋转；是 Double 数值算法，不保证任意尺度的精确结果。
- `symmetric_eigenvalues(m)` 保留并复用上述分解。`symmetric_eigenvector(m, lambda)` 选择最接近 lambda 的单个基向量；同一重根反复查询返回同一选择，要取得完整基应使用分解接口。
- `count_parts_default(mesh)`：按共享边连通数零件，只有点接触不算连通。
- `ValidationReport::euler_number()`：χ = V − E + F。对闭合可定向曲面，χ = 2k − 2Σg；不能脱离这些前提解释“洞”的数量。
- `center_mass()`、`moment_inertia()`、`principal_moments()`：密度取 1，底层函数不自动验证网格，保留整体反向模型的计算行为；调用方负责几何前提。
- `PrintabilityReport::mass_properties_available()`：CLI / 网页共用的质量属性输出条件，报告必须来自同一网格。要求非空、边计数闭合、无退化面、绕向一致、无需局部翻面，且分量均为正体积、无潜在嵌套 / 重叠标记。失败时入口显示“未评估”；网页协议新增“质量属性”“质量属性前提”，异常时继续省略“重心”“主惯量”数值字段。薄壁与参考阈值不单独阻断质量属性；此方法不验证自交、全部非流形顶点或数值精度。
- `ray_cast()`：内部归一化方向，`RayHit.distance` 为最近命中的欧氏距离；零 / 非有限方向返回 `None`。
- `ray_triangle()`：底层返回 `origin + dir*t` 中的参数 `t`，不归一化方向。
- `nearest_point()`：表面最近点及无符号距离。

## STL 输入契约

STL 输入契约：`parse_stl_binary()`、`stream_stl_binary()` 和 `StlScanner::finish()` 均要求严格匹配 `84 + 50 × count` 字节，三角形数大于 0，声明法线与顶点有限。任何额外尾字节、截断或非有限字段均失败；仅完成 `feed()` 不表示文件有效。数量字段以无符号数读取，不允许有符号截断变成负数。

`parse_stl_ascii()` 与 `stream_stl_ascii()` 共用逐面状态机，要求 `facet normal`、`outer loop`、三个 `vertex`、`endloop`、`endfacet` 的完整顺序。空行、ASCII 空白和 CRLF 可读，solid 包装可省略；未知记录、坏数字、错误顶点数、嵌套或未结束的面会报错。几何退化仍由验证层处理。`detect_format()` 是内容提示，二进制长度匹配只是结构证据；自动入口还须解析成功。

兼容性：此前被部分入口忽略的尾部垃圾、坏面和非有限声明法线现在统一拒绝；没有增加宽松模式。`stream_stl_ascii()` 仍接收完整文本，真正分块文件入口目前仅支持二进制 STL。

## 射线命中距离

`Mesh::ray_cast(origin, dir)` 在内部归一化有限的非零方向，返回最近命中的 `RayHit`。`distance` 是起点到命中点的欧氏距离，单位与网格坐标相同；`point` 是命中坐标。将方向乘以正数不会改变射线及其距离，负倍数则改变射线朝向。例如，从单位立方体下方 (0.25, 0.5, -1) 沿 (0, 0, 2) 发射，最近命中 z=0，距离为 1，而不是参数值 0.5。

零方向、非有限起点或方向返回 `None`；无命中时同样返回 `None`，该返回类型不区分这些原因。归一化先按方向的最大绝对分量缩放，避免直接平方极大 / 极小方向造成溢出或下溢。求交仍使用 Double 和原有平行 / 自交阈值，不是任意几何尺度下的精确计算保证。

底层 `ray_triangle(origin, dir, a, b, c)` 保持返回射线参数 `t`：命中点为 `origin + dir*t`。它不归一化方向；只有单位方向下参数才等于欧氏距离。不要把这个底层返回值与 `RayHit.distance` 混淆。

此次修复不改变函数签名。依赖旧版非单位方向下参数值的 `ray_cast()` 调用方应改用正确的几何距离；需要命中点时直接读取 `hit.point`，不要将距离再次乘以原始非单位方向。轴向、斜向、极大 / 极小正比例方向及无效输入回归见 `ray_direction_wbtest.mbt`。

## 修复

`repair(mesh, RepairOptions::default())` 删除退化面和重复面、补简单闭合边界环、统一绕向并重算法线。`RepairResult` 返回修改后的网格及删除面数、补洞数、新增三角形数等。

补洞采用边界环和中心扇形法；仅闭合环会参与补洞。复杂、凹形或非平面洞的几何质量不受保证，需人工检查。自动修复不能增加设计壁厚，也不负责网格布尔运算或修复自相交。

CLI 和网页修复后都再次运行统一复核入口。水密性改善不等于其他风险已消除。

CLI 支持 `--fix fixed.stl --svg fixed.svg` 组合：保存最终网格后，由同一个最终网格导出 SVG。没有可修复改动时也保存所请求的网格；`--strict` 在导出后依据最终复核结果退出，仍有问题时退出 1。网格写入失败则不继续 SVG；SVG 写入失败则退出 1，保留已写出的网格。两个输出应指定不同路径。

## 流式路径

`stream_stl_ascii(text)` / `stream_stl_binary(data)` 接收整份已在内存中的数据。`StlScanner::new()` / `feed(chunk)` / `finish()` 是二进制 STL 的分块入口，由调用方负责文件读取。

分块扫描不保存完整文件和三角形数组，但仍保留顶点表及全部三角形的边记录。空间 O(V+R+chunk)，非退化三角形 R=3F，R 包含重复边，不是不同边数；排序还有临时存储。`StlScanner::storage()` 返回顶点项、边记录、残留及单次缓冲峰值，不是分配器容量或进程内存测量。`--stream-only` 只运行这一路径，不提供完整绕向、壁厚、修复或预览。

`--bench` 比较三条路径，并核对三角形数和拓扑计数；由于同时运行全量解析，它不适合作为单独的低内存扫描命令。耗时使用计时器测量；数据量按主要字段粗略估算，未包含对象头、哈希桶、分配器与运行时，不是进程内存实测。

## 验证

```bash
moon update
moon check --target all --deny-warn
moon build
moon test
moon test --target js
moon test --target native
node cmd/main/smoke.cjs
bash web/build.sh
node web/smoke.cjs
```

回归包括正常立方体、缺面、法线 / 绕向、单位与变换、破损输入，以及本次新增的坐标碰撞、3000mm 平移、共线退化面、凹多边形、独立破洞和报告边界。

原有示例和新增审查案例用于手工复现，其中 17 个 3MF 文件来自官方样例库。读取成功不等于通过完整 3MF 规范认证。网页回归执行实际编译产物和报告逻辑，最小 DOM 仅验证判断和交互状态，不验证布局。

## 模块与依赖

- `vec3.mbt` / `mesh.mbt`：几何数据。
- `stl.mbt` / `obj.mbt` / `three_mf.mbt` / `ply.mbt`：格式读取；`polygon.mbt` 共用多边形三角化。
- `validate.mbt` / `winding.mbt` / `printability.mbt`：拓扑和统一打印前复核。
- `repair.mbt` / `writer.mbt`：修复与导出。
- `mass.mbt` / `mat3.mbt` / `obb.mbt` / `ray.mbt` / `thickness.mbt`：分析。
- `stream.mbt`：流式扫描。
- `preview.mbt`：SVG。
- `cmd/main/` / `web/`：CLI 与网页导出层。

核心几何算法只使用 MoonBit 核心库。3MF 使用 `hustcer/fzip` 和 `Milky2018/xml`；CLI 使用 `moonbitlang/x` 和 `moonbitlang/async`。代码支持 wasm / JS / native；CLI 文件读取只支持 wasm / native。

## 许可与参考

项目采用 [Apache-2.0](LICENSE)。参考 trimesh 的 API 与模块设计，差异和能力边界见 [COMPARISON.md](COMPARISON.md)。随附 3MF 样例采用 BSD-2-Clause，完整版权、条款及免责声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。


## 输入边界补充（2026-10-17）

ASCII STL / OBJ 的坐标和被读取的法线必须有限；二进制 STL 全量与流式读取均拒绝非有限坐标与声明法线。分块扫描遇错后保留错误，finish() 返回 Err；完整输入契约见上文“STL 输入契约”。

3MF 拒绝非有限变换、嵌套变换或坐标计算溢出，以及单位换算后的坐标溢出。当前不实现扩展语义：非空 requiredextensions 一律明确拒绝；可选扩展仍可忽略。因此成功读取核心三角网格不表示完整支持所有 3MF 扩展。

`moon run cmd/main examples/nonfinite-rejected.obj --strict` 应拒绝输入并以 1 退出，不生成检查通过结论。内存构造的 3MF、二进制 STL 与分块反例见 input_boundary_wbtest.mbt。变更与兼容约定见 [CHANGELOG.md](CHANGELOG.md)。
