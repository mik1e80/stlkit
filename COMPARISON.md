# stlkit 与相关项目的对比

## 0.2.0 API 与索引表示复核（2026-10-28）

新增 JSON v1、粗粒度结构化解析错误、IndexedMesh 初版。重跑下列现有语料：67 次读取、5 次修复重载、10 次厚度对照通过，来源/完整许可/哈希验证通过；原几何数值与边界声明保持。新索引类型通过解析值、转换、快照与非法输入测试，但拓扑接口暂时展开旧 Mesh。100k 转换实测峰值约 40 MB，高于仅生成 Mesh 的 23–24 MB，详见 [原始对照](docs/benchmarks/indexed-20261028.md)，不宣传全流程节省内存。BVH / 自相交尚未实现，历史性能表日期保持原样。

## 0.1.5 维护回归（2026-10-27）

在默认解析预算下重跑现有语料：67 次读取、5 次修复重载、10 次厚度对照均通过，所有外部模型的完整来源、许可与哈希验证通过。模型名单、逐模型反馈与数值见下方原始表，几何结果未改变；0.1.4 的记录日期保持原样。另通过 100k 全量/分块一致性回归，不将历史 500k / 1m 耗时写作本次新测量。新预算和确定性变异结果见 [资源限制](docs/resource-limits.md) 与 [变异报告](docs/fuzz-testing.md)。没有新增外部下载模型。

stlkit 面向模型文件的打印前复核：读取 STL / OBJ / 3MF / PLY，检查网格、估算采样厚度、提供修复和报告。它是 MoonBit 实现，无 FFI；库、CLI 和浏览器使用同一份核心代码。

## 与 trimesh

