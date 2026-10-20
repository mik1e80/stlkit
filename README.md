# stlkit

用 MoonBit 实现的三维网格工具链：读取 STL / OBJ / 3MF / PLY，检查模型的几何与拓扑问题，提供修复、分析和 SVG 预览。

**在线试用：<https://mik1e80.github.io/stlkit/>**

[检查边界与原始案例报告](docs/review-cases.md) · [统一后的申报说明](docs/submission.md)

库、命令行和网页使用同一份 MoonBit 核心代码。网页在浏览器本地处理文件，不上传模型。

## 本次修订

GitHub 源码版本为 **0.1.1**。本次修复了坐标去重碰撞、大坐标溢出、共线退化面漏检、凹多边形三角化和补洞计数，并统一了 CLI 与网页的复核结论。

**0.1.1 尚待发布到 Mooncakes；已发布的 0.1.0 不包含本次修复。** 验证本次修订请使用 GitHub 源码。

## 能做什么

| 模块 | 已实现能力 |
| --- | --- |
| 读取 | ASCII / 二进制 STL，OBJ，3MF，ASCII / 两种字节序的二进制 PLY |
| 多边形 | OBJ / PLY 的平面简单凸、凹多边形三角化；自相交或非平面多边形明确报错 |
| 3MF | ZIP / XML 读取、对象引用、嵌套变换、单位换算 |
| 网格检查 | 边界边、非流形边、退化面、声明法线、相邻面绕向；整体有符号体积为负时提示复核 |
| 壁厚 | 确定性表面采样与射线估算；按用户设定的参考阈值提示薄壁 |
| 分析 | 体积、表面积、包围盒、PCA 定向包围盒、连通零件数、欧拉数、重心、转动惯量 |
| 修复 | 删除退化与重复面、简单边界环补洞、统一绕向、重算法线，并重新检查 |
| 导出 | ASCII / 二进制 STL、OBJ、ASCII / 二进制 PLY |
| 预览 | 等轴测 SVG |
| 流式 | 二进制 STL 分块扫描；不保存完整文件和三角形数组，仍保留顶点表和边表 |

## 使用

先安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，再获取源码：

```bash
git clone https://github.com/mik1e80/stlkit
cd stlkit
moon update
moon run cmd/main examples/cube.stl
```

```bash
moon run cmd/main examples/broken.stl --strict
moon run cmd/main examples/broken.stl --fix fixed.stl
moon run cmd/main examples/torus.obj --svg torus.svg
moon run cmd/main model.stl --min-thickness 0.5 --strict
```

`--min-thickness` 的单位是毫米，默认参考值为 0.8；应按材料和设备调整，设为 0 可关闭薄壁阈值提醒。`--strict` 在发现需复核问题时退出 1；普通模式可正常输出问题报告。参数或文件错误也退出 1。

`--samples 1000` 指定射线预算（CLI 范围 1..100000）。`--nozzle 0.4 --supports off` 只记录场景，不推导壁厚阈值，不计算喷嘴适配或支撑需求。所有报告明确标记工艺未评估，退出 0 不构成可打印结论。

网页版支持拖入模型、调整参考壁厚、查看报告与预览、下载修复结果。也可双击本地 `web/index.html`；仓库附带编译好的 `web/dist/web.js`。

已发布的库可通过 `moon add mik1e80/stlkit` 安装。库接口和本次源码新增的 `check_printability()` 见 [README.mbt.md](README.mbt.md)。

## 如何理解结果

- **检查通过不等于保证打印成功。** 本工具没有覆盖网格自相交、全部非流形顶点、支撑需求、材料与切片工艺等所有条件。
- 壁厚字段表示**采样最小厚度**，可能漏掉局部薄处。开放或朝向异常的模型不作可靠壁厚评估。
- STL / OBJ / PLY 没有在本工具中提供可靠的物理单位声明，默认按毫米解释；3MF 按声明换算到毫米。使用前请确认单位。
- 内部 `Mesh` 是三角形列表；拓扑分析统一按容差重建顶点关系，不保留 OBJ / PLY / 3MF 原始顶点身份。默认焊接容差为 1e-6 毫米，格子边界两侧的点可能不会合并。
- PCA 定向包围盒不是最小体积包围盒；体积和质量属性需结合闭合性与绕向解释。
- 自动补洞只适合简单边界环，复杂、凹形或非平面洞可能需要手工处理。修复后仍需检查模型。

## 大文件

```bash
moon run cmd/main model.stl --bench
moon run cmd/main examples/review/cubes-64.stl --stream-only
```

基准入口会比较全量、整块流式和分块流式结果，并记录耗时。**它会运行全量解析，不是仅流式的低内存命令。** 分块入口 `StlScanner::feed()` / `finish()` 可供调用方独立使用。

`--stream-only` 只做二进制 STL 分块统计，不执行全量解析、壁厚或修复。读取缓冲区为 256 KiB，但顶点去重表和全部三角形边记录仍增长，总存储 O(V+R+chunk)，非退化输入 R=3F，不是固定总内存。`StlScanner::storage()` 提供逻辑记录计数及单次缓冲峰值，不是 RSS；排序、容器容量及运行时还有额外存储。此前的固定内存节省比例已撤回。

## 验证与开发

```bash
moon check --target all --deny-warn
moon build
moon test
moon test --target js
moon test --target native
node cmd/main/smoke.cjs
bash web/build.sh
node web/smoke.cjs
node scripts/review-cases.cjs
```

回归测试覆盖正常模型、损坏输入、坐标碰撞、大坐标、共线退化面、凹多边形、多个独立破洞及报告边界。网页检查执行实际 MoonBit 编译产物，使用最小 DOM 验证报告与修复逻辑；不代替浏览器布局检查。

[CI](.github/workflows/ci.yml) 执行检查、构建、测试、网页构建与报告回归。[Pages 工作流](.github/workflows/pages.yml) 重新构建并检查网页产物后部署。

17 个第三方 3MF 文件来自官方样例库；其余案例由项目自建。读取成功只证明已支持的几何路径可处理这些文件，不表示覆盖完整 3MF 规范或所有扩展。

## 文档与来源

- [接口、实现与边界](README.mbt.md)
- [同类项目对比](COMPARISON.md)
- [示例模型](examples/README.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

参考 trimesh 的 API 与模块设计。trimesh 也提供壁厚查询；本项目的区别在于 MoonBit 实现、三后端和库 / CLI / 网页的使用方式，详见对比文档。

本项目采用 [Apache-2.0](LICENSE)。随附 3MF 样例采用 BSD-2-Clause；版权、许可条款与免责声明完整保存在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。


## 输入边界补充（2026-10-17）

ASCII STL / OBJ 的坐标和被读取的法线必须有限；二进制 STL 全量读取同样拒绝非有限坐标与法线。二进制流式路径不读取法线，但拒绝非有限顶点；分块扫描遇错后保留错误，finish() 返回 Err。

3MF 拒绝非有限变换、嵌套变换或坐标计算溢出，以及单位换算后的坐标溢出。当前不实现扩展语义：非空 requiredextensions 一律明确拒绝；可选扩展仍可忽略。因此成功读取核心三角网格不表示完整支持所有 3MF 扩展。

`moon run cmd/main examples/nonfinite-rejected.obj --strict` 应拒绝输入并以 1 退出，不生成检查通过结论。内存构造的 3MF、二进制 STL 与分块反例见 input_boundary_wbtest.mbt。变更与兼容约定见 [CHANGELOG.md](CHANGELOG.md)。
