# stlkit：接口与实现

MoonBit 的 STL / OBJ / 3MF / PLY 网格工具链。安装、命令行和网页版入口见 [README.md](README.md)。本次修订源码版本为 0.1.1，尚待发布；Mooncakes 0.1.0 不包含本次修复和新增的打印前复核接口。

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
| `parse_ply(data)` | ASCII / 小端 / 大端 PLY，按声明跳过未知属性 |
| `write_stl_ascii(mesh)` / `write_stl_binary(mesh)` | STL 导出 |
| `write_obj(mesh)` | OBJ 导出 |
| `write_ply_ascii(mesh)` / `write_ply_binary(mesh)` | PLY 导出，统一容差去重 |
| `write_mesh(mesh, filename)` | 按输出后缀选择格式 |

OBJ / PLY 的三角形原样保留，由校验层检查退化性。平面简单凸多边形保留扇形切分；凹多边形用耳切，并保持绕向。自相交和非平面多边形明确报错，不猜测几何。未实现 OBJ 材质渲染以及完整 3MF 颜色、材料与扩展语义。

## 校验与打印前复核

`validate_default(mesh)` 返回三角形数、去重顶点数、边界边、非流形边、退化面、错误声明法线与边计数。退化检查包含顶点合并和三点共线两种情况。

`check_winding_default(mesh)` 检查相邻面的绕向，并返回总体有符号体积。相邻绕向一致不代表整体朝外。总体体积为负时需要复核；这不是逐个连通壳层的内外嵌套分类。

本次源码新增的统一入口：

```moonbit nocheck
// mesh 是已解析的网格。0.5 是调用方选择的参考壁厚，单位毫米。
let review = @stlkit.check_printability(mesh, 0.5)
println(review.verdict())
if review.needs_review() {
  println("请按报告检查模型和加工条件")
}
```

`PrintabilityReport` 包含 `validation`、`winding`、可选的 `thickness` 和 `min_thickness`。`inward()`、`thin_wall()`、`thickness_unavailable()` 用于显示具体问题；`needs_review()` 和 `verdict()` 被 CLI 与网页共用。

参考阈值为非负有限数，0 不设薄壁阈值。CLI 默认 0.8mm，网页版可调整；它是参考值，不是通用工艺标准。结果为“本次网格检查未发现已覆盖的问题”或“本次检查发现需要复核的问题”，不承诺打印成功。

检查范围不包括网格自相交、所有非流形顶点、支撑规划、喷嘴 / 树脂 / 材料适配、切片设置等。

## 壁厚

`check_printability(mesh, threshold, samples=1000)` 可指定采样预算，原两参数调用保持兼容。`review_scope()` 返回 CLI / 网页共同的工艺边界说明；接口名字不代表可打印认证。按面编号采样不保证面积均匀，采样预算和面顺序会影响结果。`docs/review-cases.md` 给出默认预算漏掉 0.05 mm 薄板的反例。

`check_thickness(mesh, samples)` / `check_thickness_default(mesh)` 从确定性表面采样点沿内法线打射线，记录命中数、采样最小厚度、命中样本平均值和最小样本位置。默认 1000 次采样，每条射线遍历三角形，时间复杂度约为 O(samples × faces)。

报告是局部采样估计，可能漏掉未采样的薄处；射线起点的微小偏移也影响数值。命中数为 0 表示无法评估，不能解读为实际壁厚 0。统一复核入口在网格开放、退化、相邻绕向异常或总体体积非正时不作可靠壁厚估计。

trimesh 的 `trimesh.proximity.thickness()` 同样提供厚度查询。本项目实现的是 MoonBit 的确定性采样与射线报告，不宣称该能力独有。

## 分析

- `Mesh::volume()`：有符号四面体贡献求和后取绝对值；开放或绕向异常时不能作为可信实体体积。
- `Mesh::surface_area()`、`bounding_box()`：现有三角形的面积与轴对齐包围盒。
- `oriented_bounding_box()`：PCA 方向的包围盒，不保证最小体积。
- `count_parts_default(mesh)`：按共享边连通数零件，只有点接触不算连通。
- `ValidationReport::euler_number()`：χ = V − E + F。对闭合可定向曲面，χ = 2k − 2Σg；不能脱离这些前提解释“洞”的数量。
- `center_mass()`、`moment_inertia()`、`principal_moments()`：密度取 1，需结合闭合性和朝向解释。
- `ray_cast()`、`nearest_point()`：射线求交与表面最近点。

## 修复

`repair(mesh, RepairOptions::default())` 删除退化面和重复面、补简单闭合边界环、统一绕向并重算法线。`RepairResult` 返回修改后的网格及删除面数、补洞数、新增三角形数等。

补洞采用边界环和中心扇形法；仅闭合环会参与补洞。复杂、凹形或非平面洞的几何质量不受保证，需人工检查。自动修复不能增加设计壁厚，也不负责网格布尔运算或修复自相交。

CLI 和网页修复后都再次运行统一复核入口。水密性改善不等于其他风险已消除。

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

ASCII STL / OBJ 的坐标和被读取的法线必须有限；二进制 STL 全量读取同样拒绝非有限坐标与法线。二进制流式路径不读取法线，但拒绝非有限顶点；分块扫描遇错后保留错误，finish() 返回 Err。

3MF 拒绝非有限变换、嵌套变换或坐标计算溢出，以及单位换算后的坐标溢出。当前不实现扩展语义：非空 requiredextensions 一律明确拒绝；可选扩展仍可忽略。因此成功读取核心三角网格不表示完整支持所有 3MF 扩展。

`moon run cmd/main examples/nonfinite-rejected.obj --strict` 应拒绝输入并以 1 退出，不生成检查通过结论。内存构造的 3MF、二进制 STL 与分块反例见 input_boundary_wbtest.mbt。变更与兼容约定见 [CHANGELOG.md](CHANGELOG.md)。