[trimesh](https://trimesh.org/) 是 Python 的网格处理库。两者在格式读取、拓扑分析、质量属性、射线查询和修复方面有共同能力；stlkit 提供 MoonBit 接口及直接可用的 CLI / 网页报告。

| 能力 | trimesh | stlkit |
| --- | --- | --- |
| 主要实现 | Python / NumPy，部分操作依赖可选组件 | MoonBit；3MF 依赖 MoonBit ZIP / XML 库 |
| 文件读取 | STL、OBJ、3MF、PLY 及其他格式 | STL、OBJ、3MF、PLY 的文档声明范围 |
| 网格表示 | 顶点与面索引 | 三角形列表；按容差重建顶点关系 |
| 拓扑与质量属性 | 水密性、绕向、连通块、欧拉数、质量属性等 | 边界边、非流形边、退化面、绕向、连通块、欧拉数、质量属性 |
| 定向包围盒 | 提供定向包围盒相关查询 | PCA 包围盒，不保证最小体积 |
| 厚度 | `trimesh.proximity.thickness()`，支持 `max_sphere` / `ray` | 确定性表面采样与内法线射线估计；报告采样最小值和命中数 |
| 修复 | 提供网格修复工具 | 退化 / 重复面删除、简单环补洞、绕向和法线修正，再次复核 |
| 网格运算 | 布尔、体素、平滑、细分等 | 未实现 |
| 分块扫描 | 常规网格处理保留模型数据 | 二进制 STL 分块入口；仍保留顶点表与边表 |
| 使用方式 | Python 库与应用集成 | MoonBit 库、CLI、浏览器网页 |

trimesh 提供壁厚查询，官方接口和算法说明见 [trimesh.proximity.thickness](https://trimesh.org/trimesh.proximity.html#trimesh.proximity.thickness)。本项目的射线采样估计不等同于最大切球法，也不保证得到全局最薄处。

### 参考关系

参考了 trimesh 的 API 和能力组织：连通零件数、欧拉数、质量属性、定向包围盒、射线 / 最近点和 PLY 读写。stlkit 是独立的 MoonBit 实现；来源说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 与 MoonBit 相关项目

下面说明相关方向和本项目的侧重点，不作“生态唯一”“其他库完全不重叠”或未核实的性能断言。具体能力需结合各包版本、文档和源码判断。

| 项目 / 方向 | 侧重点 | stlkit 的侧重点 |
| --- | --- | --- |
| `mizchi/three` 等 three.js 接口 | 三维场景、渲染和模型加载接口 | MoonBit 文件处理与网格复核，同时提供静态 SVG 预览 |
| `mizchi/mesh3d` 等网格原语 | 渲染管线中的顶点 / 网格组织，部分含 OBJ 读取 | 格式解析、拓扑计数、修复及打印前报告 |
| glTF / GLB 资产工具 | 场景、材质、动画和渲染资产分析 | STL / OBJ / 3MF / PLY 模型的网格与制造前风险 |
| 网格优化和几何工具 | 渲染性能、压缩、简化或通用几何算法 | 读取后复核、修复和报告的工作流程 |
| PicoGK 等体素 / 建模工具 | 几何生成或体素建模 | 检查已有三角网格文件 |

共享几何算法或模型读取能力不意味着定位相同，也不意味着完全没有交集。stlkit 的价值是把这些网格复核能力提供给 MoonBit 使用者，并让 CLI 与浏览器复用相同结论。

## 能力与证据边界

- 检查通过只说明当前覆盖项未发现问题；没有覆盖全部网格自相交、非流形顶点、支撑与材料工艺条件。
- 简单环补洞和 PCA 包围盒有算法边界；修复后仍需复核。
- 分块扫描降低完整文件与三角形数组的存储需求，但顶点与边数据仍随规模增长。
- CLI 内存字段是数据量估算，不是进程内存测量。旧文档的固定内存节省比例和跨项目提速数字已撤下。
- 正确性通过可复现反例与跨后端测试验证；运行命令见 [README.md](README.md#验证与开发)。

项目自建内容采用 Apache-2.0；第三方样例分别采用 BSD-2-Clause 或 CC0-1.0，完整条款、来源与改动分别随仓库保留。


## 声明面法线边界

STLKIT 仅统计已保留声明面法线与三角形绕向相反的情况（点积 < 0），不提供完整法线正确性校验；不查单位长度、垂直性或精确一致性。OBJ 三个顶点法线不完全相同时，面法线置零并跳过该项。完整语义及案例见 README 和 normal_scope_wbtest.mbt。



<!-- corpus-results:start -->
## 模型实测与反馈（2026-10-23）

以下语料在 0.1.4 严格读取路径下重新复核；10月21日的性能记录保留原始测量环境，不作为新版本的重新计时。数据由 `node scripts/corpus-cases.cjs --update` 调用实际 Native CLI 生成。默认门槛为 0 mm、样本预算 1，只用于快速几何回归；壁厚另按下表固定预算测试。STL / OBJ / PLY 的坐标由调用方按毫米解释；3MF 按声明单位换算。顶点焊接默认容差为 `1e-6`。报告三位小数按绝对误差约 0.0015 核对；跨工具链快照容许 0.003。完整数值、退出码、命令和输入哈希见 [summary.json](examples/corpus/reports/summary.json)。

解析退出 0 不等于检查通过。下表体积列在朝向不可靠时仅为有符号贡献绝对值，不可作为可靠实体体积；以原始报告中的质量属性前提为准。外部样例的计数快照用于发现行为变化，不能替代独立正确性证明。

### 自建解析值与边界模型

模型和生成脚本采用 [Apache-2.0](LICENSE)，全部为独立构造。`non-manifold-vertex` 与 `vertex-touching-cubes` 故意使用同一几何验证两个语义，不算两个独立几何来源。

| 模型 | 许可 | 面数 | 体积 / 面积 | 边界 / 非流形边 / 退化面 | 反馈 |
| --- | --- | --- | --- | --- | --- |
| [examples/cube.stl](examples/cube.stl) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 12 面，体积 1、面积 6；四格式数值一致；[原始输出](examples/corpus/reports/cube.stl.txt) |
| [examples/cube.obj](examples/cube.obj) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 12 面，体积 1、面积 6；四格式数值一致；[原始输出](examples/corpus/reports/cube.obj.txt) |
| [examples/corpus/cube-1mm.ply](examples/corpus/cube-1mm.ply) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 12 面，体积 1、面积 6；四格式数值一致；[原始输出](examples/corpus/reports/corpus_cube-1mm.ply.txt) |
| [examples/corpus/cube-1mm.3mf](examples/corpus/cube-1mm.3mf) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 12 面，体积 1、面积 6；四格式数值一致；[原始输出](examples/corpus/reports/corpus_cube-1mm.3mf.txt) |
| [examples/corpus/box-2x3x4.stl](examples/corpus/box-2x3x4.stl) | Apache-2.0 | 12 | 24 / 52 | 0 / 0 / 0 | 解析值 24 / 52 符合；[原始输出](examples/corpus/reports/corpus_box-2x3x4.stl.txt) |
| [examples/corpus/tetrahedron-unit.stl](examples/corpus/tetrahedron-unit.stl) | Apache-2.0 | 4 | 0.167 / 2.366 | 0 / 0 / 0 | 解析体积 1/6、面积 (3+√3)/2 符合；[原始输出](examples/corpus/reports/corpus_tetrahedron-unit.stl.txt) |
| [examples/corpus/octahedron-unit.stl](examples/corpus/octahedron-unit.stl) | Apache-2.0 | 8 | 1.333 / 6.928 | 0 / 0 / 0 | 解析体积 4/3、面积 4√3 符合；[原始输出](examples/corpus/reports/corpus_octahedron-unit.stl.txt) |
| [examples/corpus/rotated-box-2x3x4.stl](examples/corpus/rotated-box-2x3x4.stl) | Apache-2.0 | 12 | 24 / 52 | 0 / 0 / 0 | 旋转后 AABB 改变，PCA OBB 约 4×3×2；[原始输出](examples/corpus/reports/corpus_rotated-box-2x3x4.stl.txt) |
| [examples/corpus/square-prism-2x2x4.stl](examples/corpus/square-prism-2x2x4.stl) | Apache-2.0 | 12 | 16 / 40 | 0 / 0 / 0 | 重复特征值：OBB 有效且无零轴；不要求恢复唯一旋转方向；[原始输出](examples/corpus/reports/corpus_square-prism-2x2x4.stl.txt) |
| [examples/corpus/hollow-box-10-8.obj](examples/corpus/hollow-box-10-8.obj) | Apache-2.0 | 24 | 488 / 984 | 0 / 0 / 0 | 两壳层、内壳负体积；潜在嵌套，质量属性暂停；[原始输出](examples/corpus/reports/corpus_hollow-box-10-8.obj.txt) |
| [examples/corpus/inside-out-cube.obj](examples/corpus/inside-out-cube.obj) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 检测到一个负体积分量，暂停质量属性；[原始输出](examples/corpus/reports/corpus_inside-out-cube.obj.txt) |
| [examples/corpus/duplicate-face.stl](examples/corpus/duplicate-face.stl) | Apache-2.0 | 13 | 1 / 6.5 | 0 / 3 / 0 | 重复面导致 3 条多重边；修复删除 1 面；[原始输出](examples/corpus/reports/corpus_duplicate-face.stl.txt) |
| [examples/corpus/non-manifold-edge.stl](examples/corpus/non-manifold-edge.stl) | Apache-2.0 | 3 | 0 / 1.5 | 6 / 1 / 0 | 三面共边，识别 1 条非流形边；[原始输出](examples/corpus/reports/corpus_non-manifold-edge.stl.txt) |
| [examples/corpus/non-manifold-vertex.obj](examples/corpus/non-manifold-vertex.obj) | Apache-2.0 | 24 | 2 / 12 | 0 / 0 / 0 | 共享顶点仍为两个共享边分量；包围盒提示，未实现顶点流形判定；[原始输出](examples/corpus/reports/corpus_non-manifold-vertex.obj.txt) |
| [examples/corpus/vertex-touching-cubes.obj](examples/corpus/vertex-touching-cubes.obj) | Apache-2.0 | 24 | 2 / 12 | 0 / 0 / 0 | 共享顶点仍为两个共享边分量；包围盒提示，未实现顶点流形判定；[原始输出](examples/corpus/reports/corpus_vertex-touching-cubes.obj.txt) |
| [examples/corpus/two-independent-holes.stl](examples/corpus/two-independent-holes.stl) | Apache-2.0 | 10 | 0.833 / 5 | 6 / 0 / 0 | 两处独立三角洞；修复新增 2 面，边界 6→0；[原始输出](examples/corpus/reports/corpus_two-independent-holes.stl.txt) |
| [examples/corpus/self-intersection.obj](examples/corpus/self-intersection.obj) | Apache-2.0 | 24 | 2 / 12 | 0 / 0 / 0 | 仅包围盒重叠提示，不能据此声称精确检测自交；[原始输出](examples/corpus/reports/corpus_self-intersection.obj.txt) |
| [examples/corpus/concave-l-prism.obj](examples/corpus/concave-l-prism.obj) | Apache-2.0 | 20 | 10 / 34 | 0 / 0 / 0 | 自建 L 形凹多边形面，耳切三角化符合解析值；[原始输出](examples/corpus/reports/corpus_concave-l-prism.obj.txt) |
| [examples/corpus/slab-0.05mm.stl](examples/corpus/slab-0.05mm.stl) | Apache-2.0 | 12 | 5 / 202 | 0 / 0 / 0 | 均匀薄板；固定预算采样结果见壁厚表；[原始输出](examples/corpus/reports/corpus_slab-0.05mm.stl.txt) |
| [examples/corpus/slab-0.40mm.stl](examples/corpus/slab-0.40mm.stl) | Apache-2.0 | 12 | 40 / 216 | 0 / 0 / 0 | 均匀薄板；固定预算采样结果见壁厚表；[原始输出](examples/corpus/reports/corpus_slab-0.40mm.stl.txt) |
| [examples/corpus/slab-0.80mm.stl](examples/corpus/slab-0.80mm.stl) | Apache-2.0 | 12 | 80 / 232 | 0 / 0 / 0 | 均匀薄板；固定预算采样结果见壁厚表；[原始输出](examples/corpus/reports/corpus_slab-0.80mm.stl.txt) |
| [examples/corpus/wedge-variable-thickness.stl](examples/corpus/wedge-variable-thickness.stl) | Apache-2.0 | 12 | 52.5 / 221.45 | 0 / 0 / 0 | 竖向高度 0.05→1；射线首命中距离随端面/侧面采样改变，不能等同竖向高度；[原始输出](examples/corpus/reports/corpus_wedge-variable-thickness.stl.txt) |
| [examples/corpus/hollow-tube-wall-0.40mm.stl](examples/corpus/hollow-tube-wall-0.40mm.stl) | Apache-2.0 | 1024 | 120.589 / 627.243 | 0 / 0 / 0 | 128 段闭合空心管；离散曲面采样约 0.40 mm；[原始输出](examples/corpus/reports/corpus_hollow-tube-wall-0.40mm.stl.txt) |

### 外部模型、许可与实测

CC0 模型来自 [Ghostkeeper / SlicerTestModels contributors](https://github.com/Ghostkeeper/SlicerTestModels/tree/e1bbc8eec047c2fb604b71f7e4793c3e0189fd6d)；BSD 扫描源来自 [3MF Consortium](https://github.com/3MFConsortium/3mf-samples/tree/665e20dc4d7777fd4c9702bca86a2d4028440337)，Copyright (c) 2018, 3MF Consortium。每个文件的作者、固定来源 URL、SHA-256、改动和转换命令见 [manifest.json](examples/external/manifest.json)。[CC0-1.0 完整文本](examples/external/licenses/SlicerTestModels.CC0-1.0.txt) 与 [BSD-2-Clause 完整文本](examples/external/licenses/3MFConsortium.BSD-2-Clause.txt) 随样例保留，不以项目的 Apache-2.0 覆盖它们。外部文件的报告仅描述当前工具和容差下的观察，不据此直接断言上游文件有缺陷。

| 模型 | 许可 | 面数 | 体积 / 面积 | 边界 / 非流形边 / 退化面 | 反馈 |
| --- | --- | --- | --- | --- | --- |
| [examples/external/bracket.stl](examples/external/bracket.stl) | CC0-1.0 | 8060 | 42387.372 / 33404.71 | 0 / 0 / 18 | 支架实测报告 18 个退化面、2 个零件；质量属性暂停；[原始输出](examples/corpus/reports/external_bracket.stl.txt) |
| [examples/external/gear.stl](examples/external/gear.stl) | CC0-1.0 | 284 | 5769.966 / 3784.259 | 0 / 0 / 0 | 复杂轮廓齿轮读取成功；[原始输出](examples/corpus/reports/external_gear.stl.txt) |
| [examples/external/concave-cad.obj](examples/external/concave-cad.obj) | CC0-1.0 | 28 | 2750 / 2250 | 0 / 0 / 0 | U 形 CAD 凹八边形面，体积 2750、面积 2250；[原始输出](examples/corpus/reports/external_concave-cad.obj.txt) |
| [examples/external/heart.stl](examples/external/heart.stl) | CC0-1.0 | 33576 | 2636.211 / 1136.99 | 0 / 0 / 0 | 有机曲面读取成功；未检验精确自遮挡/自交；[原始输出](examples/corpus/reports/external_heart.stl.txt) |
| [examples/external/rotated-group.3mf](examples/external/rotated-group.3mf) | CC0-1.0 | 40 | 57262.581 / 18105.806 | 0 / 3 / 6 | 4 个共享边零件；报告 3 条非流形边及 6 个退化面；[原始输出](examples/corpus/reports/external_rotated-group.3mf.txt) |
| [examples/external/cura-4.2-project.3mf](examples/external/cura-4.2-project.3mf) | CC0-1.0 | 36 | 3000 / 1800 | 0 / 0 / 0 | Cura 4.2 工程几何读取；不验证切片配置；[原始输出](examples/corpus/reports/external_cura-4.2-project.3mf.txt) |
| [examples/external/kinect-scan.3mf](examples/external/kinect-scan.3mf) | BSD-2-Clause | 282544 | 178768.942 / 27465.862 | 0 / 0 / 0 | 141249 顶点扫描模型读取成功；材料不进入 Mesh；[原始输出](examples/corpus/reports/external_kinect-scan.3mf.txt) |
| [examples/external/cura-4.5-project.3mf](examples/external/cura-4.5-project.3mf) | CC0-1.0 | — | 拒绝 | — | Cura 私有 XML 根元素不是 Core model，严格拒绝；不支持完整工程恢复；[原始输出](examples/corpus/reports/external_cura-4.5-project.3mf.txt) |
| `_build/corpus/kinect-scan.ply` | BSD-2-Clause | 282544 | 178768.941 / 27465.862 | 0 / 0 / 0 | 同一 3MF 的独立几何转换；非独立扫描源；材料未转换；[原始输出](examples/corpus/reports/_build_corpus_kinect-scan.ply.txt) |

R01 支架、R02 齿轮、R03 CAD 凹面、R04 扫描 PLY、R05 有机曲面、R06 组件 3MF、R07 Cura 工程、R08 10–30 万面均有对应案例。R04 与 R08 使用同一个 BSD 扫描源，PLY 是几何转换，不能当作第二个独立来源。R04 没有验证颜色/法线保真，3MF 材质、Cura 配置和精确自遮挡均未评估；不声称完整切片工程兼容。

### 现有模型全部复测

旧版 COMPARISON.md 未逐个列模型，本次扩大至仓库全部现有 `examples/` 网格（含 13 个官方几何读取案例和坏输入），没有只挑成功文件。

| 模型 | 许可 | 面数 | 体积 / 面积 | 边界 / 非流形边 / 退化面 | 反馈 |
| --- | --- | --- | --- | --- | --- |
| [examples/ascii-packed.ply](examples/ascii-packed.ply) | Apache-2.0 | 2 | 0 / 1 | 4 / 0 / 0 | 完整解析跨记录空白；开放方形，质量属性暂停；[原始输出](examples/corpus/reports/ascii-packed.ply.txt) |
| [examples/box.3mf](examples/box.3mf) | BSD-2-Clause | 12 | 6000 / 2200 | 0 / 0 / 0 | 官方长方体，10×20×30，体积 6000；[原始输出](examples/corpus/reports/box.3mf.txt) |
| [examples/broken.stl](examples/broken.stl) | Apache-2.0 | 11 | 1 / 5.5 | 3 / 0 / 0 | 开放三角洞，3 条边界边；[原始输出](examples/corpus/reports/broken.stl.txt) |
| [examples/flipped.stl](examples/flipped.stl) | Apache-2.0 | 12 | 0.667 / 6 | 0 / 0 / 0 | 局部绕向冲突，暂停质量属性；[原始输出](examples/corpus/reports/flipped.stl.txt) |
| [examples/degenerate-closed.obj](examples/degenerate-closed.obj) | Apache-2.0 | 12 | 0.75 / 5.346 | 0 / 0 / 1 | 边计数闭合仍有退化面，暂停质量属性；[原始输出](examples/corpus/reports/degenerate-closed.obj.txt) |
| [examples/long-header.stl](examples/long-header.stl) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 长 ASCII 头仍识别为 STL；[原始输出](examples/corpus/reports/long-header.stl.txt) |
| [examples/obj-stl-keywords.obj](examples/obj-stl-keywords.obj) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 关键词不误识别为 STL；[原始输出](examples/corpus/reports/obj-stl-keywords.obj.txt) |
| [examples/torus.obj](examples/torus.obj) | Apache-2.0 | 2304 | 1.226 / 8.252 | 0 / 0 / 0 | 曲面离散模型；与 STL 对照；[原始输出](examples/corpus/reports/torus.obj.txt) |
| [examples/torus.stl](examples/torus.stl) | Apache-2.0 | 2304 | 1.226 / 8.252 | 0 / 0 / 0 | 曲面离散模型；与 OBJ 对照；[原始输出](examples/corpus/reports/torus.stl.txt) |
| [examples/torus.3mf](examples/torus.3mf) | BSD-2-Clause | 2200 | 776.831 / 785.595 | 0 / 0 / 0 | 官方圆环几何读取；[原始输出](examples/corpus/reports/torus.3mf.txt) |
| [examples/multiple_cylinders.3mf](examples/multiple_cylinders.3mf) | BSD-2-Clause | 528 | 37188.557 / 11233.065 | 0 / 0 / 0 | 六个 build 实例，按变换读取；[原始输出](examples/corpus/reports/multiple_cylinders.3mf.txt) |
| [examples/cube_gears.3mf](examples/cube_gears.3mf) | BSD-2-Clause | 25692 | 112366.332 / 41919.32 | 0 / 24 / 92 | 报告退化/拓扑风险；不据此断言上游模型有错；[原始输出](examples/corpus/reports/cube_gears.3mf.txt) |
| [examples/review/cubes-1.stl](examples/review/cubes-1.stl) | Apache-2.0 | 12 | 1 / 6 | 0 / 0 / 0 | 分块表项增长基线；[原始输出](examples/corpus/reports/review_cubes-1.stl.txt) |
| [examples/review/cubes-16.stl](examples/review/cubes-16.stl) | Apache-2.0 | 192 | 16 / 96 | 0 / 0 / 0 | 16 个分离立方体；[原始输出](examples/corpus/reports/review_cubes-16.stl.txt) |
| [examples/review/cubes-64.stl](examples/review/cubes-64.stl) | Apache-2.0 | 768 | 64 / 384 | 0 / 0 / 0 | 64 个分离立方体；[原始输出](examples/corpus/reports/review_cubes-64.stl.txt) |
| [examples/review/opposite-parts.obj](examples/review/opposite-parts.obj) | Apache-2.0 | 24 | 7 / 30 | 0 / 0 / 0 | 总体积 +7 掩盖 +8 / −1 两分量；[原始输出](examples/corpus/reports/review_opposite-parts.obj.txt) |
| [examples/review/opposite-parts-fixed.stl](examples/review/opposite-parts-fixed.stl) | Apache-2.0 | 24 | 9 / 30 | 0 / 0 / 0 | 修复后独立分量均朝外，总体积 9；[原始输出](examples/corpus/reports/review_opposite-parts-fixed.stl.txt) |
| [examples/review/sampling-blindspot.obj](examples/review/sampling-blindspot.obj) | Apache-2.0 | 3084 | 1.05 / 8.2 | 0 / 0 / 0 | 确定性面顺序反例；1000 / 全面预算另行复核；[原始输出](examples/corpus/reports/review_sampling-blindspot.obj.txt) |
| [examples/missing-format.ply](examples/missing-format.ply) | Apache-2.0 | — | 拒绝 | — | 坏输入按预期拒绝；属于成功的负向回归；[原始输出](examples/corpus/reports/missing-format.ply.txt) |
| [examples/missing-z.ply](examples/missing-z.ply) | Apache-2.0 | — | 拒绝 | — | 坏输入按预期拒绝；属于成功的负向回归；[原始输出](examples/corpus/reports/missing-z.ply.txt) |
| [examples/nonfinite-rejected.obj](examples/nonfinite-rejected.obj) | Apache-2.0 | — | 拒绝 | — | 坏输入按预期拒绝；属于成功的负向回归；[原始输出](examples/corpus/reports/nonfinite-rejected.obj.txt) |
| [examples/ascii-extra-values.ply](examples/ascii-extra-values.ply) | Apache-2.0 | — | 拒绝 | — | 坏输入按预期拒绝；属于成功的负向回归；[原始输出](examples/corpus/reports/ascii-extra-values.ply.txt) |
| [examples/conformance/MUSTPASS_Chapter2.1_PartsRelationships.3mf](examples/conformance/MUSTPASS_Chapter2.1_PartsRelationships.3mf) | BSD-2-Clause | 12 | 8000 / 2400 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter2.1_PartsRelationships.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter2.2_PartNaming.3mf](examples/conformance/MUSTPASS_Chapter2.2_PartNaming.3mf) | BSD-2-Clause | 12 | 16387.064 / 3870.96 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter2.2_PartNaming.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter2.3a_IgnorableMarkup.3mf](examples/conformance/MUSTPASS_Chapter2.3a_IgnorableMarkup.3mf) | BSD-2-Clause | 12 | 1000 / 600 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter2.3a_IgnorableMarkup.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter3.2b_UnitsMeasurementMM.3mf](examples/conformance/MUSTPASS_Chapter3.2b_UnitsMeasurementMM.3mf) | BSD-2-Clause | 12 | 1000 / 600 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter3.2b_UnitsMeasurementMM.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter3.2c_MultipleItemsTransform.3mf](examples/conformance/MUSTPASS_Chapter3.2c_MultipleItemsTransform.3mf) | BSD-2-Clause | 60 | 14000.003 / 6000.001 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter3.2c_MultipleItemsTransform.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter3.4.1c_MustIgnoreUndefinedMetadataName.3mf](examples/conformance/MUSTPASS_Chapter3.4.1c_MustIgnoreUndefinedMetadataName.3mf) | BSD-2-Clause | 12 | 8000 / 2400 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter3.4.1c_MustIgnoreUndefinedMetadataName.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter3.4.2_MetaData_Resources_Build.3mf](examples/conformance/MUSTPASS_Chapter3.4.2_MetaData_Resources_Build.3mf) | BSD-2-Clause | 12 | 1000 / 600 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter3.4.2_MetaData_Resources_Build.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter3.4.3a_MustNotOutputNonReferencedObjects.3mf](examples/conformance/MUSTPASS_Chapter3.4.3a_MustNotOutputNonReferencedObjects.3mf) | BSD-2-Clause | 12 | 1000 / 600 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter3.4.3a_MustNotOutputNonReferencedObjects.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter4.1_ExplicitSupport.3mf](examples/conformance/MUSTPASS_Chapter4.1_ExplicitSupport.3mf) | BSD-2-Clause | 484 | 19577.576 / 7449.016 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter4.1_ExplicitSupport.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter4.2_Components.3mf](examples/conformance/MUSTPASS_Chapter4.2_Components.3mf) | BSD-2-Clause | 60 | 14000.003 / 6000.001 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter4.2_Components.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter5.1a_MaterialResources_CompositeAndMultiProperties.3mf](examples/conformance/MUSTPASS_Chapter5.1a_MaterialResources_CompositeAndMultiProperties.3mf) | BSD-2-Clause | 12 | 1000 / 600 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter5.1a_MaterialResources_CompositeAndMultiProperties.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter5.1b_MaterialResources_MultiObjects_CompositeAndMultiProperties.3mf](examples/conformance/MUSTPASS_Chapter5.1b_MaterialResources_MultiObjects_CompositeAndMultiProperties.3mf) | BSD-2-Clause | 24 | 2000 / 1200 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter5.1b_MaterialResources_MultiObjects_CompositeAndMultiProperties.3mf.txt) |
| [examples/conformance/MUSTPASS_Chapter5.1c_MaterialResources_sRGB_RGB_Colors.3mf](examples/conformance/MUSTPASS_Chapter5.1c_MaterialResources_sRGB_RGB_Colors.3mf) | BSD-2-Clause | 12 | 1000 / 600 | 0 / 0 / 0 | 声明范围内几何读取成功；未验证材质/支撑/完整 3MF 一致性；[原始输出](examples/corpus/reports/conformance_MUSTPASS_Chapter5.1c_MaterialResources_sRGB_RGB_Colors.3mf.txt) |

### 修复后重新读取

| 输入 | 新增面 | 删除重复面 | 修复后面数 | 修复后边界 | 证据 |
| --- | --- | --- | --- | --- | --- |
| `examples/corpus/two-independent-holes.stl` | 2 | 0 | 12 | 0 | [修复及复核](examples/corpus/reports/corpus_two-independent-holes.stl.repair.txt) |
| `examples/corpus/duplicate-face.stl` | 0 | 1 | 12 | 0 | [修复及复核](examples/corpus/reports/corpus_duplicate-face.stl.repair.txt) |
| `examples/broken.stl` | 1 | 0 | 12 | 0 | [修复及复核](examples/corpus/reports/broken.stl.repair.txt) |
| `examples/flipped.stl` | 0 | 0 | 12 | 0 | [修复及复核](examples/corpus/reports/flipped.stl.repair.txt) |
| `examples/corpus/inside-out-cube.obj` | 0 | 0 | 12 | 0 | [修复及复核](examples/corpus/reports/corpus_inside-out-cube.obj.repair.txt) |

两个三角洞彼此独立，各新增一个三角形；重读导出文件后确认为 12 面且无边界。该结果不扩展到任意复杂洞。

### 固定条件的壁厚采样

所有模型均按 mm，使用默认焊接容差 `1e-6`，几何法线反向射线，参考阈值 0（不按工艺判定）。射线偏移由 `probe_inset()` 按包围盒尺度选取；脚本不覆盖库默认偏移。确定性采样不是面积加权随机采样，命中数和面顺序会影响结果。

| 模型 | 预算 | 命中 | 采样最小值 mm | 证据 |
| --- | --- | --- | --- | --- |
| `slab-0.05mm.stl` | 1000 | 1000 | 0.05 | [输出](examples/corpus/reports/corpus_slab-0.05mm.stl.samples-1000.txt) |
| `slab-0.05mm.stl` | 4096 | 4096 | 0.05 | [输出](examples/corpus/reports/corpus_slab-0.05mm.stl.samples-4096.txt) |
| `slab-0.40mm.stl` | 1000 | 1000 | 0.4 | [输出](examples/corpus/reports/corpus_slab-0.40mm.stl.samples-1000.txt) |
| `slab-0.40mm.stl` | 4096 | 4096 | 0.4 | [输出](examples/corpus/reports/corpus_slab-0.40mm.stl.samples-4096.txt) |
| `slab-0.80mm.stl` | 1000 | 1000 | 0.8 | [输出](examples/corpus/reports/corpus_slab-0.80mm.stl.samples-1000.txt) |
| `slab-0.80mm.stl` | 4096 | 4096 | 0.8 | [输出](examples/corpus/reports/corpus_slab-0.80mm.stl.samples-4096.txt) |
| `wedge-variable-thickness.stl` | 1000 | 1000 | 0.043 | [输出](examples/corpus/reports/corpus_wedge-variable-thickness.stl.samples-1000.txt) |
| `wedge-variable-thickness.stl` | 4096 | 4096 | 0.003 | [输出](examples/corpus/reports/corpus_wedge-variable-thickness.stl.samples-4096.txt) |
| `hollow-tube-wall-0.40mm.stl` | 1000 | 1000 | 0.4 | [输出](examples/corpus/reports/corpus_hollow-tube-wall-0.40mm.stl.samples-1000.txt) |
| `hollow-tube-wall-0.40mm.stl` | 4096 | 4096 | 0.4 | [输出](examples/corpus/reports/corpus_hollow-tube-wall-0.40mm.stl.samples-4096.txt) |

薄板和空心管结果与解析厚度约符。楔形的竖向高度为 0.05–1 mm，但 1000 / 4096 预算实测射线首命中最小距离为 0.043 / 0.003 mm：采样包含端面和侧面，沿各自内法线命中邻面，测量量并不是竖向高度，0.05 不能作为所有射线距离的下界。不能将这些值写成全局最小壁厚，增加预算也不能保证物理壁厚精度。旧采样漏检反例仍由 `node scripts/review-cases.cjs` 验证。

### 复现

```sh
python scripts/prepare-scan.py
node scripts/corpus-cases.cjs --check
node scripts/review-cases.cjs
node scripts/stress-cases.cjs
```

常规 CI 离线使用随仓库的已许可文件，不临时下载模型。大模型和修复输出写入已忽略的 `_build/corpus/`；性能结果见下节，不把 50 MB 模型推入 Git 历史。OpenSCAD 2021.01（GPL-2.0 工具，仅本地执行、不随仓库分发）用于可复现 CAD 导出；重建命令见 `scripts/prepare-external.cjs`。CAD 源码重建可能改变三角化与面顺序；来源清单 SHA 固定的是本次实测附件，重建后必须重新审查与测试，不能承诺字节一致。网上获取的新文件必须先补齐作者、固定来源、许可证、完整条款和 SHA-256。
<!-- corpus-results:end -->

<!-- stress-results:start -->
## 大文件实测

由独立参数化闭合圆环生成，半径 R=10、r=2 mm；面数精确为 `2×n×m`。这些是有共享顶点的连通网格，不是简单重复同一面。模型写到忽略目录，100k / 500k / 1m 文件分别约 5 / 25 / 50 MB。

| 面数 | 顶点表 / 边记录 | 分块 / bench 整进程耗时 ms | 分块 / bench 观察峰值 MiB | 输出 |
| --- | --- | --- | --- | --- |
| 100,000 | 50000 / 300000 | 180.9 / 1089 | 22.4 / 99.6 | [分块](examples/corpus/performance/100k-stream-only.txt)、[交叉验证](examples/corpus/performance/100k-bench.txt) |
| 500,000 | 250000 / 1500000 | 934.1 / 5891.8 | 74.6 / 458.8 | [分块](examples/corpus/performance/500k-stream-only.txt)、[交叉验证](examples/corpus/performance/500k-bench.txt) |
| 1,000,000 | 500000 / 3000000 | 2108.9 / 12478.4 | 140.0 / 907.0 | [分块](examples/corpus/performance/1m-stream-only.txt)、[交叉验证](examples/corpus/performance/1m-bench.txt) |

环境：win32 x64，AMD Ryzen 9 8945HX with Radeon Graphics，Native release；工具版本、输入 SHA-256 和完整命令见 [性能记录](examples/corpus/performance/summary.json)。时间包括进程启动，不含模型生成和编译。每项仅单次本机观察，没有预热、重复统计或跨项目排名。内存为每 10 ms 读取一次 OS 报告的进程历史峰值，退出间隙可能漏掉峰值，属于观察下界；不是 CLI 的字段估算。

`--bench` 会顺序执行分块、全量与整块流式，并核对三角形、顶点、边界和非流形边计数；各路径工作量不同。bench 进程峰值不能当成纯全量路径的独立内存。`--stream-only` 的顶点表与边记录随规模增长，不能承诺固定总内存。CI 每次生成并验证 100k 的两个入口，不比较计时；500k/1m 用上述脚本手动复测。
<!-- stress-results:end -->
